param (
    [string]$TorrentName,
    [string]$ContentPath,
    [switch]$TestMode = $true,
    [string]$TorrentType = "Desconocido",
    [string]$ResultsFolder = "",
    [int]$PlexScanPollSeconds = 5,
    [int]$PlexScanPollMaxAttempts = 12,
    [switch]$SkipPlexScan = $false,
    [string]$ExportResultPath = ""
)

# ==================================================
# CONFIGURACION
# ==================================================

$BotToken = "8755898341:AAFSxCy9zjYS_rLl-kFpVPCmJ3V2XLjKjYg"
$ChatID   = "-1004350117652"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$TestBasePath = $PSScriptRoot
$script:ProjectRoot = $ProjectRoot

$LogFolder = Join-Path $TestBasePath "logs"
$LogFile   = Join-Path $LogFolder "TelegramNotifier_Test.log"

# ========================================
# PLEX
# ========================================

$PlexUrl   = "http://127.0.0.1:32400"
$PlexToken = "Yt-aqViZD-ydpysRvGyP"
$script:SkipPlexScan = $SkipPlexScan.IsPresent
$script:PlexScanPollSeconds = $PlexScanPollSeconds
$script:PlexScanPollMaxAttempts = $PlexScanPollMaxAttempts
$script:PlexMoviePathPrefix = "G:\PELIS"
$script:PlexSeriesPathPrefix = "G:\SERIES"

# ========================================
# TEST CAPTURE (GLOBAL VARIABLES)
# ========================================

if ($TestMode) {
    $script:TestResults = @{
        torrents = @()
    }
    $script:PlexSearchLog = @()
    $script:SizeError = $null
    $script:PlexCacheLoaded = $false
    $script:PlexCache = @()
    
    # Usar ResultsFolder parametro si se proporciona, sino usar default
    if ([string]::IsNullOrEmpty($ResultsFolder)) {
        $script:ResultsFolder = Join-Path $TestBasePath "results"
    } else {
        $script:ResultsFolder = $ResultsFolder
    }
    
    if (-not (Test-Path $script:ResultsFolder)) {
        New-Item -ItemType Directory -Path $script:ResultsFolder -Force | Out-Null
    }
}

# ==================================================
# LOG
# ==================================================

function Rotate-Log {

    if(Test-Path $LogFile){

        $SizeMB = (Get-Item $LogFile).Length / 1MB

        if($SizeMB -ge 5){

            $Date = Get-Date -Format "yyyyMMdd_HHmmss"
            
            Rename-Item `
                -Path $LogFile `
                -NewName "TelegramNotifier_$Date.log"
        }
    }
}

