#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

flutter build macos --debug -t lib/main.dart

# Keep the running app's native libraries intact during subsequent builds.
preview_dir="$(mktemp -d "${TMPDIR:-/tmp}/best-todo-preview.XXXXXX")"
preview_app="$preview_dir/todo.app"
ditto "$project_root/build/macos/Build/Products/Debug/todo.app" "$preview_app"
open -n "$preview_app"
printf 'Preview app: %s\n' "$preview_app"
