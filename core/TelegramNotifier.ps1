# ==================================================
# TELEGRAMNOTIFIER.PS1 - Script Principal Producción
# ==================================================
# Versión simplificada para producción
# Incluye:
#   - Búsqueda de posters en Plex
#   - Caché persistente
#   - Envío a Telegram (opcional)

param (
    [string]$TorrentName,
    [string]$ContentPath = "",
    [switch]$SendTelegram = $true,
    [string]$ConfigPath = ".",
    [int]$PlexScanPollSeconds = 5,
    [int]$PlexScanPollMaxAttempts = 12,
    [switch]$SkipPlexScan = $false
)

# ==================================================
# CONFIGURACION
# ==================================================

$BotToken = "8755898341:AAFSxCy9zjYS_rLl-kFpVPCmJ3V2XLjKjYg"
$ChatID   = "-1004350117652"

# Plex
$PlexUrl   = "http://127.0.0.1:32400"
$PlexToken = "Yt-aqViZD-ydpysRvGyP"
$script:PlexScanPollSeconds = $PlexScanPollSeconds
$script:PlexScanPollMaxAttempts = $PlexScanPollMaxAttempts
$script:SkipPlexScan = $SkipPlexScan.IsPresent
$script:PlexMoviePathPrefix = "G:\PELIS"
$script:PlexSeriesPathPrefix = "G:\SERIES"

# Rutas
# Usar $PSScriptRoot por defecto para garantizar logs en core/ sin importar directorio de ejecución
$BasePath = if ([string]::IsNullOrEmpty($ConfigPath) -or $ConfigPath -eq ".") {
    $PSScriptRoot
} else {
    $ConfigPath
}
$script:ProjectRoot = Split-Path $BasePath -Parent

# ==================================================
# CARGAR LIBRERIAS
# ==================================================

$LibPath = Join-Path $PSScriptRoot "lib"

. (Join-Path $LibPath "logger.ps1")
. (Join-Path $LibPath "utilities.ps1")
. (Join-Path $LibPath "cache-manager.ps1") -PlexUrl $PlexUrl -PlexToken $PlexToken
. (Join-Path $LibPath "plex-functions.ps1") -PlexUrl $PlexUrl -PlexToken $PlexToken

# Inicializar logger
Initialize-Logger -LogPath (Join-Path $BasePath "logs")

# ==================================================
# MAIN: PROCESAR TORRENT
# ==================================================