function Write-Log {

    param([string]$Text, [string]$Level = "INFO")

    Rotate-Log

    try {

        if (!(Test-Path $LogFolder)) {
            New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        Add-Content `
            -Path $LogFile `
            -Value "[$Timestamp] [$Level] $Text"

    }
    catch {}
}

# ==================================================
# LIBRERIAS (compartidas con core)
# ==================================================

$LibPath = Join-Path $TestBasePath "lib"
. (Join-Path $LibPath "utilities.ps1")
. (Join-Path $LibPath "cache-manager.ps1")
. (Join-Path $LibPath "plex-functions.ps1")

# ==================================================
# INICIO
# ==================================================

if ($TorrentName) {



$TimestampInicio = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"

Write-Log "======================================="

Write-Log "Torrent recibido: $TorrentName"
Write-Log "Ruta recibida: $ContentPath"

$OriginalName =
    [System.IO.Path]::GetFileNameWithoutExtension($TorrentName)

$NormalizedName = Normalize-Name $OriginalName

$CleanName = Get-CleanName $OriginalName

$Resolution = Get-Resolution $NormalizedName

$SizeGB = Get-SizeGB $ContentPath

$SizeError = if ($SizeGB -eq 0 -and -not [string]::IsNullOrWhiteSpace($ContentPath) -and (Test-Path $ContentPath)) { "No se pudo calcular" } else { $null }

Write-Log "Nombre normalizado: $NormalizedName"
Write-Log "Nombre limpio: $CleanName"
Write-Log "Resolucion: $Resolution"
Write-Log "Tamaño: $SizeGB GB"

$TechnicalTags = Get-TechnicalTags $NormalizedName

$parsed = Get-TorrentSearchMetadata -TorrentName $TorrentName -ContentPath $ContentPath
$PatternDetected = $parsed.PatternDetected
$DetectedMetadata = $parsed.DetectedMetadata
$Title = $parsed.SearchTitle
$EpisodeCount = $parsed.EpisodeCount
$ContentExists = $parsed.ContentExists
$searchTitleClean = $parsed.SearchTitleClean

Write-Log "Patron detectado: $PatternDetected"
Write-Log "Tags tecnicos: $($TechnicalTags -join ', ')"
Write-Log "Tipo detectado: $($DetectedMetadata.Type)"
if ($DetectedMetadata.Type -eq "TEMPORADA") {
    Write-Log "Episodios detectados: $EpisodeCount"
}

$ParseConfidence = Get-ParseConfidence -DetectedType $DetectedMetadata.Type -CleanName $parsed.CleanName -Pattern $PatternDetected

$script:LastPosterDisplayTitle = $null
$PosterUrl =
    Get-PlexPoster `
        -Title $Title `
        -ContentPath $ContentPath `
        -DetectedMetadata $DetectedMetadata `
        -BasePath $TestBasePath `
        -PlexScanPollSeconds $script:PlexScanPollSeconds `
        -PlexScanPollMaxAttempts $script:PlexScanPollMaxAttempts `
        -SkipPlexScan:$script:SkipPlexScan

if ($script:LastPosterDisplayTitle -and $DetectedMetadata.Type -eq "PELICULA" -and (Test-PosterTitleRefinement -ParsedTitle $Title -PosterTitle $script:LastPosterDisplayTitle)) {
    $Title = $script:LastPosterDisplayTitle
    $DetectedMetadata.Title = $Title
}

$Message = Format-TelegramMessage `
    -Type $DetectedMetadata.Type `
    -Title $DetectedMetadata.Title `
    -Resolution $Resolution `
    -SizeGB $SizeGB `
    -Season $(if ($DetectedMetadata.Season) { [int]$DetectedMetadata.Season } else { 0 }) `
    -Episode $(if ($DetectedMetadata.Episode) { [int]$DetectedMetadata.Episode } else { 0 }) `
    -Year $(if ($DetectedMetadata.Year) { [string]$DetectedMetadata.Year } else { "" }) `
    -EpisodeCount $EpisodeCount

Write-Log "Mensaje generado:"
Write-Log $Message

if($PosterUrl){
    Write-Log "Poster URL: $PosterUrl"
}

$PosterBytes = 0
if ($PosterUrl) {
    try {
        $TempPoster = Join-Path $env:TEMP "telegram_poster.jpg"
        Invoke-WebRequest -Uri $PosterUrl -OutFile $TempPoster -ErrorAction SilentlyContinue
        if (Test-Path $TempPoster) {
            $PosterBytes = (Get-Item $TempPoster).Length
        }
    }
    catch { }
}

$PlexNoEncontro = $false
if (-not $PosterUrl -and $ContentExists) {
    $PlexNoEncontro = $true
    Write-Log "FALSO NEGATIVO PLEX: Contenido existe en ruta pero no encontrado en Plex"
}

# ==================================================
# TEST MODE: Capturar datos
# ==================================================

if ($TestMode) {
    $TimestampFin = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    
    $testRecord = @{
        torrent_name         = $TorrentName
        original_name        = $OriginalName
        normalized_name      = $NormalizedName
        clean_name           = $CleanName
        detected_type        = $DetectedMetadata.Type
        detected_title       = $DetectedMetadata.Title
        search_title         = $searchTitleClean
        rating_key           = if ($script:PlexSearchLog.Count -gt 0) { $script:PlexSearchLog[0].ratingKey } else { "" }
        cache_method         = if ($script:PlexSearchLog.Count -gt 0) { $script:PlexSearchLog[0].method } else { $null }
        detected_season      = $DetectedMetadata.Season
        detected_episode     = $DetectedMetadata.Episode
        detected_year        = $DetectedMetadata.Year
        parse_confidence     = $ParseConfidence
        pattern_detected     = $PatternDetected
        technical_tags       = $TechnicalTags
        resolution           = $Resolution
        size_gb              = $SizeGB
        size_error           = $SizeError
        content_exists       = $ContentExists
        episode_count        = if ($DetectedMetadata.Type -eq "TEMPORADA") { Count-Episodes $ContentPath } else { $null }
        poster_found         = if ($PosterUrl) { $true } else { $false }
        poster_url           = $PosterUrl
        poster_bytes         = $PosterBytes
        plex_no_encontro     = $PlexNoEncontro
        plex_search_log      = $script:PlexSearchLog
        timestamp_inicio     = $TimestampInicio
        timestamp_fin        = $TimestampFin
    }
    
    $script:TestResults.torrents += $testRecord

    if (-not [string]::IsNullOrWhiteSpace($ExportResultPath)) {
        $testRecord | ConvertTo-Json -Depth 6 | Set-Content -Path $ExportResultPath -Encoding UTF8 -Force
    }
}

# ==================================================
# TELEGRAM (Production)
# ==================================================

if (-not $TestMode) {
    try {

        if($PosterUrl){

            $TempPoster = Join-Path $env:TEMP "telegram_poster.jpg"

            Invoke-WebRequest `
                -Uri $PosterUrl `
                -OutFile $TempPoster

            Write-Log "Poster descargado: $TempPoster"
            Write-Log "Tamaño poster: $((Get-Item $TempPoster).Length)"

            curl.exe `
                -s `
                -X POST `
                "https://api.telegram.org/bot$BotToken/sendPhoto" `
                -F "chat_id=$ChatID" `
                -F "photo=@$TempPoster" `
                -F "caption=$Message" `
                -F "parse_mode=HTML" | Out-Null

            Remove-Item $TempPoster -Force -ErrorAction SilentlyContinue

        }
        else {

            Invoke-RestMethod `
                -Uri "https://api.telegram.org/bot$BotToken/sendMessage" `
                -Method Post `
                -Body @{
                    chat_id    = $ChatID
                    text       = $Message
                    parse_mode = "HTML"
                }

        }

        Write-Log "Envio Telegram OK"

    }
    catch {

        Write-Log "ERROR TELEGRAM"
        Write-Log $_.Exception.Message

    }
}

}
