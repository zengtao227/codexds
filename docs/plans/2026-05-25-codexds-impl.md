# codexds Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 构建 `codexds` shell 命令——无需 OpenAI 账号，通过 Moon Bridge 调用 DeepSeek API 运行 Codex CLI，与 `claudeds` 体验对齐。

**Architecture:** shell function 写入 `~/.zshrc`，设置 `CODEX_HOME=~/.dscodex` 后调用系统 `codex` 二进制。DeepSeek Key 存于 `~/.dscodex/ds.key`（与 Codex 会话隔离，永不删除）。Moon Bridge 作为常驻翻译层，codexds 启动时检查，不在则自动启动。

**Tech Stack:** Bash（无外部依赖），依赖已安装的 `codex` CLI 和 `/Users/zengtao/bin/moonbridge`。

---

## 环境前提（实现前确认）

| 项目 | 路径 | 验证命令 |
|------|------|----------|
| Moon Bridge 二进制 | `/Users/zengtao/bin/moonbridge` | `ls /Users/zengtao/bin/moonbridge` |
| Moon Bridge 配置 | `/Users/zengtao/moon-bridge/config.yml` | `curl -s http://127.0.0.1:38440/v1/models \| head -1` |
| Codex CLI | 系统 PATH | `which codex` |
| 项目目录 | `/Users/zengtao/Doc/My code/codexds/` | 已存在 |

---

## Task 1: 项目 scaffold

**Files:**
- Create: `codexds.sh`
- Create: `.gitignore`
- Create: `README.md`

**Step 1: 创建 .gitignore**

```bash
cat > "/Users/zengtao/Doc/My code/codexds/.gitignore" << 'EOF'
# 运行时文件（不进 git）
*.log
.DS_Store
EOF
```

**Step 2: 创建 README.md**

```bash
cat > "/Users/zengtao/Doc/My code/codexds/README.md" << 'EOF'
# codexds

无需 OpenAI 账号的 Codex CLI 封装，底层调用 DeepSeek API。

## 安装

```bash
./install.sh
```

## 用法

```bash
codexds                  # 在当前目录启动（首次运行自动提示输入 DeepSeek Key）
codexds /path/to/proj    # 指定项目目录
codexds --key            # 查看 / 更换 DeepSeek Key
```

## 依赖

- Codex CLI（系统已安装）
- Moon Bridge（`~/bin/moonbridge`）
- DeepSeek API Key（`platform.deepseek.com` 注册获取）

## 配置

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `CODEXDS_MOONBRIDGE_BIN` | `~/bin/moonbridge` | Moon Bridge 二进制路径 |
| `CODEXDS_MOONBRIDGE_CONFIG` | `~/moon-bridge/config.yml` | Moon Bridge 配置路径 |
| `CODEXDS_HOME` | `~/.dscodex` | codexds 隔离目录 |
| `CODEXDS_MOONBRIDGE_URL` | `http://127.0.0.1:38440` | Moon Bridge 地址 |
EOF
```

**Step 3: 创建空 codexds.sh 占位**

```bash
touch "/Users/zengtao/Doc/My code/codexds/codexds.sh"
chmod +x "/Users/zengtao/Doc/My code/codexds/codexds.sh"
```

**Step 4: Commit**

```bash
cd "/Users/zengtao/Doc/My code/codexds"
git add .gitignore README.md codexds.sh
git commit -m "feat: scaffold codexds project"
```

---

## Task 2: codexds.sh — 配置变量与 Moon Bridge 管理函数

**Files:**
- Modify: `codexds.sh`

**Step 1: 写入配置变量和 Moon Bridge 函数**

写入以下内容到 `codexds.sh`（完整替换文件）：

```bash
#!/usr/bin/env bash
# codexds — 无需 OpenAI 账号的 Codex CLI 封装，调用 DeepSeek 通过 Moon Bridge

