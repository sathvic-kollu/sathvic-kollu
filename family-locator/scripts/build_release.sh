#!/usr/bin/env bash
# Builds store-ready binaries. Needs config/release.json (copy the example),
# lib/firebase_options.dart from `flutterfire configure`, and for Android
# android/key.properties. See STORE_SUBMISSION.md.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f config/release.json ]] || { echo "Missing config/release.json (copy config/release.example.json)"; exit 1; }
grep -q "YOUR" config/release.json && { echo "config/release.json still has YOUR_* placeholders"; exit 1; }
grep -q "Firebase is not configured" lib/firebase_options.dart && { echo "Run 'flutterfire configure' first"; exit 1; }

flutter pub get
flutter analyze
flutter test

case "${1:-all}" in
  android|all)
    [[ -f android/key.properties ]] || { echo "Missing android/key.properties (see key.properties.example)"; exit 1; }
    flutter build appbundle --release --dart-define-from-file=config/release.json
    python3 scripts/check_manifest.py
    echo "Upload: build/app/outputs/bundle/release/app-release.aab"
    ;;&
  ios|all)
    if [[ "$(uname)" == "Darwin" ]]; then
      flutter build ipa --release --dart-define-from-file=config/release.json
      echo "Upload build/ios/ipa/*.ipa with Transporter, or open build/ios/archive/Runner.xcarchive in Xcode"
    elif [[ "${1:-all}" == "ios" ]]; then
      echo "iOS builds need a Mac with Xcode"; exit 1
    fi
    ;;
esac
