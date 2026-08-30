#!/bin/zsh

set -eu

SCRIPT_DIR="${0:A:h}"
SOURCE_DIR="$SCRIPT_DIR/mri.koplugin"

pause_before_exit() {
    local exit_code=$?
    echo
    if [[ $exit_code -eq 0 ]]; then
        echo "同步完成。请在 Kindle 上完整退出并重启 KOReader。"
    else
        echo "同步没有完成，请查看上面的错误信息。"
    fi
    if [[ -t 0 ]]; then
        read -r "REPLY?按回车键关闭窗口…"
    fi
    trap - EXIT
    exit $exit_code
}

trap pause_before_exit EXIT

echo "MRI → Kindle 同步工具"
echo

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "找不到电脑端插件：$SOURCE_DIR"
    exit 1
fi

required_files=(main.lua _meta.lua prompts.lua reader_context.lua providers.lua api_client.lua)
for file in "${required_files[@]}"; do
    if [[ ! -f "$SOURCE_DIR/$file" ]]; then
        echo "电脑端插件不完整，缺少：$file"
        exit 1
    fi
done

plugin_roots=()
for volume in /Volumes/*; do
    if [[ -d "$volume/koreader/plugins" && -w "$volume/koreader/plugins" ]]; then
        plugin_roots+=("$volume/koreader/plugins")
    fi
done

if [[ ${#plugin_roots[@]} -eq 0 ]]; then
    echo "没有找到已挂载的 Kindle。"
    echo "请用 USB 连接 Kindle，确认 Finder 中能看到它，然后重新双击本脚本。"
    exit 1
fi

if [[ ${#plugin_roots[@]} -gt 1 ]]; then
    echo "找到了多个 KOReader 设备，无法自动决定同步目标："
    for root in "${plugin_roots[@]}"; do
        echo "  $root"
    done
    exit 1
fi

PLUGIN_ROOT="$plugin_roots[1]"
TARGET_DIR="$PLUGIN_ROOT/mri.koplugin"
LEGACY_TARGET_DIR="$PLUGIN_ROOT/aireader.koplugin"

if [[ "$TARGET_DIR" != /Volumes/*/koreader/plugins/mri.koplugin ]]; then
    echo "目标路径校验失败：$TARGET_DIR"
    exit 1
fi

if [[ ! -d "$TARGET_DIR" && -d "$LEGACY_TARGET_DIR" ]]; then
    echo "检测到旧版 AIReader，正在迁移为 MRI。"
    /bin/mv "$LEGACY_TARGET_DIR" "$TARGET_DIR"
elif [[ -d "$TARGET_DIR" && -d "$LEGACY_TARGET_DIR" ]]; then
    echo "同时发现 MRI 和旧版 AIReader 插件目录。"
    echo "请先手动备份并移走：$LEGACY_TARGET_DIR"
    exit 1
fi

mkdir -p "$TARGET_DIR"

rsync_options=(
    -a
    --delete
    --itemize-changes
    --exclude=.DS_Store
    --exclude='*.bak-*'
)

if [[ ! -f "$SOURCE_DIR/config.json" && -f "$TARGET_DIR/config.json" ]]; then
    rsync_options+=(--exclude=config.json)
    echo "电脑端没有 config.json，将保留 Kindle 上的现有配置。"
else
    echo "配置将以电脑端 config.json 为准。"
fi

echo "来源：$SOURCE_DIR"
echo "目标：$TARGET_DIR"
echo

/usr/bin/rsync "${rsync_options[@]}" "$SOURCE_DIR/" "$TARGET_DIR/"

for file in "${required_files[@]}"; do
    if ! /usr/bin/cmp -s "$SOURCE_DIR/$file" "$TARGET_DIR/$file"; then
        echo "同步后校验失败：$file"
        exit 1
    fi
done

if [[ -f "$SOURCE_DIR/config.json" ]] && ! /usr/bin/cmp -s "$SOURCE_DIR/config.json" "$TARGET_DIR/config.json"; then
    echo "同步后配置校验失败：config.json"
    exit 1
fi

/bin/sync
