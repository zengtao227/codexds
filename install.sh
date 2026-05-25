#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEXDS_RELEASE="https://github.com/zengtao227/codexds/releases/latest/download"
MB_CONFIG_DIR="$HOME/moon-bridge"
MB_BIN_DIR="$HOME/bin"
MB_BIN="$MB_BIN_DIR/moonbridge"
ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"

# ── helpers ───────────────────────────────────────────────────────────────────

info()  { echo "  $1"; }
ok()    { echo "✓ $1"; }
fail()  { echo "✗ $1"; exit 1; }

detect_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) fail "不支持的架构：$arch" ;;
    esac
    case "$os" in
        darwin|linux) ;;
        *) fail "此脚本仅支持 macOS / Linux，Windows 请使用 install.ps1" ;;
    esac
    echo "${os}-${arch}"
}

# ── Step 1: Codex CLI ─────────────────────────────────────────────────────────

install_codex_cli() {
    # Check app bundle (macOS)
    if [[ -x "/Applications/Codex.app/Contents/Resources/codex" ]]; then
        ok "Codex CLI 已找到（App bundle）"
        return 0
    fi
    # Check PATH
    if command -v codex &>/dev/null; then
        ok "Codex CLI 已找到（PATH）"
        return 0
    fi
    # Auto-install via npm
    if command -v npm &>/dev/null; then
        info "通过 npm 安装 Codex CLI..."
        npm install -g @openai/codex
        ok "Codex CLI 已安装"
        return 0
    fi
    # No npm — try Node.js install suggestion
    echo ""
    echo "✗ 未找到 Codex CLI，也未找到 npm"
    echo ""
    echo "  请选择安装方式："
    echo "  a) 安装 Node.js（推荐）：https://nodejs.org  → 然后重新运行此脚本"
    echo "  b) macOS 用户：下载 Codex.app：https://github.com/openai/codex"
    echo ""
    exit 1
}

# ── Step 2: Moon Bridge ───────────────────────────────────────────────────────

install_moonbridge() {
    if [[ -x "$MB_BIN" ]]; then
        ok "Moon Bridge 已找到：$MB_BIN"
        return 0
    fi

    local platform
    platform="$(detect_platform)"
    local url="$CODEXDS_RELEASE/moonbridge-${platform}"

    info "下载 Moon Bridge（$platform）..."
    mkdir -p "$MB_BIN_DIR"
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$MB_BIN"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$MB_BIN"
    else
        fail "需要 curl 或 wget 来下载 Moon Bridge"
    fi
    chmod +x "$MB_BIN"
    ok "Moon Bridge 已安装：$MB_BIN"
}

# ── Step 3: Moon Bridge config ────────────────────────────────────────────────

setup_moonbridge_config() {
    local config_file="$MB_CONFIG_DIR/config.yml"
    if [[ -f "$config_file" ]]; then
        ok "Moon Bridge 配置已存在：$config_file"
        return 0
    fi

    info "生成 Moon Bridge 配置..."
    mkdir -p "$MB_CONFIG_DIR/data"
    cp "$SCRIPT_DIR/moon-bridge-config.template.yml" "$config_file"
    ok "Moon Bridge 配置已生成：$config_file"
}

# ── Step 4: Shell integration ─────────────────────────────────────────────────

install_shell_integration() {
    local source_line="source \"$SCRIPT_DIR/codexds.sh\""

    # zsh
    if [[ -f "$ZSHRC" ]] || [[ "${SHELL:-}" == */zsh ]]; then
        if grep -qF "$source_line" "$ZSHRC" 2>/dev/null; then
            ok "~/.zshrc 已包含 codexds（跳过）"
        else
            { echo ""; echo "# codexds — Harness/Intelligence decoupled"; echo "$source_line"; } >> "$ZSHRC"
            ok "已添加到 ~/.zshrc"
        fi
    fi

    # bash
    if [[ -f "$BASHRC" ]] && [[ "${SHELL:-}" == */bash ]]; then
        if grep -qF "$source_line" "$BASHRC" 2>/dev/null; then
            ok "~/.bashrc 已包含 codexds（跳过）"
        else
            { echo ""; echo "# codexds — Harness/Intelligence decoupled"; echo "$source_line"; } >> "$BASHRC"
            ok "已添加到 ~/.bashrc"
        fi
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

echo "=== codexds 安装程序 ==="
echo ""

install_codex_cli
install_moonbridge
setup_moonbridge_config
install_shell_integration

echo ""
echo "安装完成！运行以下命令激活："
echo "  source ~/.zshrc"
echo ""
echo "然后使用："
echo "  codexds              # 启动（首次运行提示输入 DeepSeek Key）"
echo "  codexds --key        # 查看 / 更换 Key"
