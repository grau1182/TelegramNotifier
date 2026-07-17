# ==================================================
# WRAPPER: Test Data Generator v4 - Con Exportación Completa
# ==================================================

param(
    [int]$MaxTorrents = 0,
    [switch]$QuickTest = $false,
    [switch]$KeepTestCache = $false,
    [switch]$SkipPass2 = $false,
    [switch]$ReplayCacheOnly = $false,
    [string]$ReplayJsonPath = ""
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$TestBasePath = $PSScriptRoot
$ScriptPath = Join-Path $TestBasePath "TelegramTorrent_Test.ps1"
$TorrentListPath = Join-Path $ProjectRoot "recursos\torrents.csv"
$ResultsPath = Join-Path $TestBasePath "results"
$LogFolder = Join-Path $TestBasePath "logs"

if (-not (Test-Path $TorrentListPath)) {
    Write-Host "ERROR: recursos/torrents.csv no encontrado" -ForegroundColor Red
    exit 1
}

$torrents = @(Import-Csv -Path $TorrentListPath -Encoding UTF8)

if ($QuickTest) {
    $torrents = @($torrents | Select-Object -First 10)
    Write-Host "QUICK TEST: Procesando 10 torrents (SkipPlexScan activo)" -ForegroundColor Yellow
}
elseif ($MaxTorrents -gt 0) {
    $torrents = @($torrents | Select-Object -First $MaxTorrents)
}

$isFullTest = (-not $QuickTest) -and ($MaxTorrents -le 0) -and (-not $ReplayCacheOnly)

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "WRAPPER v4 - TEST CON CACHE" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

if ($ReplayCacheOnly) {
    Write-Host "Modo: REPLAY (solo pasada 2)" -ForegroundColor Magenta
}
else {
    Write-Host "Torrents: $($torrents.Count)" -ForegroundColor Green
    if ($isFullTest) {
        $modeLabel = "FULL (caché test"
        if ($KeepTestCache) { $modeLabel += ", caché caliente" }
        if ($SkipPass2) { $modeLabel += ", sin pasada 2" }
        $modeLabel += ")"
        Write-Host "Modo: $modeLabel" -ForegroundColor Green
    }
    else {
        Write-Host "Modo: $(if ($QuickTest) { 'QUICK' } else { 'PARCIAL' }) (caché producción)" -ForegroundColor Yellow
    }
}

$inicio = Get-Date
$found = 0
$notfound = 0
$allTorrentResults = @()
$validation = $null

. $ScriptPath -TestMode $true -TorrentName '' -ContentPath '' -ResultsFolder $ResultsPath -SkipPlexScan:$QuickTest

. (Join-Path $TestBasePath "lib\test-cache-helpers.ps1")

$script:ProjectRoot = $ProjectRoot

if ($ReplayCacheOnly) {
    Archive-TestSessionLog -LogFolder $LogFolder
    Write-Log "========================================"
    Write-Log "=== REPLAY - solo pasada 2 ==="
    Write-Log "========================================"

    $script:UseTestCache = $true
    Reset-PlexCache

    $cacheFilePath = Get-PlexCacheFilePath -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $cacheFilePath)) {
        Write-Host "ERROR: no existe caché test en $cacheFilePath" -ForegroundColor Red
        exit 1
    }

    Initialize-PlexCache -ForceReload -ProjectRoot $ProjectRoot
    Write-Host "Caché test cargada: $cacheFilePath ($($script:PlexCache.Count) entradas)" -ForegroundColor Cyan

    try {
        $replay = Get-ReplayTestJson -ResultsPath $ResultsPath -ReplayJsonPath $ReplayJsonPath
    }
    catch {
        Write-Host "ERROR replay: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    Write-Host "JSON replay: $($replay.JsonFile)" -ForegroundColor Cyan
    Write-Log "JSON replay: $($replay.JsonFile)"

    $allTorrentResults = @($replay.Torrents | ForEach-Object {
        @{
            numero            = $_.numero
            torrent_name      = $_.torrent_name
            content_path      = $_.content_path
            rating_key        = [string]$_.rating_key
            poster_url        = $_.poster_url
            poster_encontrado = [bool]$_.poster_encontrado
        }
    })

    $found = @($allTorrentResults | Where-Object { $_.poster_encontrado }).Count
    $notfound = $allTorrentResults.Count - $found

    $validation = Invoke-CacheValidationPass `
        -TorrentResults $allTorrentResults `
        -ProjectRoot $ProjectRoot `
        -ResultsPath $ResultsPath `
        -CacheOnlyComparison
}
elseif ($isFullTest) {
    Archive-TestSessionLog -LogFolder $LogFolder
    Write-Log "========================================"
    Write-Log "=== TEST FULL - inicio ==="
    Write-Log "========================================"

    $script:UseTestCache = $true
    Reset-PlexCache

    $cacheFilePath = Get-PlexCacheFilePath -ProjectRoot $ProjectRoot
    $reuseCache = $KeepTestCache -and (Test-Path -LiteralPath $cacheFilePath)

    if ($reuseCache) {
        Write-Host "Reutilizando caché test: $cacheFilePath" -ForegroundColor Cyan
        Write-Log "Caché test existente reutilizada (KeepTestCache)"
    }
    else {
        Initialize-EmptyTestCacheFile -ProjectRoot $ProjectRoot
        Write-Host "Caché test vacía: $cacheFilePath" -ForegroundColor Cyan
    }

    Initialize-PlexCache -ForceReload -ProjectRoot $ProjectRoot
    Write-Log "=== PASADA 1: Plex + generación plex_cache_test.json ==="

    foreach ($idx in 0..($torrents.Count - 1)) {
        $torrent = $torrents[$idx]
        $num = $idx + 1

        $name = $torrent.torrent_name.Trim()
        $path = $torrent.content_path.Trim()

        if ([string]::IsNullOrEmpty($name)) {
            Write-Host "[$num/$($torrents.Count)] [SKIP] Nombre vacío" -ForegroundColor Gray
            continue
        }

        Write-Host -NoNewline "[$num/$($torrents.Count)] $name ... "

        $script:PlexSearchLog = @()
        $script:LastPosterDisplayTitle = $null

        $parsed = Get-TorrentSearchMetadata -TorrentName $name -ContentPath $path
        $global:OriginalName = $parsed.OriginalName
        $global:NormalizedName = Normalize-Name $parsed.OriginalName
        $global:CleanName = $parsed.CleanName
        $global:DetectedMetadata = $parsed.DetectedMetadata
        $global:PatternDetected = $parsed.PatternDetected
        $global:Resolution = Get-Resolution $global:NormalizedName
        $global:SizeGB = Get-SizeGB $path
        $global:TechnicalTags = Get-TechnicalTags $global:NormalizedName
        $global:ContentExists = $parsed.ContentExists

        $searchTitle = $parsed.SearchTitle
        $searchTitleClean = $parsed.SearchTitleClean

        $poster = Get-PlexPoster -Title $searchTitle -ContentPath $path `
                                 -DetectedMetadata $global:DetectedMetadata `
                                 -BasePath $TestBasePath `
                                 -PlexScanPollSeconds $script:PlexScanPollSeconds `
                                 -PlexScanPollMaxAttempts $script:PlexScanPollMaxAttempts `
                                 -SkipPlexScan:$script:SkipPlexScan

        if ($script:LastPosterDisplayTitle -and $global:DetectedMetadata.Type -eq "PELICULA" -and (Test-PosterTitleRefinement -ParsedTitle $parsed.SearchTitle -PosterTitle $script:LastPosterDisplayTitle)) {
            $searchTitle = $script:LastPosterDisplayTitle
            $global:DetectedMetadata.Title = $script:LastPosterDisplayTitle
        }

        $cacheMethod = if ($script:PlexSearchLog.Count -gt 0) { $script:PlexSearchLog[0].method } else { $null }
        $resolvedRatingKey = if ($script:PlexSearchLog.Count -gt 0) { $script:PlexSearchLog[0].ratingKey } else { "" }

        $contentLibrary = $null
        if ($path -match '\\ANIME_DIBUS\\') {
            $contentLibrary = "ANIME_DIBUS"
        }

        $parseConfidence = switch ($global:PatternDetected) {
            { $_ -in @("EPISODIO_SIMPLE") } { 95 }
            { $_ -in @("TEMPORADA", "TEMPORADA_PACK", "TEMPORADA_ORDINAL", "TEMPORADA_NOMBRE", "TEMPORADA_SEASON", "TEMPORADA_S_BRACKET") } { 85 }
            "PELICULA_CON_AÑO" { 80 }
            default {
                if ($global:DetectedMetadata.Type -ne "Desconocido") { 70 } else { 45 }
            }
        }

        $torrentResult = @{
            numero             = $num
            torrent_name       = $name
            nombre_limpio      = [string]$global:CleanName
            content_path       = $path
            content_library    = $contentLibrary
            titulo_detectado   = $searchTitle
            search_title       = $searchTitleClean
            rating_key         = $resolvedRatingKey
            cache_method       = $cacheMethod
            tipo_detectado     = $global:DetectedMetadata.Type
            patron             = $global:PatternDetected
            patron_detectado   = $global:PatternDetected
            resolucion         = $global:Resolution
            tamanio_gb         = $global:SizeGB
            contenido_existe   = $global:ContentExists
            poster_encontrado  = if ($poster) { $true } else { $false }
            poster_url         = $poster
            parse_confidence   = $parseConfidence
            tags_tecnicos      = $global:TechnicalTags -join ","
            plex_responses     = @()
            error_general      = $null
            timestamp          = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            test_cache_mode    = $script:UseTestCache
        }

        $allTorrentResults += $torrentResult

        if ($poster) {
            Write-Host "OK" -ForegroundColor Green
            $found++
        }
        else {
            Write-Host "NO" -ForegroundColor Red
            $notfound++
        }
    }

    $cacheFileData = Get-CacheFileData -ProjectRoot $ProjectRoot
    $cacheEntriesOnDisk = if ($cacheFileData -and $cacheFileData.Data.cache) { @($cacheFileData.Data.cache).Count } else { 0 }

    Write-Log "=== PASADA 1 fin: $found posters / $($torrents.Count) torrents, $cacheEntriesOnDisk entradas en caché test ==="

    if (-not $SkipPass2) {
        $validation = Invoke-CacheValidationPass `
            -TorrentResults $allTorrentResults `
            -ProjectRoot $ProjectRoot `
            -ResultsPath $ResultsPath `
            -CacheOnlyComparison
    }
    else {
        Write-Log "Pasada 2 omitida (SkipPass2)"
        Write-Host "Pasada 2 omitida (-SkipPass2)" -ForegroundColor Yellow
    }
}
else {
    $script:UseTestCache = $false
    Write-Host "Pre-cargando cache producción..." -ForegroundColor Cyan
    Initialize-PlexCache -SkipDelay $true -ProjectRoot $ProjectRoot
    Write-Host "Cache cargado: $($script:PlexCache.Count) títulos" -ForegroundColor Green

    foreach ($idx in 0..($torrents.Count - 1)) {
        $torrent = $torrents[$idx]
        $num = $idx + 1

        $name = $torrent.torrent_name.Trim()
        $path = $torrent.content_path.Trim()

        if ([string]::IsNullOrEmpty($name)) {
            Write-Host "[$num/$($torrents.Count)] [SKIP] Nombre vacío" -ForegroundColor Gray
            continue
        }

        Write-Host -NoNewline "[$num/$($torrents.Count)] $name ... "

        $script:PlexSearchLog = @()
        $script:LastPosterDisplayTitle = $null

        $parsed = Get-TorrentSearchMetadata -TorrentName $name -ContentPath $path
        $global:OriginalName = $parsed.OriginalName
        $global:NormalizedName = Normalize-Name $parsed.OriginalName
        $global:CleanName = $parsed.CleanName
        $global:DetectedMetadata = $parsed.DetectedMetadata
        $global:PatternDetected = $parsed.PatternDetected
        $global:Resolution = Get-Resolution $global:NormalizedName
        $global:SizeGB = Get-SizeGB $path
        $global:TechnicalTags = Get-TechnicalTags $global:NormalizedName
        $global:ContentExists = $parsed.ContentExists

        $searchTitle = $parsed.SearchTitle
        $searchTitleClean = $parsed.SearchTitleClean

        $poster = Get-PlexPoster -Title $searchTitle -ContentPath $path `
                                 -DetectedMetadata $global:DetectedMetadata `
                                 -BasePath $TestBasePath `
                                 -PlexScanPollSeconds $script:PlexScanPollSeconds `
                                 -PlexScanPollMaxAttempts $script:PlexScanPollMaxAttempts `
                                 -SkipPlexScan:$script:SkipPlexScan

        if ($script:LastPosterDisplayTitle -and $global:DetectedMetadata.Type -eq "PELICULA" -and (Test-PosterTitleRefinement -ParsedTitle $parsed.SearchTitle -PosterTitle $script:LastPosterDisplayTitle)) {
            $searchTitle = $script:LastPosterDisplayTitle
            $global:DetectedMetadata.Title = $script:LastPosterDisplayTitle
        }

        $cacheMethod = if ($script:PlexSearchLog.Count -gt 0) { $script:PlexSearchLog[0].method } else { $null }
        $resolvedRatingKey = if ($script:PlexSearchLog.Count -gt 0) { $script:PlexSearchLog[0].ratingKey } else { "" }

        $contentLibrary = $null
        if ($path -match '\\ANIME_DIBUS\\') {
            $contentLibrary = "ANIME_DIBUS"
        }

        $parseConfidence = switch ($global:PatternDetected) {
            { $_ -in @("EPISODIO_SIMPLE") } { 95 }
            { $_ -in @("TEMPORADA", "TEMPORADA_PACK", "TEMPORADA_ORDINAL", "TEMPORADA_NOMBRE", "TEMPORADA_SEASON", "TEMPORADA_S_BRACKET") } { 85 }
            "PELICULA_CON_AÑO" { 80 }
            default {
                if ($global:DetectedMetadata.Type -ne "Desconocido") { 70 } else { 45 }
            }
        }

        $torrentResult = @{
            numero             = $num
            torrent_name       = $name
            nombre_limpio      = [string]$global:CleanName
            content_path       = $path
            content_library    = $contentLibrary
            titulo_detectado   = $searchTitle
            search_title       = $searchTitleClean
            rating_key         = $resolvedRatingKey
            cache_method       = $cacheMethod
            tipo_detectado     = $global:DetectedMetadata.Type
            patron             = $global:PatternDetected
            patron_detectado   = $global:PatternDetected
            resolucion         = $global:Resolution
            tamanio_gb         = $global:SizeGB
            contenido_existe   = $global:ContentExists
            poster_encontrado  = if ($poster) { $true } else { $false }
            poster_url         = $poster
            parse_confidence   = $parseConfidence
            tags_tecnicos      = $global:TechnicalTags -join ","
            plex_responses     = @()
            error_general      = $null
            timestamp          = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            test_cache_mode    = $script:UseTestCache
        }

        $allTorrentResults += $torrentResult

        if ($poster) {
            Write-Host "OK" -ForegroundColor Green
            $found++
        }
        else {
            Write-Host "NO" -ForegroundColor Red
            $notfound++
        }
    }
}

