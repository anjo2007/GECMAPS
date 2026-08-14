export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  return res.status(200).json({
    version: "1.3.0",
    buildNumber: 13,
    releaseNotes: "• Direct internal campus walkway navigation (no gate detours)\n• Dynamic gate closure schedule & rerouting alerts\n• Enhanced mobile UI sizing and navigation bar\n• Improved real-time GPS & sensor fusion accuracy",
    downloadUrl: "https://gecmaps.vercel.app/app-release.apk",
    minRequiredBuildNumber: 1,
    forceUpdate: false
  });
}
