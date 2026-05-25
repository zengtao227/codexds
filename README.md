# codexds

**工具与模型解耦。** Codex 是 harness，DeepSeek 是 intelligence——你不应该因为选择了一个工具就被绑定在一个模型上。

codexds 让你用 DeepSeek API 驱动 Codex CLI，无需 OpenAI 账号，不干扰已有的 Codex 登录实例，两者可以同时运行。

---

## 快速开始

**唯一前置条件：** 安装 [Codex Desktop](https://github.com/openai/codex)（或通过 `npm install -g @openai/codex` 安装 CLI）

### macOS / Linux

```bash
git clone https://github.com/zengtao227/codexds
cd codexds
./install.sh
source ~/.zshrc
codexds
```

### Windows

```powershell
git clone https://github.com/zengtao227/codexds
cd codexds
powershell -ExecutionPolicy Bypass -File install.ps1
. $PROFILE
codexds
```

首次运行会提示输入 DeepSeek API Key，输入后自动保存，之后无需再次输入。

> **获取 DeepSeek API Key：** [platform.deepseek.com](https://platform.deepseek.com)

---

## 用法

```bash
codexds              # 在当前目录启动
codexds --key        # 查看 / 更换 DeepSeek Key
```

Codex 内部操作与官方版本完全一致：`/key`、`/exit`、模型切换等均正常使用。

---

## 工作原理

```
Codex CLI → codexds → Moon Bridge（本地代理） → DeepSeek API
```

- **CODEX_HOME 隔离**：codexds 使用独立的 `~/.dscodex`，与 `~/.codex` 完全不冲突，可双开
- **Moon Bridge**：本地运行的协议转换层，将 Codex 的 Responses API 请求转换为 DeepSeek 格式
- **Key 持久化**：Key 存储在 `~/.dscodex/ds.key`，Codex 退出不会删除

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CODEXDS_MOONBRIDGE_BIN` | `~/bin/moonbridge` | Moon Bridge 二进制路径 |
| `CODEXDS_MOONBRIDGE_CONFIG` | `~/moon-bridge/config.yml` | Moon Bridge 配置路径 |
| `CODEXDS_HOME` | `~/.dscodex` | codexds 隔离目录 |
| `CODEXDS_MOONBRIDGE_URL` | `http://127.0.0.1:38440` | Moon Bridge 监听地址 |
| `CODEXDS_CODEX_BIN` | 自动检测 | 手动指定 codex 二进制路径 |
