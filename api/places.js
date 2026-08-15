import { kv, createClient } from '@vercel/kv';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

// Ephemeral in-memory cache for production fallback if no DB is configured
let memoryCache = null;

// Path for local cache file in development
const LOCAL_CACHE_PATH = path.join(process.cwd(), 'api', 'places_local_cache.json');

// Helper to check if running locally
const isDev = process.env.NODE_ENV === 'development' || !process.env.VERCEL;

// Safely parse JSON body from different potential types
function parseBody(body) {
  if (!body) return null;
  if (typeof body === 'object') return body;
  
  try {
    if (typeof body === 'string') {
      return JSON.parse(body);
    }
    if (Buffer.isBuffer(body)) {
      return JSON.parse(body.toString('utf-8'));
    }
  } catch (e) {
    console.error('Failed to parse request body as JSON:', e);
  }
  return null;
}

// Cloudinary Media Upload Helper
async function uploadToCloudinary(base64Data, folder = 'gec_compass_places') {
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
  const uploadPreset = process.env.CLOUDINARY_UPLOAD_PRESET;

  if (!cloudName || !base64Data) return null;

  try {
    const dataUri = base64Data.startsWith('data:image') 
      ? base64Data 
      : `data:image/jpeg;base64,${base64Data}`;

    const formData = new URLSearchParams();
    formData.append('file', dataUri);
    formData.append('folder', folder);
    if (uploadPreset) {
      formData.append('upload_preset', uploadPreset);
    }

    const endpoint = `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`;
    const res = await fetch(endpoint, {
      method: 'POST',
      body: formData
    });

    if (res.ok) {
      const json = await res.json();
      return json.secure_url || json.url;
    } else {
      console.error('Cloudinary upload error status:', res.status, await res.text());
    }
  } catch (e) {
    console.error('Cloudinary upload exception:', e);
  }
  return null;
}

// GitHub Gist Driver
function getAuthHeader(token) {
  if (!token) return '';
  const trimmed = token.trim();
  if (trimmed.startsWith('ghp_') || trimmed.startsWith('github_pat_')) {
    return `token ${trimmed}`;
  }
  return `Bearer ${trimmed}`;
}

async function getGistPlaces(token, gistId) {
  // Strategy: Try lightweight raw URL FIRST (avoids massive Gist API JSON wrapper),
  // then fall back to full API if raw URL fails.

  // 1. Direct Raw Gist Fetch (fastest, smallest response — just the JSON content)
  try {
    const rawRes = await fetch(`https://gist.githubusercontent.com/anjo2007/${gistId}/raw/places.json`, {
      headers: { 'User-Agent': 'GEC-Compass-API', 'Cache-Control': 'no-cache' }
    });
    if (rawRes.ok) {
      const rawText = await rawRes.text();
      const parsed = JSON.parse(rawText);
      console.log(`getGistPlaces: raw URL returned ${Array.isArray(parsed) ? parsed.length : 0} places`);
      return parsed;
    }
    console.error('getGistPlaces: raw URL returned status', rawRes.status);
  } catch (rawErr) {
    console.error('getGistPlaces: raw URL fetch error:', rawErr?.message || rawErr);
  }

  // 2. Full Gist API (includes metadata wrapper — larger download, but works if raw URL changes)
  try {
    const headers = {
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'GEC-Compass-API'
    };
    if (token) {
      headers['Authorization'] = getAuthHeader(token);
    }

    const res = await fetch(`https://api.github.com/gists/${gistId}`, { headers });
    if (res.ok) {
      const gist = await res.json();
      if (gist.files && Object.keys(gist.files).length > 0) {
        const file = Object.values(gist.files)[0];
        // If content is truncated, fetch via raw_url
        if (file.truncated && file.raw_url) {
          const rawRes = await fetch(file.raw_url, { headers });
          if (rawRes.ok) {
            const rawText = await rawRes.text();
            return JSON.parse(rawText);
          }
        }
        if (file.content) {
          return JSON.parse(file.content);
        }
      }
    } else {
      console.error('getGistPlaces: API returned status', res.status);
    }
  } catch (apiErr) {
    console.error('getGistPlaces: API fetch error:', apiErr?.message || apiErr);
  }

  return [];
}

