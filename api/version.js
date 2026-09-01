export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=300, stale-while-revalidate=3600');

  return res.status(200).json({
    version: "1.3.4",
    buildNumber: 17,
    releaseNotes: "• High-precision 7-digit GPS & sub-meter Campus Grid (GEC-E074.48-N052.82)\n• Ultra-compressed APK package size & faster launch\n• Zero-bandwidth ETag caching & smart sync\n• Updated CARTO Basemaps & performance optimizations",
    downloadUrl: "https://github.com/anjo2007/GECMAPS/releases/latest/download/app-arm64-v8a-release.apk",
    minRequiredBuildNumber: 1,
    forceUpdate: false
  });
}
