#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_LINE="source \"$SCRIPT_DIR/codexds.sh\""
ZSHRC="$HOME/.zshrc"

echo "=== codexds installer ==="

# 检查依赖：codex CLI（PATH 优先，fallback 到 App bundle）
_CODEX_APP_BIN="/Applications/Codex.app/Contents/Resources/codex"
if command -v codex > /dev/null 2>&1; then
    echo "✓ codex CLI 已找到（PATH）：$(command -v codex)"
elif [[ -x "$_CODEX_APP_BIN" ]]; then
    echo "✓ codex CLI 已找到（App bundle）：$_CODEX_APP_BIN"
else
    echo "✗ 未找到 codex CLI，请先安装 Codex.app 或设置 CODEXDS_CODEX_BIN"
    exit 1
fi

MB_BIN="${CODEXDS_MOONBRIDGE_BIN:-$HOME/bin/moonbridge}"
if [[ ! -x "$MB_BIN" ]]; then
    echo "✗ 未找到 Moon Bridge 二进制：$MB_BIN"
    echo "  请设置 CODEXDS_MOONBRIDGE_BIN 指向正确路径"
    exit 1
fi

echo "✓ Moon Bridge 已找到：$MB_BIN"

# 添加 source 行（去重）
if grep -qF "$SOURCE_LINE" "$ZSHRC" 2>/dev/null; then
    echo "✓ ~/.zshrc 已包含 codexds（跳过）"
else
    echo "" >> "$ZSHRC"
    echo "# codexds — DeepSeek-powered Codex CLI" >> "$ZSHRC"
    echo "$SOURCE_LINE" >> "$ZSHRC"
    echo "✓ 已添加到 ~/.zshrc"
fi

echo ""
echo "安装完成！运行以下命令激活："
echo "  source ~/.zshrc"
echo ""
echo "然后使用："
echo "  codexds              # 启动（首次运行提示输入 DeepSeek Key）"
echo "  codexds --key        # 更换 Key"