// Strips base64 image data from a place to keep Gist size manageable.
// Preserves Cloudinary/HTTP URLs but removes raw data: URIs and base64 strings.
function stripBase64FromPlace(place) {
  if (!place) return place;
  const cleaned = { ...place };
  const isBase64 = (val) => typeof val === 'string' && (val.startsWith('data:image') || (val.length > 1000 && !/^https?:\/\//.test(val)));

  // Strip top-level base64 fields
  if (isBase64(cleaned.photoUrl)) delete cleaned.photoUrl;
  if (isBase64(cleaned.photoBase64)) delete cleaned.photoBase64;
  if (isBase64(cleaned.photo)) delete cleaned.photo;
  if (isBase64(cleaned.vpsBoardPhotoUrl)) delete cleaned.vpsBoardPhotoUrl;
  if (isBase64(cleaned.vpsBoardPhotoBase64)) delete cleaned.vpsBoardPhotoBase64;
  if (isBase64(cleaned.vpsBoardPhoto)) delete cleaned.vpsBoardPhoto;

  // Strip base64 from tags
  if (cleaned.tags && typeof cleaned.tags === 'object') {
    cleaned.tags = { ...cleaned.tags };
    if (isBase64(cleaned.tags.image)) delete cleaned.tags.image;
    if (isBase64(cleaned.tags.photoUrl)) delete cleaned.tags.photoUrl;
    if (isBase64(cleaned.tags.vpsBoardPhotoUrl)) delete cleaned.tags.vpsBoardPhotoUrl;
  }

  return cleaned;
}

async function saveGistPlaces(token, gistId, places) {
  const authHeader = getAuthHeader(token);
  let fileName = 'places.json';
  try {
    const res = await fetch(`https://api.github.com/gists/${gistId}`, {
      headers: {
        'Authorization': authHeader,
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'GEC-Compass-API'
      }
    });
    if (res.ok) {
      const gist = await res.json();
      const files = Object.keys(gist.files);
      if (files.length > 0) fileName = files[0];
    }
  } catch (e) {
    console.error('Error finding gist filename, defaulting to places.json:', e);
  }

  const content = JSON.stringify(places, null, 2);
  console.log(`saveGistPlaces: writing ${Array.isArray(places) ? places.length : 0} places (${(content.length / 1024).toFixed(1)} KB) to ${fileName}`);

  const res = await fetch(`https://api.github.com/gists/${gistId}`, {
    method: 'PATCH',
    headers: {
      'Authorization': authHeader,
      'Accept': 'application/vnd.github.v3+json',
      'Content-Type': 'application/json',
      'User-Agent': 'GEC-Compass-API'
    },
    body: JSON.stringify({
      files: {
        [fileName]: {
          content: content
        }
      }
    })
  });
  if (!res.ok) {
    console.error(`saveGistPlaces PATCH error (${res.status}):`, await res.text());
  }
  return res.ok;
}

// GitHub Repository Driver
async function getRepoPlaces(token, repo, filePath = 'places.json') {
  const headers = {
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'GEC-Compass-API'
  };
  if (token) {
    headers['Authorization'] = getAuthHeader(token);
  }

  const res = await fetch(`https://api.github.com/repos/${repo}/contents/${filePath}`, { headers });
  if (!res.ok) {
    if (res.status === 404) return [];
    const errText = await res.text();
    console.error(`Repo fetch error (${res.status}):`, errText);
    throw new Error(`Repo fetch error: ${res.statusText}`);
  }
  const fileData = await res.json();
  const content = Buffer.from(fileData.content, 'base64').toString('utf-8');
  return JSON.parse(content);
}

async function saveRepoPlaces(token, repo, filePath = 'places.json', places) {
  const authHeader = getAuthHeader(token);
  let sha;
  try {
    const res = await fetch(`https://api.github.com/repos/${repo}/contents/${filePath}`, {
      headers: {
        'Authorization': authHeader,
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'GEC-Compass-API'
      }
    });
    if (res.ok) {
      const fileData = await res.json();
      sha = fileData.sha;
    }
  } catch (e) {
    console.error('Error fetching file SHA:', e);
  }

  const res = await fetch(`https://api.github.com/repos/${repo}/contents/${filePath}`, {
    method: 'PUT',
    headers: {
      'Authorization': authHeader,
      'Accept': 'application/vnd.github.v3+json',
      'Content-Type': 'application/json',
      'User-Agent': 'GEC-Compass-API'
    },
    body: JSON.stringify({
      message: 'Update custom places [skip ci]',
      content: Buffer.from(JSON.stringify(places, null, 2)).toString('base64'),
      sha: sha
    })
  });
  if (!res.ok) {
    console.error(`saveRepoPlaces PUT error (${res.status}):`, await res.text());
  }
  return res.ok;
}

// Local File cache helpers for local development
function readLocalCache() {
  try {
    if (fs.existsSync(LOCAL_CACHE_PATH)) {
      const content = fs.readFileSync(LOCAL_CACHE_PATH, 'utf-8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error('Local cache read error:', e);
  }
  return [];
}

function writeLocalCache(places) {
  try {
    const dir = path.dirname(LOCAL_CACHE_PATH);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(LOCAL_CACHE_PATH, JSON.stringify(places, null, 2), 'utf-8');
    return true;
  } catch (e) {
    console.error('Local cache write error:', e);
    return false;
  }
}

// Unified read function
async function readPlaces(driver, isBackup, context) {
  const { kvUrl, kvToken, ghToken, gistId, ghRepo, backupKvUrl, backupKvToken, backupGistId, backupGhRepo, PLACES_KEY } = context;
  
  switch (driver) {
    case 'kv':
      if (isBackup && backupKvUrl && backupKvToken) {
        const customKv = createClient({ url: backupKvUrl, token: backupKvToken });
        const data = await customKv.get(PLACES_KEY);
        return data || [];
      }
      const data = await kv.get(PLACES_KEY);
      return data || [];
      
    case 'gist':
      const targetGistId = isBackup ? (backupGistId || gistId) : gistId;
      return await getGistPlaces(ghToken, targetGistId);
      
    case 'repo':
      const targetRepo = isBackup ? (backupGhRepo || ghRepo) : ghRepo;
      return await getRepoPlaces(ghToken, targetRepo);
      
    case 'local':
      return readLocalCache();
      
    case 'memory':
      if (!memoryCache) memoryCache = [];
      return memoryCache;
      
    default:
      return [];
  }
}

function formatPlaceForStorage(place) {
  if (!place) return place;

  const photoUrl = place.photoUrl || place.photo || place.photoBase64 || place.tags?.image || place.tags?.photoUrl;
  const vpsBoardPhotoUrl = place.vpsBoardPhotoUrl || place.vpsBoardPhoto || place.vpsBoardPhotoBase64 || place.tags?.vpsBoardPhotoUrl;

  const tags = place.tags ? { ...place.tags } : {};
  if (photoUrl) {
    tags.image = tags.image || photoUrl;
    tags.photoUrl = tags.photoUrl || photoUrl;
  }
  if (vpsBoardPhotoUrl) {
    tags.vpsBoardPhotoUrl = tags.vpsBoardPhotoUrl || vpsBoardPhotoUrl;
  }
  const isDeleted = place.deleted === true || place.tags?.deleted === true || place.deleted === 'true' || place.tags?.deleted === 'true';

  const cleanPlace = {
    id: String(place.id),
    name: String(place.name),
    lat: Number(place.lat || 0),
    lng: Number(place.lng || 0),
    tags
  };

  if (isDeleted) {
    cleanPlace.deleted = true;
    cleanPlace.tags.deleted = true;
    cleanPlace.deletedAt = place.deletedAt || new Date().toISOString();
  }

  if (photoUrl) cleanPlace.photoUrl = photoUrl;
  if (vpsBoardPhotoUrl) cleanPlace.vpsBoardPhotoUrl = vpsBoardPhotoUrl;

  return cleanPlace;
}

// Unified write function
async function writePlaces(driver, isBackup, places, context) {
  const { kvUrl, kvToken, ghToken, gistId, ghRepo, backupKvUrl, backupKvToken, backupGistId, backupGhRepo, PLACES_KEY } = context;
  const cleanPlaces = Array.isArray(places) ? places.map(formatPlaceForStorage) : [];
  
  switch (driver) {
    case 'kv':
      if (isBackup && backupKvUrl && backupKvToken) {
        const customKv = createClient({ url: backupKvUrl, token: backupKvToken });
        await customKv.set(PLACES_KEY, cleanPlaces);
        return true;
      }
      await kv.set(PLACES_KEY, cleanPlaces);
      return true;
      
    case 'gist':
      const targetGistId = isBackup ? (backupGistId || gistId) : gistId;
      return await saveGistPlaces(ghToken, targetGistId, cleanPlaces);
      
    case 'repo':
      const targetRepo = isBackup ? (backupGhRepo || ghRepo) : ghRepo;
      return await saveRepoPlaces(ghToken, targetRepo, 'places.json', cleanPlaces);
      
    case 'local':
      return writeLocalCache(cleanPlaces);
      
    case 'memory':
      memoryCache = cleanPlaces;
      return true;
      
    default:
      return false;
  }
}

export default async function handler(request, response) {
  // CORS Headers
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type, x-security-code, Authorization, *');

  if (request.method === 'OPTIONS') {
    return response.status(200).end();
  }

  const PLACES_KEY = 'gec_compass_custom_places';

  function extractGistId(input) {
    if (!input) return '553a8435d8cd2459358147935ecdd59b';
    const str = String(input).trim();
    const match = str.match(/[a-f0-9]{32}/i);
    return match ? match[0] : (str || '553a8435d8cd2459358147935ecdd59b');
  }

  // Read environment variables
  const kvUrl = process.env.KV_REST_API_URL;
  const kvToken = process.env.KV_REST_API_TOKEN;
  const ghToken = process.env.GITHUB_TOKEN ? process.env.GITHUB_TOKEN.trim() : '';
  const gistId = extractGistId(process.env.GIST_ID);
  const ghRepo = process.env.GITHUB_REPO; // e.g. "anjo2007/GECMAPS"

  const backupKvUrl = process.env.BACKUP_KV_REST_API_URL;
  const backupKvToken = process.env.BACKUP_KV_REST_API_TOKEN;
  const backupGistId = process.env.BACKUP_GIST_ID ? extractGistId(process.env.BACKUP_GIST_ID) : (gistId !== '553a8435d8cd2459358147935ecdd59b' ? '553a8435d8cd2459358147935ecdd59b' : null);
  const backupGhRepo = process.env.BACKUP_GITHUB_REPO;

  const context = {
    kvUrl,
    kvToken,
    ghToken,
    gistId,
    ghRepo,
    backupKvUrl,
    backupKvToken,
    backupGistId,
    backupGhRepo,
    PLACES_KEY
  };

  // Determine primary driver
  let primaryDriver = 'memory';
  if (kvUrl && kvToken) {
    primaryDriver = 'kv';
  } else if (ghToken && gistId) {
    primaryDriver = 'gist';
  } else if (ghToken && ghRepo) {
    primaryDriver = 'repo';
  } else if (gistId) {
    primaryDriver = 'gist';
  } else if (isDev) {
    primaryDriver = 'local';
  }

  // Determine backup driver (exclude primary driver from acting as backup)
  let backupDriver = null;
  if (backupGhRepo || (ghToken && ghRepo && primaryDriver !== 'repo')) {
    backupDriver = 'repo';
  } else if ((backupKvUrl && backupKvToken) || (kvUrl && kvToken && primaryDriver !== 'kv')) {
    backupDriver = 'kv';
  } else if (backupGistId || (ghToken && gistId && primaryDriver !== 'gist')) {
    backupDriver = 'gist';
  }

  if (request.method === 'GET') {
    const urlObj = new URL(request.url || '', `http://${request.headers.host || 'localhost'}`);
    
    // Safe environment diagnostic check (does not leak secret values)
    if (urlObj.searchParams.get('debug') === 'true') {
      let debugReadPlaces = [];
      let debugError = null;
      try {
        debugReadPlaces = await readPlaces(primaryDriver, false, context);
      } catch (err) {
        debugError = err?.message || String(err);
      }
      return response.status(200).json({
        hasKvUrl: !!kvUrl,
        hasKvToken: !!kvToken,
        hasGhToken: !!ghToken,
        hasGistId: !!gistId,
        gistIdSnippet: gistId ? `${gistId.slice(0, 6)}...` : null,
        hasGhRepo: !!ghRepo,
        hasBackupKvUrl: !!backupKvUrl,
        hasBackupKvToken: !!backupKvToken,
        hasBackupGistId: !!backupGistId,
        hasBackupGhRepo: !!backupGhRepo,
        primaryDriver,
        backupDriver,
        primaryReadCount: debugReadPlaces.length,
        debugError,
        nodeEnv: process.env.NODE_ENV,
        isVercel: !!process.env.VERCEL,
      });
    }

    try {
      let places = [];
      try {
        places = await readPlaces(primaryDriver, false, context);
      } catch (primaryError) {
        console.error(`Primary driver (${primaryDriver}) read failed:`, primaryError);
        if (backupDriver) {
          try {
            places = await readPlaces(backupDriver, true, context);
          } catch (backupError) {
            console.error(`Backup driver (${backupDriver}) read failed:`, backupError);
          }
        }
        if (places.length === 0 && isDev) {
          places = readLocalCache();
        }
      }

      // Normalize places to ensure all photo variants are unified under photoUrl and vpsBoardPhotoUrl
      const normalizedPlaces = places.map(p => {
        if (!p) return p;
        let photoUrl = p.photoUrl || p.photo || p.photoBase64 || p.tags?.image || p.tags?.photoUrl;
        let vpsUrl = p.vpsBoardPhotoUrl || p.vpsBoardPhoto || p.vpsBoardPhotoBase64 || p.tags?.vpsBoardPhotoUrl;
        let photoBase64 = p.photoBase64 || photoUrl || null;
        let vpsBoardPhotoBase64 = p.vpsBoardPhotoBase64 || vpsUrl || null;

        const tags = p.tags ? { ...p.tags } : {};
        if (photoUrl) {
          tags.image = tags.image || photoUrl;
          tags.photoUrl = tags.photoUrl || photoUrl;
        }
        if (vpsUrl) {
          tags.vpsBoardPhotoUrl = tags.vpsBoardPhotoUrl || vpsUrl;
        }

        const isDeleted = p.deleted === true || p.tags?.deleted === true || p.deleted === 'true' || p.tags?.deleted === 'true';
        if (isDeleted) {
          tags.deleted = true;
        }

        return {
          ...p,
          deleted: isDeleted ? true : undefined,
          photoUrl: photoUrl || null,
          vpsBoardPhotoUrl: vpsUrl || null,
          photoBase64: photoBase64 || null,
          vpsBoardPhotoBase64: vpsBoardPhotoBase64 || null,
          tags
        };
      });

      // Handle export backup for zero-data-loss platform migration
      if (urlObj.searchParams.get('export') === 'true' || urlObj.searchParams.get('backup') === 'true') {
        const activePlaces = normalizedPlaces.filter(p => p && !p.deleted && !p.tags?.deleted);
        response.setHeader('Content-Type', 'application/json');
        response.setHeader('Content-Disposition', 'attachment; filename="gec_compass_places_backup.json"');
        return response.status(200).send(JSON.stringify(activePlaces, null, 2));
      }

      response.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      response.setHeader('Pragma', 'no-cache');
      response.setHeader('Expires', '0');
      response.setHeader('x-storage-persistence', primaryDriver === 'memory' ? 'none' : 'persistent');
      // Return normalized places including deletion tombstones so all devices synchronize deletions
      return response.status(200).json(normalizedPlaces);
    } catch (error) {
      console.error('Read handler error:', error);
      return response.status(500).json({ error: 'Failed to read places data' });
    }
  }

  if (request.method === 'POST') {
    const newPlace = parseBody(request.body);
    
    // Basic and coordinate bounds validation
    if (!newPlace || !newPlace.id || !newPlace.name) {
      return response.status(400).json({ error: 'Invalid place data structure' });
    }

    const lat = Number(newPlace.lat);
    const lng = Number(newPlace.lng);
    if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180) {
      return response.status(400).json({ error: 'Invalid coordinates: lat must be [-90, 90] and lng must be [-180, 180]' });
    }
    if (String(newPlace.name).length > 250) {
      return response.status(400).json({ error: 'Place name exceeds maximum allowed length of 250 characters' });
    }

    // Auto-upload Base64 images to Cloudinary CDN if server has CLOUDINARY_CLOUD_NAME configured
    if (process.env.CLOUDINARY_CLOUD_NAME) {
      if (newPlace.photoBase64) {
        const uploadedUrl = await uploadToCloudinary(newPlace.photoBase64, 'gec_compass_places');
        if (uploadedUrl) {
          newPlace.photoUrl = uploadedUrl;
          if (!newPlace.tags) newPlace.tags = {};
          newPlace.tags.image = uploadedUrl;
          newPlace.tags.photoUrl = uploadedUrl;
          delete newPlace.photoBase64;
        }
      }
      if (newPlace.vpsBoardPhotoBase64) {
        const uploadedVpsUrl = await uploadToCloudinary(newPlace.vpsBoardPhotoBase64, 'gec_compass_vps');
        if (uploadedVpsUrl) {
          newPlace.vpsBoardPhotoUrl = uploadedVpsUrl;
          if (!newPlace.tags) newPlace.tags = {};
          newPlace.tags.vpsBoardPhotoUrl = uploadedVpsUrl;
          delete newPlace.vpsBoardPhotoBase64;
        }
      }
    }

    try {
      let placesList = [];
      let source = 'memory';

      // Fetch existing list (try primary, fallback to backup)
      let readSuccess = false;
      try {
        placesList = await readPlaces(primaryDriver, false, context);
        source = primaryDriver;
        readSuccess = true;
      } catch (primaryError) {
        console.error(`Primary driver (${primaryDriver}) read failed during save:`, primaryError);
        if (backupDriver) {
          try {
            placesList = await readPlaces(backupDriver, true, context);
            source = backupDriver + '_backup';
            readSuccess = true;
          } catch (backupError) {
            console.error(`Backup driver (${backupDriver}) read failed during save:`, backupError);
          }
        }
      }

      // SAFEGUARD: If persistent storage is configured but reading existing data failed,
      // ABORT SAVE to prevent overwriting/wiping out existing data with an empty array!
      if (!readSuccess && primaryDriver !== 'memory' && primaryDriver !== 'local') {
        return response.status(500).json({
          error: 'Failed to read existing places from storage. Aborting save operation to prevent data loss.'
        });
      }

      if (!readSuccess) {
        if (isDev) {
          placesList = readLocalCache();
          source = 'local';
        } else {
          placesList = memoryCache || [];
          source = 'memory';
        }
      }

      // Check if this is a new place (id not in existing list)
      const isNewPlace = !placesList.some(p => p.id === newPlace.id);

      if (isNewPlace) {
        // Distance calculation helper (Haversine in meters)
        function getDistanceMeters(lat1, lon1, lat2, lon2) {
          const R = 6371000;
          const dLat = (lat2 - lat1) * Math.PI / 180;
          const dLon = (lon2 - lon1) * Math.PI / 180;
          const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                    Math.sin(dLon/2) * Math.sin(dLon/2);
          const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
          return R * c;
        }

        const hasDuplicate = placesList.some(p => {
          if (!p || p.deleted || p.tags?.deleted) return false;
          const pNameClean = (p.name || '').trim().toLowerCase();
          const newNameClean = (newPlace.name || '').trim().toLowerCase();
          
          const dist = getDistanceMeters(p.lat, p.lng, newPlace.lat, newPlace.lng);
          const coordsMatch = dist < 2.0;

          const pFloor = p.tags && p.tags.floor ? p.tags.floor.toString().trim().toLowerCase() : '';
          const newFloor = newPlace.tags && newPlace.tags.floor ? newPlace.tags.floor.toString().trim().toLowerCase() : '';
          const pRef = p.tags && p.tags.ref ? p.tags.ref.toString().trim().toLowerCase() : '';
          const newRef = newPlace.tags && newPlace.tags.ref ? newPlace.tags.ref.toString().trim().toLowerCase() : '';
          
          const floorMatch = pFloor === newFloor;
          const refMatch = pRef === newRef;

          // Duplicate checks:
          // 1. Same name AND coordinates within 2 meters
          // 2. Same name AND same floor AND same room ref (only if room ref is not empty)
          // 3. Same coordinates AND same floor AND same room ref (only if room ref is not empty)
          return (pNameClean === newNameClean && coordsMatch) ||
                 (pNameClean === newNameClean && floorMatch && refMatch && newRef !== '') ||
                 (coordsMatch && floorMatch && refMatch && newRef !== '');
        });

        if (hasDuplicate) {
          return response.status(409).json({
            error: 'Duplicate place detected. A place with the same name, coordinates, or room details already exists.'
          });
        }
      }

      // De-duplicate items (newer place overrides older place with same ID)
      const filtered = placesList.filter(p => p.id !== newPlace.id);
      filtered.push(newPlace);

      // Save to primary driver
      let primarySaveSuccess = false;
      let primarySaveError = null;
      try {
        primarySaveSuccess = await writePlaces(primaryDriver, false, filtered, context);
      } catch (e) {
        primarySaveError = e.message;
        console.error(`Primary driver (${primaryDriver}) write failed:`, e);
      }

      // Save to backup driver if configured
      let backupSaveSuccess = false;
      let backupSaveError = null;
      if (backupDriver) {
        try {
          backupSaveSuccess = await writePlaces(backupDriver, true, filtered, context);
        } catch (e) {
          backupSaveError = e.message;
          console.error(`Backup driver (${backupDriver}) write failed:`, e);
        }
      }

      // Return response indicating status of saves
      if (primarySaveSuccess) {
        return response.status(200).json({
          success: true,
          place: newPlace,
          source,
          backupSaved: backupDriver ? backupSaveSuccess : undefined,
          backupError: backupSaveError || undefined
        });
      } else if (backupSaveSuccess) {
        // Primary failed but backup succeeded
        return response.status(200).json({
          success: true,
          place: newPlace,
          source,
          primaryError: primarySaveError || 'Primary write failed',
          backupSaved: true
        });
      } else {
        // Both failed
        throw new Error(primarySaveError || 'Write failed to all configured storage drivers');
      }

    } catch (error) {
      console.error('Write handler error:', error);
      return response.status(500).json({ error: 'Failed to save place data', details: error.message });
    }
  }

  if (request.method === 'DELETE') {
    try {
      const urlObj = new URL(request.url || '', `http://${request.headers.host || 'localhost'}`);
      const idToDelete = (request.query && request.query.id) || urlObj.searchParams.get('id');
      const enteredCode = (request.query && request.query.code) || urlObj.searchParams.get('code') || request.headers['x-security-code'];

      const isValidCode = (code) => {
        if (!code) return false;
        const inputCode = String(code).trim();
        const envCode = process.env.SECURITY_CODE ? process.env.SECURITY_CODE.trim() : null;
        const validCode = envCode || '8714743183';
        const cBuf = Buffer.from(inputCode);
        const vBuf = Buffer.from(validCode);
        return cBuf.length === vBuf.length && crypto.timingSafeEqual(cBuf, vBuf);
      };

      if (!isValidCode(enteredCode)) {
        return response.status(403).json({ error: 'Unauthorized: Invalid security code' });
      }

      if (idToDelete) {
        // Fetch existing list with safeguard
        let placesList = [];
        let readSuccess = false;
        try {
          placesList = await readPlaces(primaryDriver, false, context);
          readSuccess = true;
        } catch (primaryError) {
          if (backupDriver) {
            try {
              placesList = await readPlaces(backupDriver, true, context);
              readSuccess = true;
            } catch (_) {}
          }
        }

        if (!readSuccess && primaryDriver !== 'memory' && primaryDriver !== 'local') {
          return response.status(500).json({ error: 'Failed to read places from storage. Aborting delete operation.' });
        }

        const NinetyDaysAgo = Date.now() - (90 * 24 * 60 * 60 * 1000);
        const filtered = placesList.filter(p => {
          if (String(p.id).trim() === String(idToDelete).trim()) return false;
          // Prune tombstones older than 90 days
          const isTombstone = p.deleted === true || p.tags?.deleted === true || p.deleted === 'true' || p.tags?.deleted === 'true';
          if (isTombstone) {
            const deletedTime = p.deletedAt ? new Date(p.deletedAt).getTime() : 0;
            return deletedTime > NinetyDaysAgo;
          }
          return true;
        });

        const existingPlace = placesList.find(p => String(p.id).trim() === String(idToDelete).trim());

        filtered.push({
          ...(existingPlace || {}),
          id: String(idToDelete).trim(),
          name: existingPlace ? existingPlace.name : 'Deleted Place',
          deleted: true,
          tags: {
            ...(existingPlace && existingPlace.tags ? existingPlace.tags : {}),
            deleted: true
          },
          deletedAt: new Date().toISOString()
        });

        const writePrimary = await writePlaces(primaryDriver, false, filtered, context);
        let writeBackup = true;
        if (backupDriver) {
          try {
            writeBackup = await writePlaces(backupDriver, true, filtered, context);
          } catch (e) {
            console.error('Backup write failed during delete:', e);
            writeBackup = false;
          }
        }

        // Return error if primary write failed — prevents Flutter from falsely
        // saving a local tombstone when the cloud deletion never actually persisted.
        if (!writePrimary && primaryDriver !== 'memory') {
          return response.status(500).json({
            error: 'Failed to persist deletion to storage. Please try again.',
            primarySaved: false,
            backupSaved: writeBackup
          });
        }

        return response.status(200).json({
          success: true,
          message: `Place ${idToDelete} deleted successfully`,
          primaryDriver,
          backupDriver,
          primarySaved: writePrimary,
          backupSaved: writeBackup
        });
      } else {
        const writePrimary = await writePlaces(primaryDriver, false, [], context);
        let writeBackup = true;
        if (backupDriver) {
          writeBackup = await writePlaces(backupDriver, true, [], context);
        }
        return response.status(200).json({
          success: true,
          message: 'All custom places deleted successfully',
          primaryDriver,
          backupDriver,
          primarySaved: writePrimary,
          backupSaved: writeBackup
        });
      }
    } catch (error) {
      console.error('DELETE handler error:', error);
      return response.status(500).json({ error: 'Failed to delete places data' });
    }
  }

  return response.status(405).json({ error: 'Method not allowed' });
}
