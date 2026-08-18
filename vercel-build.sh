#!/bin/bash
echo "Downloading Flutter SDK..."
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"

echo "Enabling Web..."
flutter config --enable-web

cd gec_compass_app

echo "Getting dependencies..."
flutter pub get

echo "Building for Web..."
flutter build web --release

cd ..
echo "Generating location sitemap..."
node scripts/generate-sitemap.mjs

echo "Copying APK release asset..."
cp app-release.apk gec_compass_app/build/web/app-release.apk 2>/dev/null || true
cp app-arm64-v8a-release.apk gec_compass_app/build/web/app-arm64-v8a-release.apk 2>/dev/null || true


