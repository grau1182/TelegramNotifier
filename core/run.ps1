# ==================================================
# RUN.PS1 - Ejecutable de Producción
# ==================================================
# Wrapper simple para ejecutar TelegramNotifier.ps1

param (
    [string]$TorrentName,
    [string]$ContentPath = "",
    [switch]$SendTelegram = $false
)

$BasePath = Split-Path -Parent $PSScriptRoot
$ScriptPath = Join-Path $PSScriptRoot "TelegramNotifier.ps1"

if (-not (Test-Path $ScriptPath)) {
    Write-Host "❌ Error: TelegramNotifier.ps1 no encontrado en $ScriptPath" -ForegroundColor Red
    exit 1
}

$params = @{
    TorrentName = $TorrentName
    ContentPath = $ContentPath
    ConfigPath = $PSScriptRoot
}

if ($SendTelegram) {
    $params.SendTelegram = $true
}

& $ScriptPath @params
