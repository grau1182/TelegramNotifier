# ==================================================
# WRAPPER: Test Data Generator v4 - Con Exportación Completa
# ==================================================

param(
    [int]$MaxTorrents = 0,
    [switch]$QuickTest = $false
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$TestBasePath = $PSScriptRoot
$ScriptPath = Join-Path $TestBasePath "TelegramTorrent_Test.ps1"
$TorrentListPath = Join-Path $ProjectRoot "recursos\torrents.csv"
$ResultsPath = Join-Path $TestBasePath "results"
$LogFolder = Join-Path $TestBasePath "logs"

# Verificar que existen archivos
if (-not (Test-Path $TorrentListPath)) {
    Write-Host "ERROR: recursos/torrents.csv no encontrado" -ForegroundColor Red
    exit 1
}

# Leer torrents
$torrents = @(Import-Csv -Path $TorrentListPath -Encoding UTF8)

if ($QuickTest) {
    $torrents = @($torrents | Select-Object -First 10)
    Write-Host "QUICK TEST: Procesando 10 torrents (SkipPlexScan activo)" -ForegroundColor Yellow
}
elseif ($MaxTorrents -gt 0) {
    $torrents = @($torrents | Select-Object -First $MaxTorrents)
}

$isFullTest = (-not $QuickTest) -and ($MaxTorrents -le 0)

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "WRAPPER v4 - TEST CON CACHE" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Torrents: $($torrents.Count)" -ForegroundColor Green
if ($isFullTest) {
    Write-Host "Modo: FULL (caché test + pasada 2)" -ForegroundColor Green
}
else {
    Write-Host "Modo: $(if ($QuickTest) { 'QUICK' } else { 'PARCIAL' }) (caché producción)" -ForegroundColor Yellow
}

$inicio = Get-Date
$found = 0
$notfound = 0
$allTorrentResults = @()

# Dot-source: Carga TODAS las funciones del script en memoria (comparte scope)
. $ScriptPath -TestMode $true -ResultsFolder $ResultsPath -SkipPlexScan:$QuickTest

. (Join-Path $TestBasePath "lib\test-cache-helpers.ps1")

$script:ProjectRoot = $ProjectRoot

if ($isFullTest) {
    Archive-TestSessionLog -LogFolder $LogFolder
    Write-Log "========================================"
    Write-Log "=== TEST FULL - inicio ==="
    Write-Log "========================================"

    $script:UseTestCache = $true
    Reset-PlexCache
    Initialize-EmptyTestCacheFile -ProjectRoot $ProjectRoot
    Initialize-PlexCache -ForceReload -ProjectRoot $ProjectRoot

    Write-Host "Caché test vacía: test/recursos/plex_cache_test.json" -ForegroundColor Cyan
    Write-Log "=== PASADA 1: Plex + generación plex_cache_test.json ==="
}
else {
    $script:UseTestCache = $false
    Write-Host "Pre-cargando cache producción..." -ForegroundColor Cyan
    Initialize-PlexCache -SkipDelay $true -ProjectRoot $ProjectRoot
    Write-Host "Cache cargado: $($script:PlexCache.Count) títulos" -ForegroundColor Green
}

# Procesar cada torrent
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

    # Buscar poster (paridad con producción; SkipPlexScan solo en QuickTest)
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

$duracion = ((Get-Date) - $inicio).TotalSeconds
$coverage = if ($torrents.Count -gt 0) { [math]::Round(($found / $torrents.Count) * 100, 2) } else { 0 }

if ($isFullTest) {
    $cacheFilePath = Get-PlexCacheFilePath -ProjectRoot $ProjectRoot
    $cacheFileData = Get-CacheFileData -ProjectRoot $ProjectRoot
    $cacheEntriesOnDisk = if ($cacheFileData -and $cacheFileData.Data.cache) { @($cacheFileData.Data.cache).Count } else { 0 }

    Write-Log "=== PASADA 1 fin: $found posters / $($torrents.Count) torrents, $cacheEntriesOnDisk entradas en caché test ==="

    $validation = Invoke-CacheValidationPass `
        -TorrentResults $allTorrentResults `
        -ProjectRoot $ProjectRoot `
        -ResultsPath $ResultsPath
}

Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "RESULTADOS:" -ForegroundColor Green
Write-Host "  Total: $($torrents.Count)" -ForegroundColor Green
Write-Host "  Encontrados: $found" -ForegroundColor Green
Write-Host "  No encontrados: $notfound" -ForegroundColor Green
Write-Host "  Cobertura: $coverage%" -ForegroundColor Green
Write-Host "  Duracion: $([math]::Round($duracion, 2))s" -ForegroundColor Green
if ($isFullTest) {
    Write-Host "  Caché test: test/recursos/plex_cache_test.json" -ForegroundColor Green
    Write-Host "  Pasada 2 OK: $($validation.Ok)/$($validation.Total)" -ForegroundColor Green
}
Write-Host "=======================================" -ForegroundColor Cyan

# ==================================================
# EXPORTAR RESULTADOS A JSON - COMPLETO
# ==================================================

$JsonFolder = Join-Path $ResultsPath "json"
if (-not (Test-Path $JsonFolder)) {
    New-Item -ItemType Directory -Path $JsonFolder -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$JsonFile = Join-Path $JsonFolder "TelegramNotifier_Test_$Timestamp.json"

$resumen = @{
    total_torrents       = $torrents.Count
    encontrados          = $found
    no_encontrados       = $notfound
    cobertura_porcentaje = $coverage
    duracion_segundos    = [math]::Round($duracion, 2)
    timestamp_inicio     = $inicio.ToString("yyyy-MM-dd HH:mm:ss.fff")
    timestamp_fin        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    modo                 = if ($QuickTest) { "QUICK_TEST" } elseif ($MaxTorrents -gt 0) { "PARTIAL_TEST" } else { "FULL_TEST" }
    cache_size           = $script:PlexCache.Count
    test_cache_mode      = $script:UseTestCache
}

if ($isFullTest) {
    $resumen.cache_test_file = Get-PlexCacheFilePath -ProjectRoot $ProjectRoot
    $resumen.pasada2_ok = $validation.Ok
    $resumen.pasada2_fail = $validation.Fail
    $resumen.pasada2_json = $validation.JsonFile
}

$jsonOutput = @{
    resumen  = $resumen
    torrents = $allTorrentResults
}

$jsonOutput | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFile -Encoding UTF8

Write-Host "`nJSON exportado: $JsonFile" -ForegroundColor Green
Write-Host "Total registros: $($allTorrentResults.Count)" -ForegroundColor Green

if ($isFullTest) {
    Write-Log "=== TEST FULL - fin ==="
    Write-Host "Validación caché: $($validation.JsonFile)" -ForegroundColor Green
}
