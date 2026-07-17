# ==================================================
# Helpers: estimación y registro de duración del pipeline
# ==================================================

function Get-PipelineRunMode {
    param(
        [switch]$QuickTest,
        [int]$MaxTorrents = 0,
        [switch]$ReplayCacheOnly
    )

    if ($ReplayCacheOnly) { return "REPLAY_CACHE" }
    if ($QuickTest) { return "QUICK_TEST" }
    if ($MaxTorrents -gt 0) { return "PARTIAL_TEST" }
    return "FULL_TEST"
}

function Get-PipelineTorrentCount {
    param(
        [string]$ProjectRoot,
        [switch]$QuickTest,
        [int]$MaxTorrents = 0,
        [switch]$ReplayCacheOnly
    )

    if ($ReplayCacheOnly) {
        $jsonFolder = Join-Path $ProjectRoot "test\results\json"
        if (-not (Test-Path $jsonFolder)) { return 0 }
        $latest = Get-ChildItem -Path $jsonFolder -Filter "TelegramNotifier_Test_*.json" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if (-not $latest) { return 0 }
        try {
            $raw = Get-Content $latest.FullName -Raw -Encoding UTF8
            if ($raw.Length -ge 3 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
            $data = $raw | ConvertFrom-Json
            return [int]$data.resumen.total_torrents
        }
        catch { return 0 }
    }

    $csvPath = Join-Path $ProjectRoot "recursos\torrents.csv"
    if (-not (Test-Path $csvPath)) {
        return 0
    }

    $count = @((Import-Csv -Path $csvPath -Encoding UTF8)).Count
    if ($QuickTest) {
        return [Math]::Min(10, $count)
    }
    if ($MaxTorrents -gt 0) {
        return [Math]::Min($MaxTorrents, $count)
    }
    return $count
}

function Format-DurationHuman {
    param([double]$Seconds)

    if ($Seconds -lt 0) { $Seconds = 0 }

    if ($Seconds -lt 60) {
        return "$([math]::Round($Seconds)) s"
    }

    if ($Seconds -lt 3600) {
        $minutes = [math]::Floor($Seconds / 60)
        $secs = [math]::Round($Seconds % 60)
        return "$minutes min $secs s"
    }

    $hours = [math]::Floor($Seconds / 3600)
    $minutes = [math]::Floor(($Seconds % 3600) / 60)
    return "$hours h $minutes min"
}

function Get-PipelineDurationEstimate {
    param(
        [string]$Mode,
        [int]$TorrentCount,
        [string]$ResultsPath,
        [string]$TimingFilePath,
        [switch]$KeepTestCache,
        [switch]$SkipPass2,
        [switch]$ReplayCacheOnly
    )

    if ($ReplayCacheOnly) {
        $pass2Sec = [math]::Max(30, [math]::Round($TorrentCount * 0.4))
        $analysisOverheadSec = 20
        return @{
            Mode                   = "REPLAY_CACHE"
            TorrentCount           = $TorrentCount
            WrapperEstimateSec     = $pass2Sec
            TotalLowSec            = $pass2Sec + $analysisOverheadSec
            TotalHighSec           = [math]::Round($pass2Sec * 1.5) + $analysisOverheadSec
            Source                 = "replay pasada 2 (~0.4 s/torrent)"
            AnalysisOverheadSec    = $analysisOverheadSec
            Pass2ExtraSec          = 0
        }
    }

    $analysisOverheadSec = 20
    $wrapperEstimateSec = $null
    $source = "valores por defecto"
    $includesPass2InWrapper = $false
    $needsTestCacheFactor = ($Mode -eq "FULL_TEST") -and (-not $KeepTestCache)

    if (Test-Path $TimingFilePath) {
        try {
            $last = Get-Content $TimingFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($last.modo -eq $Mode -and [int]$last.total_torrents -gt 0 -and $last.wrapper_segundos) {
                $wrapperEstimateSec = ([double]$last.wrapper_segundos / [int]$last.total_torrents) * $TorrentCount
                $source = "ultima ejecucion pipeline ($($last.timestamp))"
                $includesPass2InWrapper = [bool]$last.test_cache_mode -and ($Mode -eq "FULL_TEST")
                if ($needsTestCacheFactor -and -not [bool]$last.test_cache_mode) {
                    $wrapperEstimateSec *= 1.25
                    $source += ", factor caché test vacía x1.25"
                }
            }
        }
        catch {
        }
    }

    if (-not $wrapperEstimateSec) {
        $jsonFolder = Join-Path $ResultsPath "json"
        if (Test-Path $jsonFolder) {
            $jsonFiles = @(Get-ChildItem -Path $jsonFolder -Filter "TelegramNotifier_Test_*.json" -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 30)

            foreach ($jsonFile in $jsonFiles) {
                try {
                    $raw = Get-Content $jsonFile.FullName -Raw -Encoding UTF8
                    if ($raw.Length -ge 3 -and [int][char]$raw[0] -eq 0xFEFF) {
                        $raw = $raw.Substring(1)
                    }
                    $data = $raw | ConvertFrom-Json
                    if (-not $data.resumen) { continue }
                    if ([string]$data.resumen.modo -ne $Mode) { continue }
                    if ([int]$data.resumen.total_torrents -le 0) { continue }
                    if (-not $data.resumen.duracion_segundos) { continue }

                    $wrapperEstimateSec = ([double]$data.resumen.duracion_segundos / [int]$data.resumen.total_torrents) * $TorrentCount
                    $source = "JSON $($jsonFile.Name)"

                    $hasPass2 = $null -ne $data.resumen.pasada2_json
                    $includesPass2InWrapper = $hasPass2
                    if ($needsTestCacheFactor -and -not [bool]$data.resumen.test_cache_mode) {
                        $wrapperEstimateSec *= 1.25
                        $source += ", factor caché test vacía x1.25"
                    }
                    break
                }
                catch {
                }
            }
        }
    }

    if (-not $wrapperEstimateSec) {
        $secPerTorrent = switch ($Mode) {
            "FULL_TEST" { 3.5 }
            "QUICK_TEST" { 11.0 }
            default { 8.0 }
        }
        $wrapperEstimateSec = $secPerTorrent * $TorrentCount
        if ($Mode -eq "FULL_TEST") {
            if ($needsTestCacheFactor) {
                $wrapperEstimateSec *= 1.25
                $source = "por defecto FULL (~3.5 s/torrent, caché fría x1.25)"
            }
            elseif ($KeepTestCache) {
                $source = "por defecto FULL (~3.5 s/torrent, caché caliente)"
            }
            else {
                $source = "por defecto FULL (~3.5 s/torrent)"
            }
        }
    }

    $pass2ExtraSec = 0
    if ($Mode -eq "FULL_TEST" -and -not $includesPass2InWrapper -and -not $SkipPass2) {
        $pass2ExtraSec = [math]::Max(60, [math]::Round($TorrentCount * 0.3))
    }

    $wrapperLow = $wrapperEstimateSec * 0.85
    $wrapperHigh = $wrapperEstimateSec * 1.35
    $totalLow = $wrapperLow + $pass2ExtraSec + $analysisOverheadSec
    $totalHigh = $wrapperHigh + $pass2ExtraSec + $analysisOverheadSec

    return @{
        Mode                   = $Mode
        TorrentCount           = $TorrentCount
        WrapperEstimateSec     = [math]::Round($wrapperEstimateSec)
        TotalLowSec            = [math]::Round($totalLow)
        TotalHighSec           = [math]::Round($totalHigh)
        Source                 = $source
        AnalysisOverheadSec    = $analysisOverheadSec
        Pass2ExtraSec          = $pass2ExtraSec
    }
}

function Write-PipelineDurationEstimate {
    param($Estimate)

    $modeLabel = switch ($Estimate.Mode) {
        "FULL_TEST" { "FULL (caché test + pasada 2)" }
        "REPLAY_CACHE" { "Replay (solo pasada 2)" }
        "QUICK_TEST" { "QuickTest (10 torrents)" }
        "PARTIAL_TEST" { "Parcial" }
        default { $Estimate.Mode }
    }

    Write-Host "Modo: $modeLabel | Torrents: $($Estimate.TorrentCount)" -ForegroundColor DarkGray
    Write-Host "Duracion estimada total: $(Format-DurationHuman $Estimate.TotalLowSec) - $(Format-DurationHuman $Estimate.TotalHighSec)" -ForegroundColor Yellow
    Write-Host "  (wrapper ~$(Format-DurationHuman $Estimate.WrapperEstimateSec)"
    if ($Estimate.Pass2ExtraSec -gt 0) {
        Write-Host "   + pasada 2 ~$(Format-DurationHuman $Estimate.Pass2ExtraSec)"
    }
    Write-Host "   + analisis HTML ~$(Format-DurationHuman $Estimate.AnalysisOverheadSec))" -ForegroundColor DarkGray
    Write-Host "  Fuente: $($Estimate.Source)" -ForegroundColor DarkGray
    Write-Host ""
}

function Save-PipelineTimingRecord {
    param(
        [string]$TimingFilePath,
        [string]$Mode,
        [int]$TorrentCount,
        [double]$WrapperSeconds,
        [double]$AnalysisSeconds,
        [double]$TotalSeconds,
        [bool]$TestCacheMode
    )

    $timingDir = Split-Path $TimingFilePath -Parent
    if (-not (Test-Path $timingDir)) {
        New-Item -ItemType Directory -Path $timingDir -Force | Out-Null
    }

    $record = @{
        modo              = $Mode
        total_torrents    = $TorrentCount
        wrapper_segundos  = [math]::Round($WrapperSeconds, 2)
        analisis_segundos = [math]::Round($AnalysisSeconds, 2)
        total_segundos    = [math]::Round($TotalSeconds, 2)
        test_cache_mode   = $TestCacheMode
        timestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    $record | ConvertTo-Json -Depth 3 | Set-Content -Path $TimingFilePath -Encoding UTF8 -Force
}
