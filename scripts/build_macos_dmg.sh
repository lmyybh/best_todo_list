#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pubspec_path="$project_root/pubspec.yaml"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS." >&2
  exit 1
fi

version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$/\1/p' "$pubspec_path" | head -n 1)"
if [[ -z "$version" ]]; then
  echo "pubspec.yaml version must use the X.Y.Z format." >&2
  exit 1
fi

flutter_path="${FLUTTER_PATH:-}"
if [[ -z "$flutter_path" ]]; then
  flutter_path="$(command -v flutter || true)"
fi
if [[ -z "$flutter_path" || ! -x "$flutter_path" ]]; then
  echo "Flutter was not found. Set FLUTTER_PATH or add flutter to PATH." >&2
  exit 1
fi

skip_flutter_build=0
if [[ "${1:-}" == "--skip-flutter-build" ]]; then
  skip_flutter_build=1
  shift
fi
if [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--skip-flutter-build]" >&2
  exit 1
fi

if [[ "$skip_flutter_build" -eq 0 ]]; then
  "$flutter_path" build macos --release
fi

release_dir="$project_root/build/macos/Build/Products/Release"
app_path="$release_dir/todo.app"
if [[ ! -d "$app_path" ]]; then
  echo "The macOS release app was not found at $app_path" >&2
  exit 1
fi
info_plist="$app_path/Contents/Info.plist"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)"
if [[ "$app_version" != "$version" ]]; then
  echo "The app version ($app_version) does not match pubspec.yaml ($version)." >&2
  echo "Rebuild the macOS release app before creating the DMG." >&2
  exit 1
fi
app_name="$(basename "$app_path")"

output_dir="$project_root/build/installer"
mkdir -p "$output_dir"
output_path="$output_dir/best_todo_list-$version-macos.dmg"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/best_todo_list-dmg.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

mkdir -p "$staging_dir/BestTodoList"
ditto "$app_path" "$staging_dir/BestTodoList/$app_name"
ln -s /Applications "$staging_dir/BestTodoList/Applications"

hdiutil create \
  -volname "BestTodoList" \
  -srcfolder "$staging_dir/BestTodoList" \
  -ov \
  -format UDZO \
  "$output_path"

if [[ ! -f "$output_path" ]]; then
  echo "DMG was not created at $output_path" >&2
  exit 1
fi

ls -lh "$output_path"
