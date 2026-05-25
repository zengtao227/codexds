# codexds 设计文档

**日期**：2026-05-25  
**状态**：已确认，待实现

---

## 目标

构建 `codexds`——一个 shell 命令，让用户无需 OpenAI 账号即可使用 Codex CLI，底层调用 DeepSeek API，通过 Moon Bridge 做协议翻译。与现有 `claudeds` 命令对齐，可双开并行。

---

## 架构

```
codexds (shell function in ~/.zshrc)
    ↓ CODEX_HOME=~/.dscodex
Codex CLI（系统已安装，自动随 Codex 升级）
    ↓ http://127.0.0.1:38440/v1  (Responses API)
Moon Bridge（常驻后台，12MB RAM，0% CPU）
    ↓ Anthropic protocol
DeepSeek V4 Pro / Flash API
```

## 关键设计决策

### 1. 实现形式：shell function（同 claudeds）
- 不 fork codex-cli 源码，直接调用系统 `codex` 二进制
- Codex 升级自动受益，无需维护版本
- 与 claudeds 形式完全对齐

### 2. Key 管理：~/.dscodex/ds.key（独立文件）
- 首次运行：提示输入，验证，保存
- Key 失效（401/402）：自动检测，重新提示
- 主动换 Key：`codexds --key`
- Codex 内部 `exit` / logout **不会删除** ds.key（两个文件分离）

### 3. 隔离方式：CODEX_HOME=~/.dscodex
- 完全独立于 `~/.codex`（主账号）
- 两个实例可同时运行，互不干扰
- `~/.dscodex/config.toml` 指向 Moon Bridge

### 4. Moon Bridge：常驻服务，不随 codexds 启停
- 已作为二进制常驻：`/Users/zengtao/bin/moonbridge`
- codexds 启动时检查是否在运行，不在则启动
- 不提供停止功能（Moon Bridge 为共享基础设施）

---

## 文件结构

```
/Users/zengtao/Doc/My code/codexds/
├── codexds.sh                  ← 主脚本（source 进 ~/.zshrc）
├── install.sh                  ← 一键安装
├── uninstall.sh                ← 卸载（保留 ds.key）
├── templates/
│   ├── config.toml.tpl         ← ~/.dscodex/config.toml 模板
│   └── moonbridge.yml.tpl      ← Moon Bridge config 片段（路由）
└── docs/plans/
    └── 2026-05-25-codexds-design.md

运行时文件（不进 git）：
~/.dscodex/
├── ds.key                      ← DeepSeek API Key（永不删除）
├── config.toml                 ← Codex 配置，指向 Moon Bridge
└── models_catalog.json         ← DeepSeek 模型能力（Moon Bridge 生成）
```

---

## UX 流程

### 首次运行
```
$ codexds
[codexds] 首次使用，请输入 DeepSeek API Key（sk-xxx）：
> sk-xxxxxx
[codexds] 验证 Key...
[codexds] ✓ Key 有效，已保存到 ~/.dscodex/ds.key
[codexds] ✓ Moon Bridge 运行中
[codexds] 启动 Codex (DeepSeek V4 Pro)...
[Codex TUI 正常启动]
```

### 正常运行
```
$ codexds
[codexds] ✓ Moon Bridge 运行中
[Codex TUI 直接启动，无提示]
```

### Key 失效
```
$ codexds
[codexds] ✗ DeepSeek Key 已失效（401），请输入新 Key：
> sk-newkey
[codexds] ✓ 验证通过，已更新
[Codex TUI 启动]
```

### 主动换 Key
```
$ codexds --key
当前 Key：sk-d6a...（后4位：0228）
输入新 Key（回车跳过）：
> sk-newkey
[codexds] ✓ 已更新并重启 Moon Bridge
```

---

## Moon Bridge 路由配置

在现有 `/Users/zengtao/moon-bridge/config.yml` 中，codexds 使用已有路由：
- `gpt-5.4` → deepseek-v4-pro（主模型）
- `gpt-5.4-mini` → deepseek-v4-flash（轻量模型）

`~/.dscodex/config.toml` 使用 `gpt-5.4` 作为默认模型名。

---

## 升级兼容性

| 场景 | 影响 | 应对 |
|------|------|------|
| Codex 正常升级 | 无（自动用新二进制） | 无需操作 |
| Codex 改 config.toml 格式 | 低风险（[openai] section 稳定） | 重新生成 config.toml |
| Codex 强制要求 OpenAI auth | 需对策 | 记录已知可用版本号 |
| Moon Bridge 升级 | 无（独立服务） | 无需操作 |
| DeepSeek API 变更 | 在 Moon Bridge 层处理 | 更新 Moon Bridge config |

---

## 验收标准

1. `codexds` 首次运行提示 Key 输入，保存后不再提示
2. `codexds` 与 `codex`（主账号）可同时运行，互不干扰
3. Codex 内 `exit` 后，`~/.dscodex/ds.key` 仍存在
4. `codexds --key` 可更换 Key
5. Key 失效时自动检测并提示
6. Moon Bridge 不在运行时，codexds 自动启动它
