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

    # Parseado del nombre
    $OriginalName = [System.IO.Path]::GetFileNameWithoutExtension($TorrentName)
    $NormalizedName = Normalize-Name $OriginalName
    $CleanName = Get-CleanName $OriginalName
    
    # Extracción de metadata
    $Resolution = Get-Resolution $NormalizedName
    $SizeGB = Get-SizeGB $ContentPath
    $PatternDetected = Get-PatternDetected $CleanName
    $TechnicalTags = Get-TechnicalTags $NormalizedName
    $ContentExists = if ([string]::IsNullOrEmpty($ContentPath)) { $false } else { Test-Path $ContentPath }

    # Metadata detectada
    $DetectedMetadata = @{ Title = ""; Year = $null; Season = $null; Episode = $null; Type = "Desconocido" }
    $EpisodeCount = 0

    # ==================================================
    # DETECCION DE TIPO
    # ==================================================

    if ($CleanName -match '^(.*?)-s(\d{1,2})e(\d{1,2})(?:-|$)') {
        $Title   = Convert-Title $Matches[1]
        $Season  = [int]$Matches[2]
        $Episode = [int]$Matches[3]

        $DetectedMetadata.Title = $Title
        $DetectedMetadata.Season = $Season
        $DetectedMetadata.Episode = $Episode
        $DetectedMetadata.Type = "EPISODIO"

        Write-Log "Tipo: EPISODIO (S$($Season.ToString('D2'))E$($Episode.ToString('D2')))" -Level "INFO"
    }

    elseif ($CleanName -match '^(.*?)-s(\d{1,2})(?:-|$)') {
        $Title  = Convert-Title $Matches[1]
        $Season = [int]$Matches[2]
        $EpisodeCount = Count-Episodes $ContentPath

        $DetectedMetadata.Title = $Title
        $DetectedMetadata.Season = $Season
        $DetectedMetadata.Type = "TEMPORADA"

        Write-Log "Tipo: TEMPORADA (S$Season con $EpisodeCount episodios)" -Level "INFO"
    }

    elseif ($CleanName -match '^(.*?)[-\s\(](19\d{2}|20\d{2})[\)\-]?') {
        $Title = $Matches[1]
        $Title = $Title -replace '\[.*\]', ''
        $Title = $Title.Trim()
        $Title = Convert-Title $Title
        $Year  = $Matches[2]

        $DetectedMetadata.Title = $Title
        $DetectedMetadata.Year = $Year
        $DetectedMetadata.Type = "PELICULA"

        Write-Log "Tipo: PELICULA ($Year)" -Level "INFO"
    }

    else {
        $Title = Convert-Title $CleanName
        $DetectedMetadata.Title = $Title
        $DetectedMetadata.Type = "DESCONOCIDO"

        Write-Log "Tipo: DESCONOCIDO" -Level "WARNING"
    }

    Write-Log "Título detectado: $($DetectedMetadata.Title)" -Level "INFO"

    # ==================================================
    # BUSCAR POSTER
    # ==================================================

    $script:LastPosterDisplayTitle = $null
    $PosterUrl = Get-PlexPoster -Title $DetectedMetadata.Title `
                                 -ContentPath $ContentPath `
                                 -DetectedMetadata $DetectedMetadata `
                                 -BasePath $BasePath `
                                 -PlexScanPollSeconds $script:PlexScanPollSeconds `
                                 -PlexScanPollMaxAttempts $script:PlexScanPollMaxAttempts `
                                 -SkipPlexScan:$script:SkipPlexScan

    $DisplayTitle = if ($script:LastPosterDisplayTitle) { $script:LastPosterDisplayTitle } else { $DetectedMetadata.Title }

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
