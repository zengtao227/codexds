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