function Process-Torrent {
    param(
        [string]$TorrentName,
        [string]$ContentPath
    )

    Write-Log "========================================" -Level "INFO"
    Write-Log "Procesando torrent: $TorrentName" -Level "INFO"
    Write-Log "Ruta: $ContentPath" -Level "INFO"

    $parsed = Get-TorrentSearchMetadata -TorrentName $TorrentName -ContentPath $ContentPath

    $OriginalName = $parsed.OriginalName
    $NormalizedName = Normalize-Name $OriginalName
    $CleanName = $parsed.CleanName
    $DetectedMetadata = $parsed.DetectedMetadata
    $PatternDetected = $parsed.PatternDetected
    $EpisodeCount = $parsed.EpisodeCount
    $SearchTitle = $parsed.SearchTitle

    $Resolution = Get-Resolution $NormalizedName
    $SizeGB = Get-SizeGB $ContentPath
    $TechnicalTags = Get-TechnicalTags $NormalizedName
    $ContentExists = $parsed.ContentExists

    Write-Log "Patron detectado: $PatternDetected" -Level "INFO"
    Write-Log "Tipo: $($DetectedMetadata.Type)" -Level "INFO"
    if ($DetectedMetadata.Type -eq "TEMPORADA") {
        Write-Log "Episodios detectados: $EpisodeCount" -Level "INFO"
    }
    Write-Log "Título detectado: $SearchTitle" -Level "INFO"

    # ==================================================
    # BUSCAR POSTER
    # ==================================================

    $script:LastPosterDisplayTitle = $null
    $PosterUrl = Get-PlexPoster -Title $SearchTitle `
                                 -ContentPath $ContentPath `
                                 -DetectedMetadata $DetectedMetadata `
                                 -BasePath $BasePath `
                                 -PlexScanPollSeconds $script:PlexScanPollSeconds `
                                 -PlexScanPollMaxAttempts $script:PlexScanPollMaxAttempts `
                                 -SkipPlexScan:$script:SkipPlexScan

    if ($script:LastPosterDisplayTitle -and $DetectedMetadata.Type -eq "PELICULA" -and (Test-PosterTitleRefinement -ParsedTitle $SearchTitle -PosterTitle $script:LastPosterDisplayTitle)) {
        $SearchTitle = $script:LastPosterDisplayTitle
        $DetectedMetadata.Title = $script:LastPosterDisplayTitle
    }

    $DisplayTitle = $DetectedMetadata.Title

    $Message = Format-TelegramMessage `
        -Type $DetectedMetadata.Type `
        -Title $DisplayTitle `
        -Resolution $Resolution `
        -SizeGB $SizeGB `
        -Season $(if ($DetectedMetadata.Season) { [int]$DetectedMetadata.Season } else { 0 }) `
        -Episode $(if ($DetectedMetadata.Episode) { [int]$DetectedMetadata.Episode } else { 0 }) `
        -Year $(if ($DetectedMetadata.Year) { [string]$DetectedMetadata.Year } else { "" }) `
        -EpisodeCount $EpisodeCount

    if ($PosterUrl) {
        Write-Log "Poster encontrado: $PosterUrl" -Level "SUCCESS"
    }
    else {
        Write-Log "No se encontró poster en Plex" -Level "WARNING"
    }

    # ==================================================
    # ENVIAR A TELEGRAM (opcional)
    # ==================================================

    if ($SendTelegram) {
        Send-TelegramNotification -Message $Message -PosterUrl $PosterUrl -BotToken $BotToken -ChatID $ChatID
    }

    Write-Log "========================================" -Level "INFO"

    return @{
        TorrentName = $TorrentName
        Title = $DetectedMetadata.Title
        Type = $DetectedMetadata.Type
        PosterUrl = $PosterUrl
        Message = $Message
    }
}

function Send-TelegramNotification {
    param(
        [string]$Message,
        [string]$PosterUrl,
        [string]$BotToken,
        [string]$ChatID
    )

    try {
        if ($PosterUrl) {
            $TempPoster = Join-Path $env:TEMP "telegram_poster_$(Get-Date -Format 'yyyyMMddHHmmss').jpg"
            Invoke-WebRequest -Uri $PosterUrl -OutFile $TempPoster -ErrorAction SilentlyContinue

            if (Test-Path $TempPoster) {
                curl.exe -s -X POST "https://api.telegram.org/bot$BotToken/sendPhoto" `
                    -F "chat_id=$ChatID" `
                    -F "photo=@$TempPoster" `
                    -F "caption=$Message" `
                    -F "parse_mode=HTML" | Out-Null

                Remove-Item $TempPoster -Force -ErrorAction SilentlyContinue
                Write-Log "Notificación Telegram enviada (con poster)" -Level "SUCCESS"
            }
        }
        else {
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/sendMessage" `
                -Method Post `
                -Body @{
                    chat_id    = $ChatID
                    text       = $Message
                    parse_mode = "HTML"
                } | Out-Null

            Write-Log "Notificación Telegram enviada (texto)" -Level "SUCCESS"
        }
    }
    catch {
        Write-Log "Error enviando Telegram: $($_.Exception.Message)" -Level "ERROR"
    }
}

# ==================================================
# EJECUTAR SI SE PROPORCIONA TORRENT
# ==================================================

if ($TorrentName) {
    $result = Process-Torrent -TorrentName $TorrentName -ContentPath $ContentPath
    exit 0
}
else {
    Write-Host "`n❌ Uso: .\TelegramNotifier.ps1 -TorrentName 'archivo.torrent' [-ContentPath 'ruta'] [-SendTelegram]`n" -ForegroundColor Red
    exit 1
}
