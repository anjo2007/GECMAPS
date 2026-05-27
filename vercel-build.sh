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
