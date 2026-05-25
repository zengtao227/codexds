# codexds.ps1 — Windows PowerShell equivalent of codexds.sh

$_CODEXDS_MB_BIN    = if ($env:CODEXDS_MOONBRIDGE_BIN)    { $env:CODEXDS_MOONBRIDGE_BIN }    else { "$env:USERPROFILE\bin\moonbridge.exe" }
$_CODEXDS_MB_CONFIG = if ($env:CODEXDS_MOONBRIDGE_CONFIG) { $env:CODEXDS_MOONBRIDGE_CONFIG } else { "$env:USERPROFILE\moon-bridge\config.yml" }
$_CODEXDS_HOME      = if ($env:CODEXDS_HOME)              { $env:CODEXDS_HOME }              else { "$env:APPDATA\dscodex" }
$_CODEXDS_MB_URL    = if ($env:CODEXDS_MOONBRIDGE_URL)    { $env:CODEXDS_MOONBRIDGE_URL }    else { "http://127.0.0.1:38440" }
$_CODEXDS_KEY_FILE  = "$_CODEXDS_HOME\ds.key"

# ── Helpers ───────────────────────────────────────────────────────────────────

function _codexds_mb_running {
    try {
        $r = Invoke-WebRequest -Uri "$_CODEXDS_MB_URL/v1/models" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        return $r.StatusCode -eq 200
    } catch { return $false }
}

function _codexds_ensure_moonbridge {
    if (_codexds_mb_running) { return $true }
    if (-not (Test-Path $_CODEXDS_MB_BIN)) {
        Write-Host "[codexds] ✗ Moon Bridge 未找到：$_CODEXDS_MB_BIN"
        return $false
    }
    Write-Host "[codexds] 启动 Moon Bridge..."
    Start-Process -FilePath $_CODEXDS_MB_BIN -ArgumentList "-config", $_CODEXDS_MB_CONFIG -WindowStyle Hidden
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 300
        if (_codexds_mb_running) { Write-Host "[codexds] ✓ Moon Bridge 已启动"; return $true }
    }
    Write-Host "[codexds] ✗ Moon Bridge 启动超时"
    return $false
}

function _codexds_validate_key($key) {
    try {
        $r = Invoke-WebRequest -Uri "https://api.deepseek.com/v1/models" `
            -Headers @{ Authorization = "Bearer $key" } `
            -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        return $r.StatusCode -eq 200
    } catch { return $false }
}

function _codexds_save_key($key) {
    New-Item -ItemType Directory -Force -Path $_CODEXDS_HOME | Out-Null
    Set-Content -Path $_CODEXDS_KEY_FILE -Value $key -Encoding UTF8
    # Update Moon Bridge config
    if (Test-Path $_CODEXDS_MB_CONFIG) {
        (Get-Content $_CODEXDS_MB_CONFIG -Raw) `
            -replace 'api_key: "sk-[^"]*"', "api_key: `"$key`"" |
            Set-Content $_CODEXDS_MB_CONFIG -Encoding UTF8
    }
}

function _codexds_mask_key($key) {
    if ($key.Length -le 10) { return "******" }
    return "$($key.Substring(0,6))...$($key.Substring($key.Length-4))"
}

function _codexds_restart_moonbridge {
    Get-Process -Name "moonbridge" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    _codexds_ensure_moonbridge | Out-Null
}

function _codexds_prompt_key($promptMsg) {
    Write-Host $promptMsg
    $newKey = Read-Host "DeepSeek Key (sk-xxx)"
    if (-not $newKey) { Write-Host "[codexds] ✗ Key 不能为空"; return $false }
    Write-Host "[codexds] 验证 Key..."
    if (-not (_codexds_validate_key $newKey)) {
        Write-Host "[codexds] ✗ Key 验证失败（可能无效或网络不通）"
        return $false
    }
    _codexds_save_key $newKey
    Write-Host "[codexds] ✓ Key 已保存"
    _codexds_restart_moonbridge
    return $true
}

function _codexds_ensure_key {
    if (-not (Test-Path $_CODEXDS_KEY_FILE)) {
        return (_codexds_prompt_key "[codexds] 首次使用，请输入 DeepSeek API Key：")
    }
    $key = Get-Content $_CODEXDS_KEY_FILE -Raw
    if (_codexds_validate_key $key.Trim()) { return $true }
    return (_codexds_prompt_key "[codexds] ✗ DeepSeek Key 已失效，请输入新 Key：")
}

function _codexds_ensure_config {
    $configFile = "$_CODEXDS_HOME\config.toml"
    New-Item -ItemType Directory -Force -Path $_CODEXDS_HOME | Out-Null
    if (-not (Test-Path $configFile) -or (Get-Item $configFile).Length -eq 0) {
        Write-Host "[codexds] 生成 Codex 配置..."
        $toml = @"
model = "gpt-5.4"
model_reasoning_effort = "high"
model_catalog_json = "$_CODEXDS_HOME\models_catalog.json"

[model_providers.moonbridge]
name = "Moon Bridge"
base_url = "$_CODEXDS_MB_URL/v1"
wire_api = "responses"
"@
        Set-Content -Path $configFile -Value $toml -Encoding UTF8
        Write-Host "[codexds] ✓ 配置已生成"
    }
}

function _codexds_find_codex {
    if ($env:CODEXDS_CODEX_BIN -and (Test-Path $env:CODEXDS_CODEX_BIN)) {
        return $env:CODEXDS_CODEX_BIN
    }
    $c = Get-Command codex -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function _codexds_cmd_key {
    if (Test-Path $_CODEXDS_KEY_FILE) {
        $current = (Get-Content $_CODEXDS_KEY_FILE -Raw).Trim()
        Write-Host "[codexds] 当前 Key：$(_codexds_mask_key $current)"
    } else {
        Write-Host "[codexds] 当前无 Key"
    }
    $newKey = Read-Host "输入新 Key（回车取消）"
    if (-not $newKey) { Write-Host "[codexds] 已取消"; return }
    Write-Host "[codexds] 验证新 Key..."
    if (-not (_codexds_validate_key $newKey)) { Write-Host "[codexds] ✗ 验证失败"; return }
    _codexds_save_key $newKey
    Write-Host "[codexds] ✓ Key 已更新"
    if (_codexds_mb_running) {
        Write-Host "[codexds] 重启 Moon Bridge 使新 Key 生效..."
        _codexds_restart_moonbridge
    }
}

# ── Main entry point ──────────────────────────────────────────────────────────

function codexds {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

    if ($Args -and $Args[0] -eq "--key") {
        _codexds_cmd_key; return
    }

    New-Item -ItemType Directory -Force -Path $_CODEXDS_HOME | Out-Null

    if (-not (_codexds_ensure_key))       { return }
    if (-not (_codexds_ensure_moonbridge)) { return }
    _codexds_ensure_config

    $launchDir = $PWD.Path
    if ($launchDir -eq $env:USERPROFILE) {
        $workspace = "$_CODEXDS_HOME\workspace"
        New-Item -ItemType Directory -Force -Path $workspace | Out-Null
        Write-Host "[codexds] ⚠ 检测到 home 目录冲突，已切换至 $workspace"
        $launchDir = $workspace
    }

    $codexBin = _codexds_find_codex
    if (-not $codexBin) {
        Write-Host "[codexds] ✗ 未找到 codex CLI，请先运行 install.ps1"
        return
    }

    Write-Host "[codexds] 启动 Codex (DeepSeek V4 Pro)..."
    $env:CODEX_HOME = $_CODEXDS_HOME
    & $codexBin --cd $launchDir @Args
}
