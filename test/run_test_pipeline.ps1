# ==================================================
# PIPELINE ORQUESTADOR: Test + Análisis
# ==================================================

param(
    [switch]$QuickTest = $false,
    [int]$MaxTorrents = 0,
    [switch]$KeepTestCache = $false,
    [switch]$SkipPass2 = $false,
    [switch]$ReplayCacheOnly = $false,
    [string]$ReplayJsonPath = ""
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$TestFolder = $PSScriptRoot
$WrapperScript = Join-Path $TestFolder "test_v4_wrapper.ps1"
$AnalysisScript = Join-Path $TestFolder "validation\AnalyzeResults.ps1"
$ResultsPath = Join-Path $TestFolder "results"
$TimingFilePath = Join-Path $ResultsPath "last_pipeline_timing.json"

. (Join-Path $TestFolder "lib\pipeline-timing.ps1")

$pipelineMode = Get-PipelineRunMode -QuickTest:$QuickTest -MaxTorrents $MaxTorrents -ReplayCacheOnly:$ReplayCacheOnly
$torrentCount = Get-PipelineTorrentCount -ProjectRoot $ProjectRoot -QuickTest:$QuickTest -MaxTorrents $MaxTorrents -ReplayCacheOnly:$ReplayCacheOnly
$estimate = Get-PipelineDurationEstimate `
    -Mode $pipelineMode `
    -TorrentCount $torrentCount `
    -ResultsPath $ResultsPath `
    -TimingFilePath $TimingFilePath `
    -KeepTestCache:$KeepTestCache `
    -SkipPass2:$SkipPass2 `
    -ReplayCacheOnly:$ReplayCacheOnly

$pipelineStart = Get-Date

Write-Host "`n╔════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PIPELINE v4 - TEST + ANALYSIS   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-PipelineDurationEstimate -Estimate $estimate

# FASE 1: Generar tests y JSON
Write-Host "[FASE 1/2] Ejecutando tests..." -ForegroundColor Yellow
$wrapperStart = Get-Date

$params = @{}
if ($QuickTest) { $params.QuickTest = $true }
if ($MaxTorrents -gt 0) { $params.MaxTorrents = $MaxTorrents }
if ($KeepTestCache) { $params.KeepTestCache = $true }
if ($SkipPass2) { $params.SkipPass2 = $true }
if ($ReplayCacheOnly) { $params.ReplayCacheOnly = $true }
if ($ReplayJsonPath) { $params.ReplayJsonPath = $ReplayJsonPath }

& $WrapperScript @params

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ ERROR en fase de tests" -ForegroundColor Red
    exit 1
}

$wrapperSeconds = ((Get-Date) - $wrapperStart).TotalSeconds

# FASE 2: Análisis
Write-Host "`n[FASE 2/2] Generando análisis..." -ForegroundColor Yellow
$analysisStart = Get-Date

& $AnalysisScript

$analysisSeconds = ((Get-Date) - $analysisStart).TotalSeconds
$totalSeconds = ((Get-Date) - $pipelineStart).TotalSeconds

Save-PipelineTimingRecord `
    -TimingFilePath $TimingFilePath `
    -Mode $pipelineMode `
    -TorrentCount $torrentCount `
    -WrapperSeconds $wrapperSeconds `
    -AnalysisSeconds $analysisSeconds `
    -TotalSeconds $totalSeconds `
    -TestCacheMode (($pipelineMode -eq "FULL_TEST") -or ($pipelineMode -eq "REPLAY_CACHE"))

Write-Host "`n╔════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PIPELINE COMPLETADO OK          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Wrapper:  $(Format-DurationHuman $wrapperSeconds)" -ForegroundColor Green
Write-Host "  Analisis: $(Format-DurationHuman $analysisSeconds)" -ForegroundColor Green
Write-Host "  Total:    $(Format-DurationHuman $totalSeconds)" -ForegroundColor Green
Write-Host "  Registro: $TimingFilePath`n" -ForegroundColor DarkGray
