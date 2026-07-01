# ==============================
# qbittorrent-notify.ps1 (robusto)
# ==============================

param(
    [string]$TorrentName,
    [string]$ContentPath,
    [int]$FileCount,
    [string]$InfoHash
)

# ==============================
# CONFIG
# ==============================
$BotToken = '8755898341:AAFSxCy9zjYS_rLl-kFpVPCmJ3V2XLjKjYg'
$ChatId   = '-1004350117652'

# ==============================
# UTF-8 / SETUP
# ==============================
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()

# ==============================
# DEBUG (activable)
# ==============================
Write-Host "SCRIPT INICIADO"
Write-Host "TORRENT: $TorrentName"
Write-Host "PATH: $ContentPath"

try {

    # ==============================
    # NORMALIZACIÓN ROBUSTA
    # ==============================
    $cleanName = $TorrentName.ToLower()

    # convierte cualquier separador raro en espacio
    $cleanName = $cleanName -replace '[\._\-]+', ' '
    $cleanName = $cleanName -replace '\s+', ' '
    $cleanName = $cleanName.Trim()

    $parseName = $cleanName

    # ==============================
    # VARIABLES
    # ==============================
    $title = ''
    $season = ''
    $episode = ''
    $year = ''
    $episodesText = ''
    $formatText = ''
    $resolution = ''
    $sizeGB = ''
    $qualityText = ''
    $messageTitle = ''

    # ==============================
    # RESOLUCIÓN
    # ==============================
    if ($parseName -match '(\d{3,4}\s*p)') {
        $resolution = ($matches[1] -replace '\s+', '')
    }

    # HDR / DV
    if ($parseName -match '(hdr10\+?|hdr|dolby| dv )') {
        if ($parseName -match '(dolby| dv )') {
            $formatText = 'Dolby Vision'
        } elseif ($parseName -match 'hdr10\+') {
            $formatText = 'HDR10+'
        } elseif ($parseName -match 'hdr') {
            $formatText = 'HDR'
        }
    }

    # ==============================
    # EPISODIO
    # ==============================
    if ($parseName -match '(.*)\s+s?(\d{1,2})\s*e(\d{1,2})\b') {

        $title = $matches[1].Trim()
        $season  = "{0:D2}" -f [int]$matches[2]
        $episode = "{0:D2}" -f [int]$matches[3]

        $messageTitle = "Episodio descargado"
        $episodesText = "T$season · E$episode"
    }

    # ==============================
    # TEMPORADA
    # ==============================
    elseif ($parseName -match '(.*)\s+s(\d{1,2})\s*pack') {

        $title = $matches[1].Trim()
        $season = "{0:D2}" -f [int]$matches[2]

        $messageTitle = "Temporada descargada"

        $videoFiles = Get-ChildItem -Path $ContentPath -Recurse -Include *.mkv,*.mp4,*.avi -File -ErrorAction SilentlyContinue
        $countEp = if ($videoFiles) { $videoFiles.Count } else { $FileCount }

        $episodesText = "$countEp episodios"
    }

    # ==============================
    # PELÍCULA
    # ==============================
    elseif ($parseName -match '^(.+)\s+(\d{4})') {

        $title = $matches[1].Trim()
        $year  = $matches[2]

        $messageTitle = "Película descargada"
    }

    else {
        $title = $cleanName
        $messageTitle = "Descarga completada"
    }

    # ==============================
    # CALIDAD
    # ==============================
    if ($resolution -and $formatText) {
        $qualityText = "$resolution $formatText"
    }
    elseif ($resolution) {
        $qualityText = $resolution
    }

    # ==============================
    # TAMAÑO
    # ==============================
    $totalBytes = 0

    if (Test-Path $ContentPath) {
        Get-ChildItem -Path $ContentPath -Recurse -File |
            ForEach-Object { $totalBytes += $_.Length }
    }

    if ($totalBytes -gt 0) {
        $sizeGB = "{0:N1} GB" -f ($totalBytes / 1GB)
    }

    # ==============================
    # MENSAJE (SIN HTML ENCODE PARA EVITAR ERRORES)
    # ==============================
    $mensaje = "<b>$messageTitle</b>`n`n"
    $mensaje += "$title`n"

    if ($season) {
        if ($episode) {
            $mensaje += "T$season · E$episode`n"
        } else {
            $mensaje += "Temporada $season`n"
        }
    }

    if ($year) {
        $mensaje += "($year)`n"
    }

    $mensaje += "`n"

    if ($episodesText) {
        $mensaje += "📺 $episodesText`n"
    }

    if ($qualityText) {
        $mensaje += "🎞️ $qualityText`n"
    }

    if ($sizeGB) {
        $mensaje += "💾 $sizeGB`n"
    }

    # DEBUG FINAL
    Write-Host "MENSAJE FINAL:"
    Write-Host $mensaje

    # ==============================
    # TELEGRAM
    # ==============================
    $apiUrl = "https://api.telegram.org/bot$BotToken/sendMessage"

    $params = @{
        chat_id = $ChatId
        text = $mensaje
        parse_mode = "HTML"
    }

    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $params

    Write-Host "RESPUESTA TELEGRAM:"
    Write-Host ($response | ConvertTo-Json -Depth 10)

}
catch {
    Write-Host "ERROR CAPTURADO:"
    Write-Host $_.Exception.Message

    ("Error: " + $_.Exception.Message) |
        Out-File -FilePath "$env:TEMP\qbittorrent_telegram_error.log" -Append
}