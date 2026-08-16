import { kv, createClient } from '@vercel/kv';
import fs from 'fs';
import path from 'path';

// Helper to load standard buildings
async function loadStandardBuildings() {
  // Try local file first (fastest in Node environment)
  try {
    const localPath = path.join(process.cwd(), 'gec_compass_app', 'assets', 'campus_buildings.json');
    if (fs.existsSync(localPath)) {
      const data = fs.readFileSync(localPath, 'utf-8');
      return JSON.parse(data);
    }
  } catch (e) {
    console.error('Failed to load local campus_buildings.json:', e);
  }

  // Fallback to GitHub raw
  try {
    const res = await fetch(
      'https://raw.githubusercontent.com/anjo2007/GECMAPS/master/gec_compass_app/assets/campus_buildings.json',
      { headers: { 'User-Agent': 'GEC-Compass-API' } }
    );
    if (res.ok) {
      return await res.json();
    }
  } catch (e) {
    console.error('Failed to fetch campus_buildings.json from GitHub:', e);
  }
  return [];
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
  if (!res.ok) return [];
  const gist = await res.json();
  const file = Object.values(gist.files)[0];
  if (file.truncated && file.raw_url) {
    const rawRes = await fetch(file.raw_url, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'User-Agent': 'GEC-Compass-API'
      }
    });
    if (rawRes.ok) return JSON.parse(await rawRes.text());
  }
  return JSON.parse(file.content);
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
  if (!res.ok) return [];
  const fileData = await res.json();
  const content = Buffer.from(fileData.content, 'base64').toString('utf-8');
  return JSON.parse(content);
}

async function readPlaces(driver, isBackup, context) {
  const { kvUrl, kvToken, ghToken, gistId, ghRepo, backupKvUrl, backupKvToken, backupGistId, backupGhRepo, PLACES_KEY } = context;
  try {
    switch (driver) {
      case 'kv':
        if (isBackup && backupKvUrl && backupKvToken) {
          const customKv = createClient({ url: backupKvUrl, token: backupKvToken });
          return (await customKv.get(PLACES_KEY)) || [];
        }
        return (await kv.get(PLACES_KEY)) || [];
      case 'gist':
        return await getGistPlaces(ghToken, isBackup ? (backupGistId || gistId) : gistId);
      case 'repo':
        return await getRepoPlaces(ghToken, isBackup ? (backupGhRepo || ghRepo) : ghRepo);
      default:
        return [];
    }
  } catch (e) {
    console.error(`Read error for driver ${driver}:`, e);
    return [];
  }
}

function escapeXml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

export default async function handler(request, response) {
  const protocol = request.headers['x-forwarded-proto'] || 'https';
  const host = request.headers.host || 'gecmaps.vercel.app';
  const baseUrl = `${protocol}://${host}`;
  const today = new Date().toISOString().split('T')[0];

  // Load environment variables for custom places
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

  let primaryDriver = 'memory';
  if (kvUrl && kvToken) primaryDriver = 'kv';
  else if (ghToken && gistId) primaryDriver = 'gist';
  else if (ghToken && ghRepo) primaryDriver = 'repo';

  let backupDriver = null;
  if (backupGhRepo || (ghToken && ghRepo && primaryDriver !== 'repo')) backupDriver = 'repo';
  else if ((backupKvUrl && backupKvToken) || (kvUrl && kvToken && primaryDriver !== 'kv')) backupDriver = 'kv';
  else if (backupGistId || (ghToken && gistId && primaryDriver !== 'gist')) backupDriver = 'gist';

  let standardBuildings = await loadStandardBuildings();
  let customPlaces = [];
  try {
    customPlaces = await readPlaces(primaryDriver, false, context);
  } catch (_) {
    if (backupDriver) {
      try {
        customPlaces = await readPlaces(backupDriver, true, context);
      } catch (_) {}
    }
  }

  // Combine and deduplicate places by ID, excluding deleted tombstones
  const placeMap = new Map();
  for (const place of [...standardBuildings, ...customPlaces]) {
    if (place && place.id && place.name && place.name !== 'Unnamed Location' && !place.deleted && !place.tags?.deleted) {
      placeMap.set(place.id, place);
    }
  }

  const places = Array.from(placeMap.values());

  // Generate XML string
  let xml = `<?xml version="1.0" encoding="UTF-8"?>\n`;
  xml += `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n`;
  xml += `        xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">\n`;

  // Root homepage
  xml += `  <url>\n`;
  xml += `    <loc>${baseUrl}/</loc>\n`;
  xml += `    <lastmod>${today}</lastmod>\n`;
  xml += `    <changefreq>daily</changefreq>\n`;
  xml += `    <priority>1.0</priority>\n`;
  xml += `    <image:image>\n`;
  xml += `      <image:loc>${baseUrl}/icons/Icon-512.png</image:loc>\n`;
  xml += `      <image:title>GECT Compass - GEC Thrissur Campus Map</image:title>\n`;
  xml += `      <image:caption>Interactive campus map &amp; navigation system for Government Engineering College Thrissur.</image:caption>\n`;
  xml += `    </image:image>\n`;
  xml += `  </url>\n`;

  // About page
  xml += `  <url>\n`;
  xml += `    <loc>${baseUrl}/about</loc>\n`;
  xml += `    <lastmod>${today}</lastmod>\n`;
  xml += `    <changefreq>monthly</changefreq>\n`;
  xml += `    <priority>0.8</priority>\n`;
  xml += `  </url>\n`;

  // Location pages
  for (const place of places) {
    const locUrl = `${baseUrl}/api/share?id=${encodeURIComponent(place.id)}`;
    const imgUrl = place.photoUrl
      ? place.photoUrl
      : `${baseUrl}/api/share?id=${encodeURIComponent(place.id)}&amp;image=true`;

    const name = escapeXml(place.name);
    const coordsStr = (place.lat && place.lng) ? ` (Lat: ${place.lat}, Lng: ${place.lng})` : '';

    xml += `  <url>\n`;
    xml += `    <loc>${locUrl}</loc>\n`;
    xml += `    <lastmod>${today}</lastmod>\n`;
    xml += `    <changefreq>weekly</changefreq>\n`;
    xml += `    <priority>0.7</priority>\n`;
    xml += `    <image:image>\n`;
    xml += `      <image:loc>${imgUrl}</image:loc>\n`;
    xml += `      <image:title>${name} - GECT Compass | GECT Maps &amp; GEC Maps Thrissur</image:title>\n`;
    xml += `      <image:caption>Location and walking route for ${name} on GECT Compass campus map at Government Engineering College Thrissur${coordsStr}.</image:caption>\n`;
    xml += `    </image:image>\n`;
    xml += `  </url>\n`;
  }

  xml += `</urlset>\n`;

  response.setHeader('Content-Type', 'application/xml; charset=utf-8');
  response.setHeader('Cache-Control', 'public, s-maxage=3600, stale-while-revalidate=86400');
  return response.status(200).send(xml);
}
