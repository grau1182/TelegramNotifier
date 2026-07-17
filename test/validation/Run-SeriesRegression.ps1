# ==================================================
# Run-SeriesRegression.ps1
# Pruebas de integración contra Plex real (Windows)
# Genera logs en test/logs/TelegramNotifier_Test.log
# ==================================================

param(
    [switch]$SkipPlexScan = $false
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$TestScript = Join-Path $ProjectRoot "test\TelegramTorrent_Test.ps1"
$TempResults = Join-Path $env:TEMP "TelegramNotifier_series_regression.json"

$cases = @(
    @{
        Name = "Percy Jackson S02 PACK"
        TorrentName = "Percy Jackson y los dioses del Olimpo (2023) S02 [PACK][DSNP WEB-DL 2160p HEVC DV-HDR10+ ES DD+ 5.1][HDO]"
        ContentPath = "G:\SERIES\PERCY_JACKSON_Y_LOS_DIOSES_DEL_OLIMPO"
        ExpectRatingKey = "8201"
        ExpectPosterPattern = "/8202/"
        ExpectTitleContains = "Percy Jackson"
        ExpectTitleNotContains = "Palomas"
    },
    @{
        Name = "The Boys S05E01"
        TorrentName = "The Boys S05E01 [AMZN WEB-DL 2160p HEVC DV-HDR10+ ES DD+ 5.1][HDO].mkv"
        ContentPath = "G:\SERIES\THE_BOYS\The Boys S05E01 [AMZN WEB-DL 2160p HEVC DV-HDR10+ ES DD+ 5.1][HDO].mkv"
        ExpectRatingKey = "7223"
        ExpectPosterPattern = "/7224/"
        ExpectTitleContains = "The Boys"
        ExpectTitleNotContains = "Cuarenta"
    },
    @{
        Name = "Blade Runner 2049 (regresion)"
        TorrentName = "Blade Runner 2049 (2017) [Remastered 4K][Remastered 2160p HEVC SDR-RAW ES DTS-HD 7.1 EN TrueHD 7.1.4 Atmos Subs]HDO.mkv"
        ContentPath = "G:\PELIS\Blade Runner 2049 (2017) [Remastered 4K][Remastered 2160p HEVC SDR-RAW ES DTS-HD 7.1 EN TrueHD 7.1.4 Atmos Subs]HDO.mkv"
        ExpectRatingKey = "8190"
        ExpectPosterPattern = "/8190/"
        ExpectTitleContains = "Blade Runner"
        ExpectTitleNotContains = ""
    }
)

Write-Host "Regresion series + pelicula (integracion Plex)" -ForegroundColor Cyan
Write-Host "Logs: test\logs\TelegramNotifier_Test.log" -ForegroundColor DarkGray
Write-Host ""

$passed = 0
$failed = 0

foreach ($case in $cases) {
    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "Caso: $($case.Name)" -ForegroundColor Yellow

    if (Test-Path $TempResults) {
        Remove-Item $TempResults -Force -ErrorAction SilentlyContinue
    }

    & $TestScript `
        -TorrentName $case.TorrentName `
        -ContentPath $case.ContentPath `
        -TestMode `
        -SkipPlexScan:$SkipPlexScan `
        -ExportResultPath $TempResults

    if (-not (Test-Path $TempResults)) {
        Write-Host "  FAIL: no se genero resultado JSON" -ForegroundColor Red
        $failed++
        Write-Host ""
        continue
    }

    $record = Get-Content $TempResults -Raw | ConvertFrom-Json
    $ok = $true
    $reasons = @()

    if (-not $record.poster_found) {
        $ok = $false
        $reasons += "poster no encontrado"
    }
    elseif ($record.poster_url -notmatch $case.ExpectPosterPattern) {
        $ok = $false
        $reasons += "poster no coincide con '$($case.ExpectPosterPattern)' -> $($record.poster_url)"
    }

    if ($case.ExpectRatingKey -and [string]$record.rating_key -ne $case.ExpectRatingKey) {
        $ok = $false
        $reasons += "ratingKey esperado $($case.ExpectRatingKey), obtuvo '$($record.rating_key)'"
    }

    if ($case.ExpectTitleContains -and [string]$record.detected_title -notmatch [regex]::Escape($case.ExpectTitleContains)) {
        $ok = $false
        $reasons += "titulo no contiene '$($case.ExpectTitleContains)' -> '$($record.detected_title)'"
    }

    if ($case.ExpectTitleNotContains -and [string]$record.detected_title -match [regex]::Escape($case.ExpectTitleNotContains)) {
        $ok = $false
        $reasons += "titulo no debe contener '$($case.ExpectTitleNotContains)'"
    }

    if ($ok) {
        Write-Host "  PASS" -ForegroundColor Green
        Write-Host "  Poster: $($record.poster_url)" -ForegroundColor DarkGray
        Write-Host "  Titulo: $($record.detected_title)" -ForegroundColor DarkGray
        Write-Host "  RatingKey: $($record.rating_key)" -ForegroundColor DarkGray
        $passed++
    }
    else {
        Write-Host "  FAIL: $($reasons -join '; ')" -ForegroundColor Red
        $failed++
    }

    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Regresion: $passed OK, $failed FAIL" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "Revisa el log completo en: test\logs\TelegramNotifier_Test.log" -ForegroundColor DarkGray

if ($failed -gt 0) {
    exit 1
}

exit 0
