export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  return res.status(200).json({
    version: "1.2.0",
    buildNumber: 12,
    releaseNotes: "• Dynamic GEC campus area theme projection\n• Enhanced offline road graph navigation\n• Building text labels on zoom & navigation\n• Location range alerts & recentering",
    downloadUrl: "https://gecmaps.vercel.app/app-release.apk",
    minRequiredBuildNumber: 1,
    forceUpdate: false
  });
}
