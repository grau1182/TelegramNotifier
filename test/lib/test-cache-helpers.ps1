# ==================================================
# Helpers: caché test + pasada 2 + logs de sesión FULL
# Requiere utilities.ps1, cache-manager.ps1, plex-functions.ps1 cargados antes.
# ==================================================

function Get-PosterRatingKeyFromUrl {
    param([string]$PosterUrl)

    if ([string]::IsNullOrWhiteSpace($PosterUrl)) { return "" }
    if ($PosterUrl -match '/metadata/(\d+)/') { return $Matches[1] }
    return ""
}

function Archive-TestSessionLog {
    param([string]$LogFolder)

    $logFile = Join-Path $LogFolder "TelegramNotifier_Test.log"
    if (-not (Test-Path $logFile)) {
        return
    }

    $archiveName = "TelegramNotifier_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Rename-Item -Path $logFile -NewName $archiveName -Force
}

function Resolve-PosterFromCacheOnly {
    param(
        [string]$SearchTitle,
        [string]$SearchTitleClean,
        [hashtable]$DetectedMetadata,
        [string]$RatingKey = "",
        [switch]$SkipRuntimePosterResolution
    )

    $cacheResult = Get-PosterByCache -Title $SearchTitleClean -RatingKey $RatingKey -DetectedMetadata $DetectedMetadata
    if (-not $cacheResult.found) {
        return @{
            found      = $false
            poster_url = $null
            method     = $cacheResult.method
            rating_key = ""
        }
    }

    $posterUrl = $cacheResult.url

    if (-not $SkipRuntimePosterResolution -and $DetectedMetadata.Type -in @("EPISODIO", "TEMPORADA") -and $cacheResult.ratingKey) {
        $runtimePoster = Resolve-PlexSeriesPoster -ShowRatingKey $cacheResult.ratingKey -DetectedMetadata $DetectedMetadata
        if ($runtimePoster) {
            $posterUrl = $runtimePoster
        }
    }

    return @{
        found      = $true
        poster_url = $posterUrl
        method     = $cacheResult.method
        rating_key = [string]$cacheResult.ratingKey
    }
}

