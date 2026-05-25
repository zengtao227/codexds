#!/usr/bin/env bash
# codexds — 无需 OpenAI 账号的 Codex CLI 封装，调用 DeepSeek 通过 Moon Bridge
# 架构：Codex → 工具拦截层(:8383) → Moon Bridge(:38440) → DeepSeek

# ── 配置（可通过环境变量覆盖）────────────────────────────────────
_CODEXDS_BIN="${CODEXDS_MOONBRIDGE_BIN:-$HOME/bin/moonbridge}"
_CODEXDS_MB_CONFIG="${CODEXDS_MOONBRIDGE_CONFIG:-$HOME/moon-bridge/config.yml}"
_CODEXDS_HOME="${CODEXDS_HOME:-$HOME/.dscodex}"
_CODEXDS_MB_URL="${CODEXDS_MOONBRIDGE_URL:-http://127.0.0.1:38440}"
_CODEXDS_INTERCEPTOR_PORT="${CODEXDS_INTERCEPTOR_PORT:-8383}"
_CODEXDS_INTERCEPTOR_URL="http://127.0.0.1:${_CODEXDS_INTERCEPTOR_PORT}"
_CODEXDS_KEY_FILE="$_CODEXDS_HOME/ds.key"
_CODEXDS_CODEX_APP_BIN="/Applications/Codex.app/Contents/Resources/codex"
# 脚本自身所在目录（source 时解析）
_CODEXDS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ── Codex CLI 查找 ────────────────────────────────────────────────

_codexds_find_codex() {
    if [[ -n "${CODEXDS_CODEX_BIN:-}" && -x "$CODEXDS_CODEX_BIN" ]]; then
        echo "$CODEXDS_CODEX_BIN"; return 0
    fi
    if command -v codex &>/dev/null; then
        command -v codex; return 0
    fi
    if [[ -x "$_CODEXDS_CODEX_APP_BIN" ]]; then
        echo "$_CODEXDS_CODEX_APP_BIN"; return 0
    fi
    return 1
}

# ── Moon Bridge 管理 ──────────────────────────────────────────────

_codexds_mb_running() {
    curl -sf --max-time 3 "$_CODEXDS_MB_URL/v1/models" > /dev/null 2>&1
}

_codexds_ensure_moonbridge() {
    if _codexds_mb_running; then return 0; fi

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
        if _codexds_mb_running; then echo "[codexds] ✓ Moon Bridge 已启动"; return 0; fi
        (( i++ ))
    done

    echo "[codexds] ✗ Moon Bridge 启动超时，请手动检查"
    return 1
}

# ── 工具拦截层管理 ────────────────────────────────────────────────

_codexds_interceptor_running() {
    curl -sf --max-time 2 "$_CODEXDS_INTERCEPTOR_URL/v1/models" > /dev/null 2>&1
}

_codexds_ensure_interceptor() {
    local interceptor_script="$_CODEXDS_SCRIPT_DIR/interceptor/server.mjs"

    if ! command -v node &>/dev/null; then
        echo "[codexds] ⚠ Node.js 未找到，web_search 功能不可用（Codex 直连 Moon Bridge）"
        return 0
    fi

    if [[ ! -f "$interceptor_script" ]]; then
        echo "[codexds] ⚠ 拦截层脚本未找到：$interceptor_script"
        return 0
    fi

    if _codexds_interceptor_running; then return 0; fi

    echo "[codexds] 启动工具拦截层..."
    MB_URL="$_CODEXDS_MB_URL" INTERCEPTOR_PORT="$_CODEXDS_INTERCEPTOR_PORT" \
        node "$interceptor_script" > /dev/null 2>&1 &

    local i=0
    while (( i < 20 )); do
        sleep 0.3
        if _codexds_interceptor_running; then
            echo "[codexds] ✓ 工具拦截层已启动（web_search / web_fetch 本地执行）"
            return 0
        fi
        (( i++ ))
    done

    echo "[codexds] ⚠ 工具拦截层启动超时，降级为直连 Moon Bridge"
    return 0  # 非致命错误
}

# ── DeepSeek Key 管理 ─────────────────────────────────────────────

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

    if [[ -f "$_CODEXDS_MB_CONFIG" ]]; then
        sed -i.bak -E "s/api_key: \"sk-[^\"]*\"/api_key: \"$key\"/" \
            "$_CODEXDS_MB_CONFIG" && rm -f "${_CODEXDS_MB_CONFIG}.bak"
    fi
}

_codexds_restart_moonbridge() {
    pkill -f "moonbridge.*config" > /dev/null 2>&1
    pkill -f "interceptor/server.mjs" > /dev/null 2>&1
    sleep 0.5
    _codexds_ensure_moonbridge
    _codexds_ensure_interceptor
}

_codexds_prompt_key() {
    local prompt_msg="$1"
    echo "$prompt_msg"
    printf "DeepSeek Key (sk-xxx): "
    local new_key
    read -r new_key

    if [[ -z "$new_key" ]]; then echo "[codexds] ✗ Key 不能为空"; return 1; fi

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
    if [[ ! -f "$_CODEXDS_KEY_FILE" ]]; then
        _codexds_prompt_key "[codexds] 首次使用，请输入 DeepSeek API Key：" || return 1
        return 0
    fi

    local key
    key=$(<"$_CODEXDS_KEY_FILE")
    if _codexds_validate_key "$key"; then return 0; fi

    _codexds_prompt_key "[codexds] ✗ DeepSeek Key 已失效，请输入新 Key：" || return 1
}

