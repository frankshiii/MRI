#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/mri.koplugin"

required_files=(
    main.lua
    _meta.lua
    api_client.lua
    computer_config.lua
    i18n.lua
    prompts.lua
    providers.lua
    reader_context.lua
    config.example.json
    LICENSE
)

for file in "${required_files[@]}"; do
    if [[ ! -f "$PLUGIN_DIR/$file" ]]; then
        echo "Missing required plugin file: $file" >&2
        exit 1
    fi
done

if ! command -v luaparse >/dev/null 2>&1; then
    echo "luaparse is required. Install it with: npm install --global luaparse@0.3.1" >&2
    exit 1
fi

while IFS= read -r lua_file; do
    luaparse -q -f "$lua_file" </dev/null
done < <(find "$PLUGIN_DIR" -type f -name '*.lua' ! -name '*.bak-*' | sort)

python3 -m json.tool "$PLUGIN_DIR/config.example.json" >/dev/null
bash -n "$ROOT_DIR/scripts/check.sh"
bash -n "$ROOT_DIR/scripts/package.sh"

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && git -C "$ROOT_DIR" ls-files --error-unmatch mri.koplugin/config.json >/dev/null 2>&1; then
    echo "mri.koplugin/config.json contains local credentials and must not be tracked." >&2
    exit 1
fi

if grep -R -nE \
    '(sk-[A-Za-z0-9_-]{16,}|AIza[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._-]{20,})' \
    --include='*.lua' --include='*.json' --include='*.md' \
    --exclude='config.json' --exclude='*.bak-*' \
    "$ROOT_DIR/mri.koplugin" "$ROOT_DIR/docs" "$ROOT_DIR/README.md"; then
    echo "A value resembling an API key was found in publishable files." >&2
    exit 1
fi

echo "MRI checks passed."
