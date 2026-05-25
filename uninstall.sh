#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_LINE="source \"$SCRIPT_DIR/codexds.sh\""
ZSHRC="$HOME/.zshrc"

echo "=== codexds uninstaller ==="
echo "注意：~/.dscodex/ds.key（DeepSeek Key）将被保留"

# 从 ~/.zshrc 移除 source 行
if grep -qF "$SOURCE_LINE" "$ZSHRC" 2>/dev/null; then
    # 同时移除注释行和 source 行
    grep -v "codexds — DeepSeek" "$ZSHRC" | \
        grep -vF "$SOURCE_LINE" > "$ZSHRC.tmp"
    mv "$ZSHRC.tmp" "$ZSHRC"
    echo "✓ 已从 ~/.zshrc 移除"
else
    echo "✓ ~/.zshrc 中无 codexds 条目（跳过）"
fi

echo ""
echo "卸载完成。DeepSeek Key 保留在 ~/.dscodex/ds.key"
echo "如需彻底清除运行：rm -rf ~/.dscodex"