# ── 配置（可通过环境变量覆盖）────────────────────────────────
_CODEXDS_BIN="${CODEXDS_MOONBRIDGE_BIN:-$HOME/bin/moonbridge}"
_CODEXDS_MB_CONFIG="${CODEXDS_MOONBRIDGE_CONFIG:-$HOME/moon-bridge/config.yml}"
_CODEXDS_HOME="${CODEXDS_HOME:-$HOME/.dscodex}"
_CODEXDS_MB_URL="${CODEXDS_MOONBRIDGE_URL:-http://127.0.0.1:38440}"
_CODEXDS_KEY_FILE="$_CODEXDS_HOME/ds.key"

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
```

**Step 2: 验证语法**

```bash
bash -n "/Users/zengtao/Doc/My code/codexds/codexds.sh"
```

期望输出：无（无语法错误）。

**Step 3: Commit**

```bash
cd "/Users/zengtao/Doc/My code/codexds"
git add codexds.sh
git commit -m "feat: add Moon Bridge management functions"
```

---

## Task 3: codexds.sh — Key 管理函数

**Files:**
- Modify: `codexds.sh`（追加）

**Step 1: 追加 Key 验证函数**

在 `codexds.sh` 末尾追加：

```bash

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

    # 同步更新 Moon Bridge config.yml 中 deepseek provider 的 api_key
    if [[ -f "$_CODEXDS_MB_CONFIG" ]]; then
        sed -i '' "s/api_key: \"sk-[a-zA-Z0-9]*\"/api_key: \"$key\"/" \
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

# --key 入口：主动更换 Key
_codexds_cmd_key() {
    if [[ -f "$_CODEXDS_KEY_FILE" ]]; then
        local current
        current=$(<"$_CODEXDS_KEY_FILE")
        local masked="${current:0:6}...${current: -4}"
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
```

**Step 2: 验证语法**

```bash
bash -n "/Users/zengtao/Doc/My code/codexds/codexds.sh"
```

期望输出：无错误。

**Step 3: Commit**

```bash
cd "/Users/zengtao/Doc/My code/codexds"
git add codexds.sh
git commit -m "feat: add DeepSeek key management functions"
```

---

## Task 4: codexds.sh — Codex 配置生成与主函数

**Files:**
- Modify: `codexds.sh`（追加）

**Step 1: 追加配置生成函数和主函数**

在 `codexds.sh` 末尾追加：

```bash

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
    echo "[codexds] 启动 Codex (DeepSeek V4 Pro)..."
    CODEX_HOME="$_CODEXDS_HOME" command codex "$@"
}
```

**Step 2: 验证完整脚本语法**

```bash
bash -n "/Users/zengtao/Doc/My code/codexds/codexds.sh"
```

期望：无错误。

**Step 3: Smoke test（不启动 Codex，只测 source 不报错）**

```bash
# 在新 shell 中 source 并确认函数可见
bash -c "source '/Users/zengtao/Doc/My code/codexds/codexds.sh' && type codexds && echo 'OK'"
```

期望输出：
```
codexds is a function
...
OK
```

**Step 4: Commit**

```bash
cd "/Users/zengtao/Doc/My code/codexds"
git add codexds.sh
git commit -m "feat: add config generation and main codexds function"
```

---

## Task 5: install.sh

**Files:**
- Create: `install.sh`

**Step 1: 写 install.sh**

```bash
cat > "/Users/zengtao/Doc/My code/codexds/install.sh" << 'INSTALL'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_LINE="source \"$SCRIPT_DIR/codexds.sh\""
ZSHRC="$HOME/.zshrc"

echo "=== codexds installer ==="

# 检查依赖
if ! command -v codex &> /dev/null; then
    echo "✗ 未找到 codex CLI，请先安装 Codex"
    exit 1
fi

MB_BIN="${CODEXDS_MOONBRIDGE_BIN:-$HOME/bin/moonbridge}"
if [[ ! -x "$MB_BIN" ]]; then
    echo "✗ 未找到 Moon Bridge 二进制：$MB_BIN"
    echo "  请设置 CODEXDS_MOONBRIDGE_BIN 指向正确路径"
    exit 1
fi

