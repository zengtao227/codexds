# codexds Windows Installer
# Run with: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReleaseBase = "https://github.com/zengtao227/codexds/releases/latest/download"
$MbDir       = "$env:USERPROFILE\moon-bridge"
$MbBin       = "$env:USERPROFILE\bin\moonbridge.exe"
$MbConfig    = "$MbDir\config.yml"
$ProfilePath = $PROFILE

function Write-Ok($msg)   { Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "  $msg" }
function Write-Fail($msg) { Write-Host "✗ $msg" -ForegroundColor Red; exit 1 }

# ── Step 1: Codex CLI ─────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== Step 1: Codex CLI ==="

$codexPath = Get-Command codex -ErrorAction SilentlyContinue
if ($codexPath) {
    Write-Ok "Codex CLI 已找到：$($codexPath.Source)"
} else {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        Write-Info "通过 npm 安装 Codex CLI..."
        npm install -g @openai/codex
        Write-Ok "Codex CLI 已安装"
    } else {
        Write-Host ""
        Write-Host "✗ 未找到 Codex CLI，也未找到 npm" -ForegroundColor Red
        Write-Host ""
        Write-Host "  请安装 Node.js：https://nodejs.org"
        Write-Host "  安装后重新运行此脚本"
        exit 1
    }
}

# ── Step 2: Moon Bridge ───────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== Step 2: Moon Bridge ==="

if (Test-Path $MbBin) {
    Write-Ok "Moon Bridge 已找到：$MbBin"
} else {
    $url = "$ReleaseBase/moonbridge-windows-amd64.exe"
    Write-Info "下载 Moon Bridge..."
    $binDir = Split-Path -Parent $MbBin
    if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir | Out-Null }
    Invoke-WebRequest -Uri $url -OutFile $MbBin -UseBasicParsing
    Write-Ok "Moon Bridge 已安装：$MbBin"
}

# ── Step 3: Moon Bridge config ────────────────────────────────────────────────

Write-Host ""
Write-Host "=== Step 3: Moon Bridge 配置 ==="

if (Test-Path $MbConfig) {
    Write-Ok "配置已存在：$MbConfig"
} else {
    Write-Info "生成配置..."
    if (-not (Test-Path $MbDir)) { New-Item -ItemType Directory -Path $MbDir | Out-Null }
    if (-not (Test-Path "$MbDir\data")) { New-Item -ItemType Directory -Path "$MbDir\data" | Out-Null }
    Copy-Item "$ScriptDir\moon-bridge-config.template.yml" $MbConfig
    Write-Ok "配置已生成：$MbConfig"
}

# ── Step 4: codexds PowerShell function ──────────────────────────────────────

Write-Host ""
Write-Host "=== Step 4: Shell 集成 ==="

$sourceSnippet = @"

# codexds — Harness/Intelligence decoupled
. "$ScriptDir\codexds.ps1"
"@

if (-not (Test-Path $ProfilePath)) {
    New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
}

$profileContent = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
if ($profileContent -and $profileContent.Contains("codexds.ps1")) {
    Write-Ok "PowerShell Profile 已包含 codexds（跳过）"
} else {
    Add-Content -Path $ProfilePath -Value $sourceSnippet
    Write-Ok "已添加到 $ProfilePath"
}

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "安装完成！运行以下命令激活："
Write-Host "  . `$PROFILE"
Write-Host ""
Write-Host "然后使用："
Write-Host "  codexds              # 启动（首次运行提示输入 DeepSeek Key）"
Write-Host "  codexds --key        # 查看 / 更换 Key"
