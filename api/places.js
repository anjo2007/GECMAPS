import { kv } from '@vercel/kv';
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
        nodeEnv: process.env.NODE_ENV,
        isVercel: !!process.env.VERCEL,
      });
    }

    try {
      // 1. Try Vercel KV first
      if (kvUrl && kvToken) {
        const places = await kv.get(PLACES_KEY) || [];
        return response.status(200).json(places);
      }
      // 2. Try GitHub Gist
      if (ghToken && gistId) {
        const places = await getGistPlaces(ghToken, gistId);
        return response.status(200).json(places);
      }
      // 3. Try GitHub Repo
      if (ghToken && ghRepo) {
        const places = await getRepoPlaces(ghToken, ghRepo);
        return response.status(200).json(places);
      }
      // 4. Try local file if in dev mode
      if (isDev) {
        const places = readLocalCache();
        return response.status(200).json(places);
      }
      
      // 5. Ephemeral cache fallback
      console.warn('No cloud database configured. Using ephemeral memory cache.');
      if (!memoryCache) memoryCache = [];
      return response.status(200).json(memoryCache);

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

      // Fetch existing list based on configured driver
      if (kvUrl && kvToken) {
        placesList = await kv.get(PLACES_KEY) || [];
        source = 'kv';
      } else if (ghToken && gistId) {
        placesList = await getGistPlaces(ghToken, gistId);
        source = 'gist';
      } else if (ghToken && ghRepo) {
        placesList = await getRepoPlaces(ghToken, ghRepo);
        source = 'repo';
      } else if (isDev) {
        placesList = readLocalCache();
        source = 'local';
      } else {
        if (!memoryCache) memoryCache = [];
        placesList = memoryCache;
      }

      // De-duplicate items (newer place overrides older place with same ID)
      const filtered = placesList.filter(p => p.id !== newPlace.id);
      filtered.push(newPlace);

      // Save list back
      if (kvUrl && kvToken) {
        await kv.set(PLACES_KEY, filtered);
      } else if (ghToken && gistId) {
        await saveGistPlaces(ghToken, gistId, filtered);
      } else if (ghToken && ghRepo) {
        await saveRepoPlaces(ghToken, ghRepo, 'places.json', filtered);
      } else if (isDev) {
        writeLocalCache(filtered);
      } else {
        memoryCache = filtered;
      }

      return response.status(200).json({ success: true, place: newPlace, source });

    } catch (error) {
      console.error('Write handler error:', error);
      return response.status(500).json({ error: 'Failed to save place data', details: error.message });
    }
  }

  return response.status(405).json({ error: 'Method not allowed' });
}