echo "✓ codex CLI 已找到：$(which codex)"
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
INSTALL
chmod +x "/Users/zengtao/Doc/My code/codexds/install.sh"
```

**Step 2: 验证 install.sh 语法**

```bash
bash -n "/Users/zengtao/Doc/My code/codexds/install.sh"
```

期望：无错误。

**Step 3: Commit**

```bash
cd "/Users/zengtao/Doc/My code/codexds"
git add install.sh
git commit -m "feat: add install.sh"
```

---

## Task 6: uninstall.sh

**Files:**
- Create: `uninstall.sh`

**Step 1: 写 uninstall.sh**

```bash
cat > "/Users/zengtao/Doc/My code/codexds/uninstall.sh" << 'UNINSTALL'
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
UNINSTALL
chmod +x "/Users/zengtao/Doc/My code/codexds/uninstall.sh"
```

**Step 2: Commit**

```bash
cd "/Users/zengtao/Doc/My code/codexds"
git add uninstall.sh
git commit -m "feat: add uninstall.sh (preserves ds.key)"
```

---

## Task 7: 端到端验证

以下验证按顺序执行，每步检查期望输出。

**Step 1: 安装**

```bash
cd "/Users/zengtao/Doc/My code/codexds"
./install.sh
source ~/.zshrc
```

期望：`codexds is a function` 可用，无错误。

**Step 2: 验证函数可见**

```bash
type codexds
```

期望输出：`codexds is a function`

**Step 3: 验证首次运行提示（临时删除 key 测试）**

```bash
# 备份现有 key（如果有）
[[ -f ~/.dscodex/ds.key ]] && cp ~/.dscodex/ds.key ~/.dscodex/ds.key.bak

# 删除 key 触发首次运行提示
rm -f ~/.dscodex/ds.key

# 运行 codexds（不实际启动 Codex，测试提示流程）
# 输入一个已知有效的 DeepSeek Key
codexds --key
```

期望：显示 `当前无 Key`，提示输入，验证后保存。

**Step 4: 验证 Key 持久化**

```bash
cat ~/.dscodex/ds.key
```

期望：显示保存的 Key（非空）。

**Step 5: 验证 CODEX_HOME 隔离（不干扰主账号）**

```bash
# 确认 ~/.dscodex/config.toml 已生成（首次 codexds 启动时会生成）
ls ~/.dscodex/config.toml ~/.dscodex/models_catalog.json
# 确认主账号未被修改
grep "gpt-5.5" ~/.codex/config.toml
```

期望：两个文件独立存在，`~/.codex/config.toml` 仍指向 gpt-5.5。

**Step 6: 验证 --key 更换流程**

```bash
codexds --key
# 显示当前 Key 的 masked 形式，然后取消（直接回车）
```

期望：显示 `sk-d6a...0228`（masked），按回车后显示 `已取消`。

**Step 7: 验证 Moon Bridge 自动启动**

```bash
# 停止 Moon Bridge
pkill -f "moonbridge" 2>/dev/null; sleep 1

# 启动 codexds（不要实际进入 Codex，Ctrl+C 打断）
# Moon Bridge 应自动启动
timeout 5 codexds || true
curl -s http://127.0.0.1:38440/v1/models | head -1
```

期望：Moon Bridge 被 codexds 自动启动，`/v1/models` 返回 JSON。

**Step 8: 最终 commit**

```bash
cd "/Users/zengtao/Doc/My code/codexds"
git add -A
git commit -m "docs: add verification checklist to implementation plan"
```

---

## Task 8: 更新 memory

更新 `/Users/zengtao/.claude/projects/-Users-zengtao/memory/project_codex_dual.md`，将方案 B 状态标记为已实现，并记录关键路径：

```
- codexds 命令：source /Users/zengtao/Doc/My code/codexds/codexds.sh
- DeepSeek Key：~/.dscodex/ds.key
- Codex 隔离 HOME：~/.dscodex/
- Moon Bridge 常驻：/Users/zengtao/bin/moonbridge
```

---

## 验收清单

- [ ] `codexds` 首次运行提示 Key 输入，保存后不再提示
- [ ] `codexds --key` 可查看/更换 Key
- [ ] Key 失效时（401）自动提示重新输入
- [ ] `codexds` 与 `codex`（主账号）可同时运行
- [ ] Codex `exit` 后 `~/.dscodex/ds.key` 仍存在
- [ ] Moon Bridge 不在运行时，codexds 自动启动它
- [ ] `~/.codex/config.toml` 内容未被修改
