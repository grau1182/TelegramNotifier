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

# Verificar que existen archivos
if (-not (Test-Path $TorrentListPath)) {
    Write-Host "ERROR: recursos/torrents.csv no encontrado" -ForegroundColor Red
    exit 1
}

# Leer torrents
$torrents = @(Import-Csv -Path $TorrentListPath)

if ($QuickTest) {
    $torrents = @($torrents | Select-Object -First 10)
    Write-Host "QUICK TEST: Procesando 10 torrents" -ForegroundColor Yellow
}
elseif ($MaxTorrents -gt 0) {
    $torrents = @($torrents | Select-Object -First $MaxTorrents)
}

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "WRAPPER v4 - TEST CON CACHE" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Torrents: $($torrents.Count)" -ForegroundColor Green

$inicio = Get-Date
$found = 0
$notfound = 0
$allTorrentResults = @()

# Dot-source: Carga TODAS las funciones del script en memoria (comparte scope)
. $ScriptPath -TestMode $true -ResultsFolder $ResultsPath

# Inicializar cache UNA SOLA VEZ
Write-Host "Pre-cargando cache..." -ForegroundColor Cyan
Initialize-PlexCache -SkipDelay $true -BasePath $TestBasePath
Write-Host "Cache cargado: $($script:PlexCache.Count) títulos" -ForegroundColor Green

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

    # Re-inicializar variables para este torrent
    $global:OriginalName = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $global:NormalizedName = Normalize-Name $global:OriginalName
    $global:CleanName = Get-CleanName $global:OriginalName
    $global:Resolution = Get-Resolution $global:NormalizedName
    $global:SizeGB = Get-SizeGB $path
    $global:PatternDetected = Get-PatternDetected $global:CleanName
    $global:TechnicalTags = Get-TechnicalTags $global:NormalizedName
    $global:ContentExists = if ([string]::IsNullOrEmpty($path)) { $false } else { Test-Path $path }
    $global:DetectedMetadata = @{ Title = ""; Year = $null; Season = $null; Episode = $null; Type = "Desconocido" }
    
    # Detectar tipo y extraer título para búsqueda
    if ($global:CleanName -match '^(.*?)-s(\d{1,2})e(\d{1,2})') {
        $global:DetectedMetadata.Type = "EPISODIO"
        $global:DetectedMetadata.Season = [int]$Matches[2]
        $global:DetectedMetadata.Episode = [int]$Matches[3]
        $searchTitle = Convert-Title $Matches[1]
    }
    elseif ($global:CleanName -match '^(.*?)-s(\d{1,2})(?:-|$)') {
        $global:DetectedMetadata.Type = "TEMPORADA"
        $global:DetectedMetadata.Season = [int]$Matches[2]
        $searchTitle = Convert-Title $Matches[1]
    }
    elseif ($global:CleanName -match '^(.*?)[-\s\(](19\d{2}|20\d{2})[\)\-]?') {
        $global:DetectedMetadata.Type = "PELICULA"
        $global:DetectedMetadata.Year = $Matches[2]
        $searchTitle = Convert-Title $Matches[1]
    }
    else {
        $global:DetectedMetadata.Type = "Desconocido"
        $searchTitle = Convert-Title $global:CleanName
    }
    
    $global:DetectedMetadata.Title = $searchTitle
    $searchTitleClean = Get-SearchTitle -Title $searchTitle -Type $global:DetectedMetadata.Type
    
    # Buscar poster
    $poster = Get-PlexPoster -Title $searchTitle -ContentPath $path `
                             -DetectedMetadata $global:DetectedMetadata `
                             -BasePath $TestBasePath

    $cacheMethod = if ($script:PlexSearchLog.Count -gt 0) { $script:PlexSearchLog[0].method } else { $null }
    $resolvedRatingKey = if ($script:PlexSearchLog.Count -gt 0) { $script:PlexSearchLog[0].ratingKey } else { "" }
    
    # Capturar resultado para este torrent - Estructura compatible con AnalyzeResults
    $cleanTitle = [string]$global:CleanName
    $parseConfidence = if ($poster) { 85 } else { 45 }
    
    $torrentResult = @{
        numero = $num
        torrent_name = $name
        nombre_limpio = $cleanTitle
        content_path = $path
        titulo_detectado = $searchTitle
        search_title = $searchTitleClean
        rating_key = $resolvedRatingKey
        cache_method = $cacheMethod
        tipo_detectado = $global:DetectedMetadata.Type
        patron = $global:PatternDetected
        patron_detectado = $global:PatternDetected
        resolucion = $global:Resolution
        tamanio_gb = $global:SizeGB
        contenido_existe = $global:ContentExists
        poster_encontrado = if ($poster) { $true } else { $false }
        poster_url = $poster
        parse_confidence = $parseConfidence
        tags_tecnicos = $global:TechnicalTags -join ","
        plex_responses = @()
        error_general = $null
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    }
    
    $allTorrentResults += $torrentResult
    
    if ($poster) {
        Write-Host "OK" -ForegroundColor Green
        $found++
    } else {
        Write-Host "NO" -ForegroundColor Red
        $notfound++
    }
}

$duracion = ((Get-Date) - $inicio).TotalSeconds
$coverage = if ($torrents.Count -gt 0) { [math]::Round(($found / $torrents.Count) * 100, 2) } else { 0 }

Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "RESULTADOS:" -ForegroundColor Green
Write-Host "  Total: $($torrents.Count)" -ForegroundColor Green
Write-Host "  Encontrados: $found" -ForegroundColor Green
Write-Host "  No encontrados: $notfound" -ForegroundColor Green
Write-Host "  Cobertura: $coverage%" -ForegroundColor Green
Write-Host "  Duracion: $([math]::Round($duracion, 2))s" -ForegroundColor Green
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

$jsonOutput = @{
    resumen = @{
        total_torrents = $torrents.Count
        encontrados = $found
        no_encontrados = $notfound
        cobertura_porcentaje = $coverage
        duracion_segundos = [math]::Round($duracion, 2)
        timestamp_inicio = $inicio.ToString("yyyy-MM-dd HH:mm:ss.fff")
        timestamp_fin = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
        modo = if ($QuickTest) { "QUICK_TEST" } else { "FULL_TEST" }
        cache_size = $script:PlexCache.Count
    }
    torrents = $allTorrentResults
}

$jsonOutput | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFile -Encoding UTF8

Write-Host "`nJSON exportado: $JsonFile" -ForegroundColor Green
Write-Host "Total registros: $($allTorrentResults.Count)" -ForegroundColor Green
