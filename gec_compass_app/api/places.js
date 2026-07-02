import { kv, createClient } from '@vercel/kv';
import fs from 'fs';
import path from 'path';

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

// GitHub Gist Driver
async function getGistPlaces(token, gistId) {
  const res = await fetch(`https://api.github.com/gists/${gistId}`, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'GEC-Compass-API'
    }
  });
  if (!res.ok) throw new Error(`Gist fetch error: ${res.statusText}`);
  const gist = await res.json();
  const file = Object.values(gist.files)[0];
  return JSON.parse(file.content);
}

async function saveGistPlaces(token, gistId, places) {
  let fileName = 'places.json';
  try {
    const res = await fetch(`https://api.github.com/gists/${gistId}`, {
      headers: {
        'Authorization': `Bearer ${token}`,
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

  const res = await fetch(`https://api.github.com/gists/${gistId}`, {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github.v3+json',
      'Content-Type': 'application/json',
      'User-Agent': 'GEC-Compass-API'
    },
    body: JSON.stringify({
      files: {
        [fileName]: {
          content: JSON.stringify(places, null, 2)
        }
      }
    })
  });
  return res.ok;
}

// GitHub Repository Driver
async function getRepoPlaces(token, repo, filePath = 'places.json') {
  const res = await fetch(`https://api.github.com/repos/${repo}/contents/${filePath}`, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'GEC-Compass-API'
    }
  });
  if (!res.ok) {
    if (res.status === 404) return [];
    throw new Error(`Repo fetch error: ${res.statusText}`);
  }
  const fileData = await res.json();
  const content = Buffer.from(fileData.content, 'base64').toString('utf-8');
  return JSON.parse(content);
}

async function saveRepoPlaces(token, repo, filePath = 'places.json', places) {
  let sha;
  try {
    const res = await fetch(`https://api.github.com/repos/${repo}/contents/${filePath}`, {
      headers: {
        'Authorization': `Bearer ${token}`,
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
      'Authorization': `Bearer ${token}`,
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

// Unified write function
async function writePlaces(driver, isBackup, places, context) {
  const { kvUrl, kvToken, ghToken, gistId, ghRepo, backupKvUrl, backupKvToken, backupGistId, backupGhRepo, PLACES_KEY } = context;
  
  switch (driver) {
    case 'kv':
      if (isBackup && backupKvUrl && backupKvToken) {
        const customKv = createClient({ url: backupKvUrl, token: backupKvToken });
        await customKv.set(PLACES_KEY, places);
        return true;
      }
      await kv.set(PLACES_KEY, places);
      return true;
      
    case 'gist':
      const targetGistId = isBackup ? (backupGistId || gistId) : gistId;
      return await saveGistPlaces(ghToken, targetGistId, places);
      
    case 'repo':
      const targetRepo = isBackup ? (backupGhRepo || ghRepo) : ghRepo;
      return await saveRepoPlaces(ghToken, targetRepo, 'places.json', places);
      
    case 'local':
      return writeLocalCache(places);
      
    case 'memory':
      memoryCache = places;
      return true;
      
    default:
      return false;
  }
}

export default async function handler(request, response) {
  // CORS Headers
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (request.method === 'OPTIONS') {
    return response.status(200).end();
  }

  const PLACES_KEY = 'gec_compass_custom_places';

  // Read environment variables
  const kvUrl = process.env.KV_REST_API_URL;
  const kvToken = process.env.KV_REST_API_TOKEN;
  const ghToken = process.env.GITHUB_TOKEN;
  const gistId = process.env.GIST_ID;
  const ghRepo = process.env.GITHUB_REPO; // e.g. "anjo2007/GECMAPS"

  const backupKvUrl = process.env.BACKUP_KV_REST_API_URL;
  const backupKvToken = process.env.BACKUP_KV_REST_API_TOKEN;
  const backupGistId = process.env.BACKUP_GIST_ID;
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
    // Safe environment diagnostic check (does not leak secret values)
    const urlObj = new URL(request.url || '', `http://${request.headers.host || 'localhost'}`);
    if (urlObj.searchParams.get('debug') === 'true') {
      return response.status(200).json({
        hasKvUrl: !!kvUrl,
        hasKvToken: !!kvToken,
        hasGhToken: !!ghToken,
        hasGistId: !!gistId,
        hasGhRepo: !!ghRepo,
        hasBackupKvUrl: !!backupKvUrl,
        hasBackupKvToken: !!backupKvToken,
        hasBackupGistId: !!backupGistId,
        hasBackupGhRepo: !!backupGhRepo,
        primaryDriver,
        backupDriver,
        nodeEnv: process.env.NODE_ENV,
        isVercel: !!process.env.VERCEL,
      });
    }

    try {
      // Try primary driver first
      try {
        const places = await readPlaces(primaryDriver, false, context);
        return response.status(200).json(places);
      } catch (primaryError) {
        console.error(`Primary driver (${primaryDriver}) read failed:`, primaryError);
        
        // Try backup driver if configured
        if (backupDriver) {
          console.log(`Attempting read from backup driver: ${backupDriver}`);
          try {
            const places = await readPlaces(backupDriver, true, context);
            return response.status(200).json(places);
          } catch (backupError) {
            console.error(`Backup driver (${backupDriver}) read failed:`, backupError);
          }
        }
        
        // Fallback to local (if dev) or memory
        if (isDev && primaryDriver !== 'local' && backupDriver !== 'local') {
          console.log('Falling back to local cache read');
          return response.status(200).json(readLocalCache());
        }
        
        console.log('Falling back to memory cache read');
        if (!memoryCache) memoryCache = [];
        return response.status(200).json(memoryCache);
      }
    } catch (error) {
      console.error('Read handler error:', error);
      return response.status(500).json({ error: 'Failed to read places data', details: error.message });
    }
  }

  if (request.method === 'POST') {
    const newPlace = parseBody(request.body);
    
    // Basic validation
    if (!newPlace || !newPlace.id || !newPlace.name) {
      return response.status(400).json({ error: 'Invalid place data structure' });
    }

    try {
      let placesList = [];
      let source = 'memory';

      // Fetch existing list (try primary, fallback to backup, then local/memory)
      try {
        placesList = await readPlaces(primaryDriver, false, context);
        source = primaryDriver;
      } catch (primaryError) {
        console.error(`Primary driver (${primaryDriver}) read failed during save:`, primaryError);
        if (backupDriver) {
          try {
            placesList = await readPlaces(backupDriver, true, context);
            source = backupDriver + '_backup';
          } catch (backupError) {
            console.error(`Backup driver (${backupDriver}) read failed during save:`, backupError);
            if (isDev) {
              placesList = readLocalCache();
              source = 'local';
            } else {
              placesList = memoryCache || [];
              source = 'memory';
            }
          }
        } else {
          if (isDev) {
            placesList = readLocalCache();
            source = 'local';
          } else {
            placesList = memoryCache || [];
            source = 'memory';
          }
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
    } catch (error) {
      console.error('DELETE handler error:', error);
      return response.status(500).json({ error: 'Failed to delete places data', details: error.message });
    }
  }

  return response.status(405).json({ error: 'Method not allowed' });
}