_codexds_mask_key() {
    local key="$1"
    local length=${#key}
    if (( length <= 10 )); then printf "%s\n" "******"; return 0; fi
    local prefix suffix
    prefix=$(printf "%s" "$key" | cut -c1-6)
    suffix=$(printf "%s" "$key" | rev | cut -c1-4 | rev)
    printf "%s...%s\n" "$prefix" "$suffix"
}

_codexds_cmd_key() {
    if [[ -f "$_CODEXDS_KEY_FILE" ]]; then
        local current masked
        current=$(<"$_CODEXDS_KEY_FILE")
        masked=$(_codexds_mask_key "$current")
        echo "[codexds] 当前 Key：$masked"
    else
        echo "[codexds] 当前无 Key"
    fi

    printf "输入新 Key（回车取消）: "
    local new_key
    read -r new_key

    if [[ -z "$new_key" ]]; then echo "[codexds] 已取消"; return 0; fi

    echo "[codexds] 验证新 Key..."
    if ! _codexds_validate_key "$new_key"; then echo "[codexds] ✗ 验证失败"; return 1; fi

    _codexds_save_key "$new_key"
    echo "[codexds] ✓ Key 已更新"

    if _codexds_mb_running; then
        echo "[codexds] 重启服务使新 Key 生效..."
        _codexds_restart_moonbridge
    fi
}

# ── Codex 配置生成 ────────────────────────────────────────────────

_codexds_endpoint_url() {
    # 拦截层在线 → 用拦截层；否则直连 Moon Bridge
    if _codexds_interceptor_running; then
        echo "$_CODEXDS_INTERCEPTOR_URL"
    else
        echo "$_CODEXDS_MB_URL"
    fi
}

_codexds_ensure_config() {
    local config_file="$_CODEXDS_HOME/config.toml"
    mkdir -p "$_CODEXDS_HOME"

    local need_config=false
    [[ ! -s "$config_file" ]] && need_config=true

    if $need_config; then
        echo "[codexds] 生成 Codex 配置..."
        "$_CODEXDS_BIN" \
            -config "$_CODEXDS_MB_CONFIG" \
            -print-codex-config "gpt-5.4" \
            -codex-base-url "$_CODEXDS_MB_URL/v1" \
            -codex-home "$_CODEXDS_HOME" \
            > "$config_file" 2>/dev/null

        if [[ ! -s "$config_file" ]]; then
            cat > "$config_file" << TOML
model = "gpt-5.4"
model_reasoning_effort = "high"
model_catalog_json = "$_CODEXDS_HOME/models_catalog.json"

[model_providers.moonbridge]
name = "Moon Bridge"
base_url = "$_CODEXDS_MB_URL/v1"
wire_api = "responses"

[features]
multi_agent = true
TOML
        fi
        echo "[codexds] ✓ 配置已生成"
    else
        # 每次刷新 catalog（静默）
        "$_CODEXDS_BIN" \
            -config "$_CODEXDS_MB_CONFIG" \
            -print-codex-config "gpt-5.4" \
            -codex-base-url "$_CODEXDS_MB_URL/v1" \
            -codex-home "$_CODEXDS_HOME" \
            > /dev/null 2>&1 || true
    fi

    # 将 base_url 更新为实际端点（拦截层或 Moon Bridge）
    local endpoint
    endpoint=$(_codexds_endpoint_url)
    sed -i.bak "s|base_url = \"http://127.0.0.1:[0-9]*/v1\"|base_url = \"${endpoint}/v1\"|g" \
        "$config_file" && rm -f "${config_file}.bak"
}

# ── 主函数 ────────────────────────────────────────────────────────

codexds() {
    if [[ "${1:-}" == "--key" ]]; then
        _codexds_cmd_key; return $?
    fi

    mkdir -p "$_CODEXDS_HOME"

    # 1. 确保 Key 有效
    _codexds_ensure_key || return 1

    # 2. 确保 Moon Bridge 运行
    _codexds_ensure_moonbridge || return 1

    # 3. 启动工具拦截层（有 Node.js 时）
    _codexds_ensure_interceptor

    # 4. 确保 Codex 配置存在并指向正确端点
    _codexds_ensure_config

    # 5. 检测 home 目录冲突
    local _launch_dir="$PWD"
    if [[ "$_launch_dir" == "$HOME" ]]; then
        local _workspace="$_CODEXDS_HOME/workspace"
        mkdir -p "$_workspace"
        echo "[codexds] ⚠ 检测到 home 目录冲突，已切换至安全工作区 $_workspace"
        echo "         提示：在项目目录下运行 codexds 可直接使用当前目录"
        _launch_dir="$_workspace"
    fi

    # 6. 启动 Codex
    local _codex_bin
    _codex_bin=$(_codexds_find_codex) || {
        echo "[codexds] ✗ 未找到 codex CLI"
        echo "         请安装 Codex.app 或设置 CODEXDS_CODEX_BIN 指向二进制路径"
        return 1
    }
    echo "[codexds] 启动 Codex (DeepSeek)..."
    CODEX_HOME="$_CODEXDS_HOME" "$_codex_bin" --cd "$_launch_dir" "$@"
}
