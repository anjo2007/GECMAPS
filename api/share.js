import { kv, createClient } from '@vercel/kv';

// Ephemeral memory cache for fallback
let memoryCache = null;

// Dedicated Gist memory cache with ETag tracking to protect against GitHub API rate limits
let gistMemoryCache = {
  data: null,
  etag: null,
  timestamp: 0,
  gistId: null
};

// Helper for auth headers
function getAuthHeader(token) {
  if (!token) return '';
  const trimmed = token.trim();
  if (trimmed.startsWith('ghp_') || trimmed.startsWith('github_pat_')) {
    return `token ${trimmed}`;
  }
  return `Bearer ${trimmed}`;
}

// GitHub Gist Driver
async function getGistPlaces(token, gistId) {
  const now = Date.now();
  if (gistMemoryCache.data && gistMemoryCache.gistId === gistId && (now - gistMemoryCache.timestamp < 3500)) {
    return gistMemoryCache.data;
  }

  const headers = {
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'GEC-Compass-API'
  };
  if (token) {
    headers['Authorization'] = getAuthHeader(token);
  }
  if (gistMemoryCache.etag && gistMemoryCache.gistId === gistId) {
    headers['If-None-Match'] = gistMemoryCache.etag;
  }

  const res = await fetch(`https://api.github.com/gists/${gistId}`, { headers });
  
  if (res.status === 304 && gistMemoryCache.data) {
    gistMemoryCache.timestamp = now;
    return gistMemoryCache.data;
  }

  if (!res.ok) {
    if (gistMemoryCache.data && gistMemoryCache.gistId === gistId) {
      return gistMemoryCache.data;
    }
    throw new Error(`Gist fetch error: ${res.statusText}`);
  }

  const gist = await res.json();
  if (!gist.files || Object.keys(gist.files).length === 0) return [];
  
  let file = gist.files['places.json'];
  if (!file) {
    const jsonKey = Object.keys(gist.files).find(k => k.toLowerCase().endsWith('.json'));
    file = jsonKey ? gist.files[jsonKey] : Object.values(gist.files)[0];
  }

  let parsed = [];
  if (file.truncated && file.raw_url) {
    const rawRes = await fetch(file.raw_url, {
      headers: { 'User-Agent': 'GEC-Compass-API' }
    });
    if (rawRes.ok) {
      const rawText = await rawRes.text();
      try {
        parsed = JSON.parse(rawText);
      } catch (_) {
        parsed = [];
      }
    }
  } else if (file.content && file.content.trim().length > 0) {
    try {
      parsed = JSON.parse(file.content);
    } catch (_) {
      parsed = [];
    }
  }

  if (!Array.isArray(parsed)) {
    parsed = [];
  }

  gistMemoryCache = {
    data: parsed,
    etag: res.headers.get('etag'),
    timestamp: now,
    gistId: gistId
  };

  return parsed;
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
    throw new Error(`Repo fetch error: ${res.statusText}`);
  }
  const fileData = await res.json();
  const content = Buffer.from(fileData.content, 'base64').toString('utf-8');
  return JSON.parse(content);
}

// Load standard buildings from GitHub raw (reliable, no filesystem dependency)
async function loadStandardBuildings() {
  try {
    const res = await fetch(
      'https://raw.githubusercontent.com/anjo2007/GECMAPS/master/gec_compass_app/assets/campus_buildings.json',
      { headers: { 'User-Agent': 'GEC-Compass-API' } }
    );
    if (res.ok) {
      return await res.json();
    }
  } catch (e) {
    console.error('Failed to fetch standard buildings from GitHub:', e);
  }
  return [];
}

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
      
    case 'memory':
      if (!memoryCache) memoryCache = [];
      return memoryCache;
      
    default:
      return [];
  }
}

