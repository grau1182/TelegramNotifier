# ==================================================
# PIPELINE ORQUESTADOR: Test + Análisis
# ==================================================

param(
    [switch]$QuickTest = $false,
    [int]$MaxTorrents = 0
)

$BasePath = "C:\Users\grau_\Downloads\TelegramNotifier"
$TestFolder = Join-Path $BasePath "test"
$WrapperScript = Join-Path $TestFolder "test_v4_wrapper.ps1"
$AnalysisScript = Join-Path $TestFolder "validation\AnalyzeResults.ps1"

Write-Host "`n╔════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PIPELINE v4 - TEST + ANALYSIS   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════╝`n" -ForegroundColor Cyan

# FASE 1: Generar tests y JSON
Write-Host "[FASE 1/2] Ejecutando tests..." -ForegroundColor Yellow
$params = @{}
if ($QuickTest) { $params.QuickTest = $true }
if ($MaxTorrents -gt 0) { $params.MaxTorrents = $MaxTorrents }

& $WrapperScript @params

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ ERROR en fase de tests" -ForegroundColor Red
    exit 1
}

# FASE 2: Análisis
Write-Host "`n[FASE 2/2] Generando análisis..." -ForegroundColor Yellow

& $AnalysisScript

Write-Host "`n╔════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PIPELINE COMPLETADO OK          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════╝`n" -ForegroundColor Cyan