$duracion = ((Get-Date) - $inicio).TotalSeconds
$torrentCount = if ($ReplayCacheOnly) { $allTorrentResults.Count } else { $torrents.Count }
$coverage = if ($torrentCount -gt 0) { [math]::Round(($found / $torrentCount) * 100, 2) } else { 0 }

Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "RESULTADOS:" -ForegroundColor Green
Write-Host "  Total: $torrentCount" -ForegroundColor Green
Write-Host "  Encontrados: $found" -ForegroundColor Green
Write-Host "  No encontrados: $notfound" -ForegroundColor Green
Write-Host "  Cobertura: $coverage%" -ForegroundColor Green
Write-Host "  Duracion: $([math]::Round($duracion, 2))s" -ForegroundColor Green
if ($isFullTest -or $ReplayCacheOnly) {
    Write-Host "  Caché test: test/recursos/plex_cache_test.json" -ForegroundColor Green
    if ($validation) {
        Write-Host "  Pasada 2 OK: $($validation.Ok)/$($validation.Total)" -ForegroundColor Green
    }
    elseif ($SkipPass2) {
        Write-Host "  Pasada 2: omitida" -ForegroundColor Yellow
    }
}
Write-Host "=======================================" -ForegroundColor Cyan

if (-not $ReplayCacheOnly) {
    $JsonFolder = Join-Path $ResultsPath "json"
    if (-not (Test-Path $JsonFolder)) {
        New-Item -ItemType Directory -Path $JsonFolder -Force | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $JsonFile = Join-Path $JsonFolder "TelegramNotifier_Test_$Timestamp.json"

    $runMode = if ($QuickTest) { "QUICK_TEST" }
               elseif ($MaxTorrents -gt 0) { "PARTIAL_TEST" }
               else { "FULL_TEST" }

    $resumen = @{
        total_torrents       = $torrentCount
        encontrados          = $found
        no_encontrados       = $notfound
        cobertura_porcentaje = $coverage
        duracion_segundos    = [math]::Round($duracion, 2)
        timestamp_inicio     = $inicio.ToString("yyyy-MM-dd HH:mm:ss.fff")
        timestamp_fin        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
        modo                 = $runMode
        cache_size           = $script:PlexCache.Count
        test_cache_mode      = $script:UseTestCache
        keep_test_cache      = $KeepTestCache.IsPresent
        skip_pass2           = $SkipPass2.IsPresent
    }

    if ($isFullTest) {
        $resumen.cache_test_file = Get-PlexCacheFilePath -ProjectRoot $ProjectRoot
        if ($validation) {
            $resumen.pasada2_ok = $validation.Ok
            $resumen.pasada2_fail = $validation.Fail
            $resumen.pasada2_json = $validation.JsonFile
        }
    }

    $jsonOutput = @{
        resumen  = $resumen
        torrents = $allTorrentResults
    }

    $jsonOutput | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFile -Encoding UTF8

    Write-Host "`nJSON exportado: $JsonFile" -ForegroundColor Green
    Write-Host "Total registros: $($allTorrentResults.Count)" -ForegroundColor Green
}
else {
    Write-Host "`nReplay completado (sin nuevo JSON de pasada 1)" -ForegroundColor Green
    Write-Host "Validación caché: $($validation.JsonFile)" -ForegroundColor Green
}

if ($isFullTest) {
    Write-Log "=== TEST FULL - fin ==="
    if ($validation) {
        Write-Host "Validación caché: $($validation.JsonFile)" -ForegroundColor Green
    }
}

if ($ReplayCacheOnly) {
    Write-Log "=== REPLAY - fin ==="
}

exit 0
