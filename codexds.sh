#!/usr/bin/env bash
# codexds — 无需 OpenAI 账号的 Codex CLI 封装，调用 DeepSeek 通过 Moon Bridge

# ── 配置（可通过环境变量覆盖）────────────────────────────────
_CODEXDS_BIN="${CODEXDS_MOONBRIDGE_BIN:-$HOME/bin/moonbridge}"
_CODEXDS_MB_CONFIG="${CODEXDS_MOONBRIDGE_CONFIG:-$HOME/moon-bridge/config.yml}"
_CODEXDS_HOME="${CODEXDS_HOME:-$HOME/.dscodex}"
_CODEXDS_MB_URL="${CODEXDS_MOONBRIDGE_URL:-http://127.0.0.1:38440}"
_CODEXDS_KEY_FILE="$_CODEXDS_HOME/ds.key"
# Codex CLI 的已知默认路径（不依赖 PATH）
_CODEXDS_CODEX_APP_BIN="/Applications/Codex.app/Contents/Resources/codex"

# ── Codex CLI 查找 ────────────────────────────────────────────

_codexds_find_codex() {
    # 1. 环境变量覆盖
    if [[ -n "${CODEXDS_CODEX_BIN:-}" && -x "$CODEXDS_CODEX_BIN" ]]; then
        echo "$CODEXDS_CODEX_BIN"; return 0
    fi
    # 2. PATH 中查找
    if command -v codex &>/dev/null; then
        command -v codex; return 0
    fi
    # 3. Codex.app bundle 默认位置（macOS 标准安装）
    if [[ -x "$_CODEXDS_CODEX_APP_BIN" ]]; then
        echo "$_CODEXDS_CODEX_APP_BIN"; return 0
    fi
    return 1
}

# ── Moon Bridge 管理 ───────────────────────────────────────────

_codexds_mb_running() {
    curl -sf "$_CODEXDS_MB_URL/v1/models" > /dev/null 2>&1
}

_codexds_ensure_moonbridge() {
    if _codexds_mb_running; then
        return 0
    fi

    if [[ ! -x "$_CODEXDS_BIN" ]]; then
        echo "[codexds] ✗ Moon Bridge 未找到：$_CODEXDS_BIN"
        echo "         请确认 Moon Bridge 已安装，或设置 CODEXDS_MOONBRIDGE_BIN"
        return 1
    fi

    echo "[codexds] 启动 Moon Bridge..."
    "$_CODEXDS_BIN" -config "$_CODEXDS_MB_CONFIG" > /dev/null 2>&1 &

    local i=0
    while (( i < 20 )); do
        sleep 0.3
        if _codexds_mb_running; then
            echo "[codexds] ✓ Moon Bridge 已启动"
            return 0
        fi
        (( i++ ))
    done

    echo "[codexds] ✗ Moon Bridge 启动超时，请手动检查"
    return 1
}

# ── DeepSeek Key 管理 ─────────────────────────────────────────

_codexds_validate_key() {
    local key="$1"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "https://api.deepseek.com/v1/models" \
        -H "Authorization: Bearer $key" \
        --max-time 8 2>/dev/null)
    [[ "$http_code" == "200" ]]
}

_codexds_save_key() {
    local key="$1"
    mkdir -p "$_CODEXDS_HOME"
    echo "$key" > "$_CODEXDS_KEY_FILE"
    chmod 600 "$_CODEXDS_KEY_FILE"

    # Keep Moon Bridge in sync without touching the isolated Codex key file.
    if [[ -f "$_CODEXDS_MB_CONFIG" ]]; then
        sed -i '' -E "s/api_key: \"sk-[^\"]*\"/api_key: \"$key\"/" \
            "$_CODEXDS_MB_CONFIG"
    fi
}

_codexds_restart_moonbridge() {
    pkill -f "moonbridge.*config" > /dev/null 2>&1
    sleep 0.5
    _codexds_ensure_moonbridge
}

_codexds_prompt_key() {
    local prompt_msg="$1"
    echo "$prompt_msg"
    printf "DeepSeek Key (sk-xxx): "
    local new_key
    read -r new_key

    if [[ -z "$new_key" ]]; then
        echo "[codexds] ✗ Key 不能为空"
        return 1
    fi

    echo "[codexds] 验证 Key..."
    if ! _codexds_validate_key "$new_key"; then
        echo "[codexds] ✗ Key 验证失败（可能无效或网络不通）"
        return 1
    fi

    _codexds_save_key "$new_key"
    echo "[codexds] ✓ Key 已保存"
    _codexds_restart_moonbridge
    return 0
}