function Get-ReplayTestJson {
    param(
        [string]$ResultsPath,
        [string]$ReplayJsonPath = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($ReplayJsonPath)) {
        if (-not (Test-Path -LiteralPath $ReplayJsonPath)) {
            throw "JSON de replay no encontrado: $ReplayJsonPath"
        }
        $jsonFile = Get-Item -LiteralPath $ReplayJsonPath
    }
    else {
        $jsonFolder = Join-Path $ResultsPath "json"
        if (-not (Test-Path $jsonFolder)) {
            throw "No hay carpeta results/json para replay"
        }

        $jsonFile = Get-ChildItem -Path $jsonFolder -Filter "TelegramNotifier_Test_*.json" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Where-Object {
                try {
                    $raw = Get-Content $_.FullName -Raw -Encoding UTF8
                    if ($raw.Length -ge 3 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
                    $data = $raw | ConvertFrom-Json
                    return ($data.resumen.modo -eq "FULL_TEST" -and $null -ne $data.torrents)
                }
                catch { return $false }
            } |
            Select-Object -First 1

        if (-not $jsonFile) {
            throw "No se encontró ningún TelegramNotifier_Test_*.json FULL previo para replay"
        }
    }

    $raw = Get-Content $jsonFile.FullName -Raw -Encoding UTF8
    if ($raw.Length -ge 3 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    $data = $raw | ConvertFrom-Json

    return @{
        JsonFile = $jsonFile.FullName
        Torrents = @($data.torrents)
        Resumen  = $data.resumen
    }
}

function Invoke-CacheValidationPass {
    param(
        [array]$TorrentResults,
        [string]$ProjectRoot,
        [string]$ResultsPath,
        [switch]$CacheOnlyComparison
    )

    Write-Log "========================================"
    Write-Log "=== PASADA 2: verificacion caché test ==="
    Write-Log "========================================"

    Reset-PlexCache
    Initialize-PlexCache -ForceReload -ProjectRoot $ProjectRoot

    $cacheFilePath = Get-PlexCacheFilePath -ProjectRoot $ProjectRoot
    Write-Log "Caché test recargada desde: $cacheFilePath ($($script:PlexCache.Count) entradas)"

    $expected = @($TorrentResults | Where-Object { $_.poster_encontrado -eq $true })
    $validationRows = @()
    $ok = 0
    $fail = 0

    foreach ($row in $expected) {
        $parsed = Get-TorrentSearchMetadata -TorrentName $row.torrent_name -ContentPath $row.content_path
        $meta = $parsed.DetectedMetadata

        $cacheRead = Resolve-PosterFromCacheOnly `
            -SearchTitle $parsed.SearchTitle `
            -SearchTitleClean $parsed.SearchTitleClean `
            -DetectedMetadata $meta `
            -RatingKey ([string]$row.rating_key) `
            -SkipRuntimePosterResolution:$CacheOnlyComparison.IsPresent

        $pass1PosterRk = Get-PosterRatingKeyFromUrl -PosterUrl ([string]$row.poster_url)
        $pass2PosterRk = Get-PosterRatingKeyFromUrl -PosterUrl ([string]$cacheRead.poster_url)
        $ratingKeyMatch = [string]$cacheRead.rating_key -eq [string]$row.rating_key

        if ($CacheOnlyComparison) {
            $posterMatch = -not [string]::IsNullOrWhiteSpace([string]$cacheRead.poster_url)
        }
        else {
            $posterMatch = (-not [string]::IsNullOrWhiteSpace([string]$cacheRead.poster_url)) -and (
                [string]$cacheRead.poster_url -eq [string]$row.poster_url -or $pass1PosterRk -eq $pass2PosterRk
            )
        }
        $success = $cacheRead.found -and $ratingKeyMatch -and $posterMatch

        if ($success) {
            $ok++
            Write-Log "PASADA 2 OK #$($row.numero): $($row.torrent_name) rk=$($row.rating_key) metodo=$($cacheRead.method)"
        }
        else {
            $fail++
            $reason = if (-not $cacheRead.found) { "cache_miss" }
                      elseif (-not $ratingKeyMatch) { "rating_key_distinto" }
                      else { "poster_distinto" }
            Write-Log "PASADA 2 FAIL #$($row.numero): $($row.torrent_name) razon=$reason p1_rk=$($row.rating_key) p2_rk=$($cacheRead.rating_key)" -Level "WARNING"
        }

        $validationRows += @{
            numero             = $row.numero
            torrent_name       = $row.torrent_name
            pass1_rating_key   = $row.rating_key
            pass2_rating_key   = $cacheRead.rating_key
            pass1_poster_url   = $row.poster_url
            pass2_poster_url   = $cacheRead.poster_url
            pass1_poster_rk    = $pass1PosterRk
            pass2_poster_rk    = $pass2PosterRk
            pass2_cache_method = $cacheRead.method
            ok                 = $success
            fail_reason        = if ($success) { $null } else { $reason }
        }
    }

    $totalExpected = $expected.Count
    $pct = if ($totalExpected -gt 0) { [math]::Round(($ok / $totalExpected) * 100, 2) } else { 0 }

    Write-Log "=== PASADA 2 fin: $ok/$totalExpected lecturas OK ($pct%) ==="

    $jsonFolder = Join-Path $ResultsPath "json"
    if (-not (Test-Path $jsonFolder)) {
        New-Item -ItemType Directory -Path $jsonFolder -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $jsonFile = Join-Path $jsonFolder "CacheValidation_$timestamp.json"

    $output = @{
        resumen = @{
            esperados_con_poster = $totalExpected
            lecturas_ok          = $ok
            lecturas_fail        = $fail
            porcentaje_ok        = $pct
            cache_file           = $cacheFilePath
            cache_entradas       = $script:PlexCache.Count
            cache_only_compare   = $CacheOnlyComparison.IsPresent
            timestamp            = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
        }
        validaciones = $validationRows
    }

    $output | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonFile -Encoding UTF8
    Write-Log "JSON validacion caché: $jsonFile"

    return @{
        Ok       = $ok
        Fail     = $fail
        Total    = $totalExpected
        JsonFile = $jsonFile
    }
}
