export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  return res.status(200).json({
    version: "1.3.1",
    buildNumber: 14,
    releaseNotes: "• Real-time cloud sync & instant updates across platforms\n• Auto-upright pin markers and labels during map rotation\n• Dynamic category-based pins & enhanced campus routing\n• Performance optimizations and bug fixes",
    downloadUrl: "https://gecmaps.vercel.app/app-release.apk",
    minRequiredBuildNumber: 1,
    forceUpdate: false
  });
}
