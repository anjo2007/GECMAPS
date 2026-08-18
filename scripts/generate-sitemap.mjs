import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const rootDir = path.resolve(__dirname, '..');
const buildingsJsonPath = path.join(rootDir, 'gec_compass_app', 'assets', 'campus_buildings.json');
const webSitemapPath = path.join(rootDir, 'gec_compass_app', 'web', 'sitemap.xml');
const buildWebSitemapPath = path.join(rootDir, 'gec_compass_app', 'build', 'web', 'sitemap.xml');

const baseUrl = 'https://gecmaps.vercel.app';
const today = new Date().toISOString().split('T')[0];

function escapeXml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

try {
  console.log('Generating static sitemap.xml for campus locations...');
  let places = [];
  if (fs.existsSync(buildingsJsonPath)) {
    const raw = fs.readFileSync(buildingsJsonPath, 'utf-8');
    places = JSON.parse(raw);
  } else {
    console.warn('campus_buildings.json not found, using default routes only.');
  }

  // Deduplicate and filter out unnamed
  const placeMap = new Map();
  for (const place of places) {
    if (place && place.id && place.name && place.name !== 'Unnamed Location') {
      placeMap.set(place.id, place);
    }
  }

  const validPlaces = Array.from(placeMap.values());

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
  xml += `      <image:title>GEC Maps | GECT Compass - GEC Thrissur Campus Map</image:title>\n`;
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
  for (const place of validPlaces) {
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
    xml += `    <priority>0.8</priority>\n`;
    xml += `    <image:image>\n`;
    xml += `      <image:loc>${imgUrl}</image:loc>\n`;
    xml += `      <image:title>${name} - GEC Maps | GECT Compass | GECT Maps &amp; GEC Compass Thrissur</image:title>\n`;
    xml += `      <image:caption>Location and walking route for ${name} on GECT Compass campus map at Government Engineering College Thrissur${coordsStr}.</image:caption>\n`;
    xml += `    </image:image>\n`;
    xml += `  </url>\n`;
  }

  xml += `</urlset>\n`;

  // Write to web/sitemap.xml
  fs.writeFileSync(webSitemapPath, xml, 'utf-8');
  console.log(`Successfully updated ${webSitemapPath} with ${validPlaces.length} location URLs.`);

  // Write to build/web/sitemap.xml if build directory exists
  const buildDir = path.dirname(buildWebSitemapPath);
  if (fs.existsSync(buildDir)) {
    fs.writeFileSync(buildWebSitemapPath, xml, 'utf-8');
    console.log(`Successfully updated ${buildWebSitemapPath}.`);
  }
} catch (err) {
  console.error('Error generating static sitemap:', err);
  process.exit(1);
}
