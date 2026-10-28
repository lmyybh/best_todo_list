#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${UPDATE_PUBLIC_KEY:?Set UPDATE_PUBLIC_KEY}"
: "${UPDATE_SIGNING_KEY_PATH:?Set UPDATE_SIGNING_KEY_PATH}"
: "${MACOS_SIGNING_IDENTITY:?Set the Developer ID Application identity}"
: "${MACOS_NOTARY_PROFILE:?Set the notarytool keychain profile}"
version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$/\1/p' pubspec.yaml)"
[[ -n "$version" ]] || exit 1
flutter build macos --release --dart-define="UPDATE_PUBLIC_KEY=$UPDATE_PUBLIC_KEY"
app="build/macos/Build/Products/Release/todo.app"
/usr/bin/lipo -verify_arch x86_64 arm64 "$app/Contents/MacOS/todo"
# Sign Mach-O leaves before their enclosing bundles, and the main app last.
while IFS= read -r -d '' file; do
  if /usr/bin/file -b "$file" | /usr/bin/grep -q 'Mach-O'; then
    /usr/bin/codesign --force --timestamp --options runtime --sign "$MACOS_SIGNING_IDENTITY" "$file"
  fi
done < <(/usr/bin/find "$app/Contents" -type f -print0)
while IFS= read -r -d '' bundle; do
  /usr/bin/codesign --force --timestamp --options runtime --sign "$MACOS_SIGNING_IDENTITY" "$bundle"
done < <(/usr/bin/find "$app/Contents" -depth -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) -print0)
/usr/bin/codesign --force --timestamp --options runtime --entitlements macos/Runner/Release.entitlements --sign "$MACOS_SIGNING_IDENTITY" "$app"
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p build/installer
archive="build/installer/best_todo_list-$version-macos.zip"
/usr/bin/ditto -c -k --keepParent "$app" "$archive"
notary_args=(--keychain-profile "$MACOS_NOTARY_PROFILE")
if [[ -n "${MACOS_NOTARY_KEYCHAIN:-}" ]]; then
  notary_args+=(--keychain "$MACOS_NOTARY_KEYCHAIN")
fi
xcrun notarytool submit "$archive" "${notary_args[@]}" --wait
xcrun stapler staple "$app"
/usr/sbin/spctl --assess --type execute "$app"
# Stapling changes the bundle; create and sign the final archive afterwards.
/usr/bin/ditto -c -k --keepParent "$app" "$archive"
dart run scripts/sign_update.dart --package "$archive" --platform macos --version "$version" \
  --key "$UPDATE_SIGNING_KEY_PATH" --public-key "$UPDATE_PUBLIC_KEY" --output build/installer/update-macos.json
bash scripts/build_macos_dmg.sh --skip-flutter-build