_codexds_ensure_key() {
    # 无 Key 文件 → 首次运行
    if [[ ! -f "$_CODEXDS_KEY_FILE" ]]; then
        _codexds_prompt_key "[codexds] 首次使用，请输入 DeepSeek API Key：" || return 1
        return 0
    fi

    local key
    key=$(<"$_CODEXDS_KEY_FILE")

    # 有 Key，验证是否有效
    if _codexds_validate_key "$key"; then
        return 0
    fi

    # Key 失效 → 提示更新
    _codexds_prompt_key "[codexds] ✗ DeepSeek Key 已失效，请输入新 Key：" || return 1
}

_codexds_mask_key() {
    local key="$1"
    local length=${#key}
    if (( length <= 10 )); then
        printf "%s\n" "******"
        return 0
    fi

    local prefix
    local suffix
    prefix=$(printf "%s" "$key" | cut -c1-6)
    suffix=$(printf "%s" "$key" | rev | cut -c1-4 | rev)
    printf "%s...%s\n" "$prefix" "$suffix"
}

# --key 入口：主动更换 Key
_codexds_cmd_key() {
    if [[ -f "$_CODEXDS_KEY_FILE" ]]; then
        local current
        current=$(<"$_CODEXDS_KEY_FILE")
        local masked
        masked=$(_codexds_mask_key "$current")
        echo "[codexds] 当前 Key：$masked"
    else
        echo "[codexds] 当前无 Key"
    fi

    printf "输入新 Key（回车取消）: "
    local new_key
    read -r new_key

    if [[ -z "$new_key" ]]; then
        echo "[codexds] 已取消"
        return 0
    fi

    echo "[codexds] 验证新 Key..."
    if ! _codexds_validate_key "$new_key"; then
        echo "[codexds] ✗ 验证失败"
        return 1
    fi

    _codexds_save_key "$new_key"
    echo "[codexds] ✓ Key 已更新"

    if _codexds_mb_running; then
        echo "[codexds] 重启 Moon Bridge 使新 Key 生效..."
        _codexds_restart_moonbridge
    fi
}

# ── Codex 配置生成 ────────────────────────────────────────────

_codexds_ensure_config() {
    local config_file="$_CODEXDS_HOME/config.toml"

    # 已有配置则跳过
    [[ -f "$config_file" ]] && return 0

    echo "[codexds] 生成 Codex 配置..."
    mkdir -p "$_CODEXDS_HOME"

    # 用 Moon Bridge 内置生成器（同时生成 models_catalog.json）
    "$_CODEXDS_BIN" \
        -config "$_CODEXDS_MB_CONFIG" \
        -print-codex-config "gpt-5.4" \
        -codex-base-url "$_CODEXDS_MB_URL/v1" \
        -codex-home "$_CODEXDS_HOME" \
        > "$config_file" 2>/dev/null

    # 如果生成失败则写入兜底配置
    if [[ ! -s "$config_file" ]]; then
        cat > "$config_file" << TOML
model = "gpt-5.4"
model_reasoning_effort = "high"
model_catalog_json = "$_CODEXDS_HOME/models_catalog.json"

[openai]
base_url = "$_CODEXDS_MB_URL/v1"
api_key = "codexds-local"

[features]
multi_agent = true
TOML
    fi

    echo "[codexds] ✓ 配置已生成"
}

# ── 主函数 ────────────────────────────────────────────────────

codexds() {
    # 处理 --key 标志
    if [[ "${1:-}" == "--key" ]]; then
        _codexds_cmd_key
        return $?
    fi

    # 创建隔离目录
    mkdir -p "$_CODEXDS_HOME"

    # 1. 确保 Key 有效（首次提示 / 失效重提示）
    _codexds_ensure_key || return 1

    # 2. 确保 Moon Bridge 运行
    _codexds_ensure_moonbridge || return 1

    # 3. 确保 Codex 配置存在
    _codexds_ensure_config || return 1

    # 4. 启动 Codex（独立 CODEX_HOME，不干扰 ~/.codex）
    local _codex_bin
    _codex_bin=$(_codexds_find_codex) || {
        echo "[codexds] ✗ 未找到 codex CLI"
        echo "         请安装 Codex.app 或设置 CODEXDS_CODEX_BIN 指向二进制路径"
        return 1
    }
    echo "[codexds] 启动 Codex (DeepSeek V4 Pro)..."
    CODEX_HOME="$_CODEXDS_HOME" "$_codex_bin" "$@"
}