export default async function handler(request, response) {
  // CORS Headers
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (request.method === 'OPTIONS') {
    return response.status(200).end();
  }

  if (request.method !== 'GET') {
    return response.status(405).json({ error: 'Method not allowed' });
  }

  const urlObj = new URL(request.url || '', `http://${request.headers.host || 'localhost'}`);
  const id = urlObj.searchParams.get('id');
  const previewUrl = urlObj.searchParams.get('previewUrl') || urlObj.searchParams.get('url');
  const serveImage = urlObj.searchParams.get('image') === 'true';

  if (previewUrl) {
    try {
      const parsed = new URL(previewUrl);
      const allowedHosts = ['gecmaps.vercel.app', 'localhost', '127.0.0.1'];
      if (allowedHosts.includes(parsed.hostname.toLowerCase())) {
        return response.redirect(302, previewUrl);
      }
    } catch (_) {}
    return response.status(400).send('Invalid or unauthorized redirect URL');
  }

  if (!id) {
    return response.status(400).send('Missing id parameter');
  }

  // Load environment variables for custom places database
  const PLACES_KEY = 'gec_compass_custom_places';
  const kvUrl = process.env.KV_REST_API_URL;
  const kvToken = process.env.KV_REST_API_TOKEN;
  const ghToken = process.env.GITHUB_TOKEN;
  const gistId = process.env.GIST_ID;
  const ghRepo = process.env.GITHUB_REPO;

  const backupKvUrl = process.env.BACKUP_KV_REST_API_URL;
  const backupKvToken = process.env.BACKUP_KV_REST_API_TOKEN;
  const backupGistId = process.env.BACKUP_GIST_ID;
  const backupGhRepo = process.env.BACKUP_GITHUB_REPO;

  const context = {
    kvUrl, kvToken, ghToken, gistId, ghRepo,
    backupKvUrl, backupKvToken, backupGistId, backupGhRepo,
    PLACES_KEY
  };

  const explicitDriver = (process.env.PRIMARY_STORAGE_DRIVER || process.env.STORAGE_DRIVER || '').toLowerCase().trim();

  let primaryDriver = 'memory';
  if (explicitDriver === 'gist' && ghToken && gistId) {
    primaryDriver = 'gist';
  } else if (explicitDriver === 'kv' && kvUrl && kvToken) {
    primaryDriver = 'kv';
  } else if (explicitDriver === 'repo' && ghToken && ghRepo) {
    primaryDriver = 'repo';
  } else if (ghToken && gistId) {
    primaryDriver = 'gist';
  } else if (kvUrl && kvToken) {
    primaryDriver = 'kv';
  } else if (ghToken && ghRepo) {
    primaryDriver = 'repo';
  }

  let backupDriver = null;
  if (primaryDriver !== 'repo' && (backupGhRepo || (ghToken && ghRepo))) {
    backupDriver = 'repo';
  } else if (primaryDriver !== 'kv' && ((backupKvUrl && backupKvToken) || (kvUrl && kvToken))) {
    backupDriver = 'kv';
  } else if (primaryDriver !== 'gist' && (backupGistId || (ghToken && gistId))) {
    backupDriver = 'gist';
  }

  // 1. Fetch custom places from database
  let customPlaces = [];
  try {
    customPlaces = await readPlaces(primaryDriver, false, context);
  } catch (primaryError) {
    console.error(`Primary driver read failed in share:`, primaryError);
    if (backupDriver) {
      try {
        customPlaces = await readPlaces(backupDriver, true, context);
      } catch (backupError) {
        console.error(`Backup driver read failed in share:`, backupError);
      }
    }
  }

  // 2. Load standard buildings from GitHub raw (no filesystem dependency)
  let standardBuildings = [];
  try {
    standardBuildings = await loadStandardBuildings();
  } catch (e) {
    console.error('Error loading standard buildings in share:', e);
  }

  // 3. Find place by ID
  let place = customPlaces.find(p => p.id === id);
  if (!place) {
    place = standardBuildings.find(p => p.id === id);
  }

  const protocol = request.headers['x-forwarded-proto'] || 'https';
  const host = request.headers.host || 'gecmaps.vercel.app';
  const baseUrl = `${protocol}://${host}`;
  const redirectUrl = `${baseUrl}/?placeId=${id}`;

  // If place not found or deleted tombstone, redirect to app root without place
  if (!place || place.deleted === true || place.tags?.deleted === true) {
    return response.redirect(302, baseUrl);
  }

  const resolvedPhotoUrl = place.photoUrl || place.vpsBoardPhotoUrl || place.tags?.image || place.tags?.photoUrl;

  // If client wants the image
  if (serveImage) {
    if (resolvedPhotoUrl) {
      return response.redirect(302, resolvedPhotoUrl);
    }
    if (place.photoBase64) {
      try {
        const buffer = Buffer.from(place.photoBase64, 'base64');
        response.setHeader('Content-Type', 'image/jpeg');
        response.setHeader('Cache-Control', 'public, max-age=86400');
        return response.status(200).send(buffer);
      } catch (err) {
        console.error('Failed to decode photoBase64:', err);
      }
    }
    // Fallback to default logo
    return response.redirect(`${baseUrl}/icons/Icon-512.png`);
  }

  // Generate HTML response for sharing/crawlers
  const shareUrl = `${baseUrl}/api/share?id=${place.id}`;
  
  // Custom metadata description
  let desc = 'Locate departments, labs, classrooms, and amenities at GEC Thrissur with real-time GPS & offline routing.';
  if (place.tags) {
    const amenity = place.tags.amenity || place.tags.building || place.tags.tourism || '';
    const floor = place.tags.floor ? `Floor ${place.tags.floor}` : '';
    const ref = place.tags.ref ? `Room ${place.tags.ref}` : '';
    const details = [ref, floor, amenity].filter(Boolean).join(', ');
    if (details) {
      desc = `${place.name} (${details}) - view details and get walking directions on GECT Compass.`;
    } else {
      desc = `View ${place.name} and get walking directions on GECT Compass.`;
    }
  }

  const imageUrl = resolvedPhotoUrl 
    ? resolvedPhotoUrl 
    : (place.photoBase64 
        ? `${baseUrl}/api/share?id=${place.id}&image=true` 
        : `${baseUrl}/icons/Icon-512.png`);

  // Escape special HTML characters to prevent XSS
  const escHtml = (str) => String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>${escHtml(place.name)} | GECT Compass</title>
  <meta name="description" content="${escHtml(desc)}">
  <meta name="keywords" content="${escHtml(place.name)}, GEC Maps, GECT Maps, GEC Compass, GECT Compass, GEC Navigator, GEC Thrissur">
  <link rel="canonical" href="${escHtml(redirectUrl)}">
  
  <!-- Open Graph / Facebook / WhatsApp -->
  <meta property="og:type" content="website">
  <meta property="og:url" content="${escHtml(shareUrl)}">
  <meta property="og:title" content="${escHtml(place.name)} | GECT Compass">
  <meta property="og:description" content="${escHtml(desc)}">
  <meta property="og:image" content="${escHtml(imageUrl)}">
  <meta property="og:site_name" content="GECT Compass">

  <!-- Twitter -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:url" content="${escHtml(shareUrl)}">
  <meta name="twitter:title" content="${escHtml(place.name)} | GECT Compass">
  <meta name="twitter:description" content="${escHtml(desc)}">
  <meta name="twitter:image" content="${escHtml(imageUrl)}">

  <!-- JSON-LD Structured Data for Location -->
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "Place",
    "name": ${JSON.stringify(place.name)},
    "description": ${JSON.stringify(desc)},
    "url": ${JSON.stringify(redirectUrl)},
    "hasMap": ${JSON.stringify(redirectUrl)},
    "image": ${JSON.stringify(imageUrl)},
    ${place.lat && place.lng ? `"geo": {
      "@type": "GeoCoordinates",
      "latitude": ${place.lat},
      "longitude": ${place.lng}
    },` : ''}
    "address": {
      "@type": "PostalAddress",
      "addressLocality": "Thrissur",
      "addressRegion": "Kerala",
      "postalCode": "680009",
      "addressCountry": "IN"
    },
    "containedInPlace": {
      "@type": "CollegeOrUniversity",
      "name": "Government Engineering College Thrissur",
      "url": "http://gectcr.ac.in/"
    }
  }
  </script>

  <!-- Redirect to the main application with placeId parameter -->
  <meta http-equiv="refresh" content="0;url=${escHtml(redirectUrl)}">
  <script>
    window.location.href = ${JSON.stringify(redirectUrl)};
  </script>
</head>
<body>
  <p>Redirecting to <a href="${escHtml(redirectUrl)}">${escHtml(place.name)} on GEC Maps & GECT Compass</a>...</p>
</body>
</html>`;

  response.setHeader('Content-Type', 'text/html; charset=utf-8');
  response.setHeader('Cache-Control', 'public, s-maxage=3600');
  return response.status(200).send(html);
}
