#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-dev}"
ARCHIVE="$ROOT_DIR/dist/MRI-${VERSION}.zip"

mkdir -p "$ROOT_DIR/dist"
rm -f "$ARCHIVE"

cd "$ROOT_DIR"
zip -qr "$ARCHIVE" mri.koplugin \
    -x 'mri.koplugin/config.json' \
       'mri.koplugin/*.bak-*' \
       '*/.DS_Store'

echo "$ARCHIVE"
