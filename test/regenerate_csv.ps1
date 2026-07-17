# Genera recursos/torrents.csv desde qBittorrent_listado.json (v1 o v2)

param(
    [switch]$OnlyWithContent,
    [switch]$OnlyCompleted,
    [switch]$FullTestTierOnly
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$JsonFile = Join-Path $ProjectRoot "recursos\listado_qbittorrent\qBittorrent_listado.json"
$CsvFile = Join-Path $ProjectRoot "recursos\torrents.csv"

function Test-ValidTorrentPathField {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if ($Path -match '\s[A-Za-z]:\\') {
        return $false
    }

    return $true
}

function Test-TorrentContentOnDisk {
    param($Torrent)

    $paths = @()
    if ($Torrent.PSObject.Properties.Name -contains 'content_path') {
        $paths += [string]$Torrent.content_path
    }
    if ($Torrent.PSObject.Properties.Name -contains 'save_path') {
        $paths += [string]$Torrent.save_path
    }
    if ($Torrent.PSObject.Properties.Name -contains 'Ruta') {
        $paths += [string]$Torrent.Ruta
    }

    foreach ($path in ($paths | Where-Object { Test-ValidTorrentPathField $_ } | Select-Object -Unique)) {
        try {
            if (Test-Path -LiteralPath $path) {
                return $true
            }
        }
        catch {
        }
    }

    return $false
}

if (-not (Test-Path $JsonFile)) {
    Write-Host "ERROR: no encontrado $JsonFile" -ForegroundColor Red
    Write-Host "Ejecuta primero recursos\listado_qbittorrent\Exportar_listado_qBittorrent.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "Leyendo JSON..." -ForegroundColor Cyan
$raw = Get-Content $JsonFile -Raw -Encoding UTF8
$data = $raw | ConvertFrom-Json

$torrents = @()
if ($data.version -eq 2 -and $data.torrents) {
    Write-Host "Formato JSON v2 detectado (exportado: $($data.exportedAt))" -ForegroundColor DarkGray
    if ($data.summary) {
        Write-Host "  Resumen JSON: total=$($data.summary.total), content_exists=$($data.summary.content_exists), parse_only=$($data.summary.parse_only)" -ForegroundColor DarkGray
    }
    $torrents = @($data.torrents)
}
elseif ($data -is [System.Array]) {
    Write-Host "Formato JSON legacy (array plano)" -ForegroundColor DarkGray
    $torrents = @($data)
}
else {
    $torrents = @($data)
}

Write-Host "Torrents en JSON: $($torrents.Count)" -ForegroundColor Cyan

if ($OnlyWithContent) {
    $torrents = @($torrents | Where-Object { Test-TorrentContentOnDisk -Torrent $_ })
    Write-Host "Filtro OnlyWithContent (Test-Path en disco): $($torrents.Count) torrents" -ForegroundColor Yellow
}

if ($OnlyCompleted) {
    $torrents = @($torrents | Where-Object {
        $state = if ($_.state -is [System.Array]) { [string]$_.state[0] } else { [string]$_.state }
        if ($state -in @('uploading', 'stalledUP', 'pausedUP', 'forcedUP', 'queuedUP')) {
            return $true
        }
        if ($_.PSObject.Properties.Name -contains 'progress') {
            $progressRaw = if ($_.progress -is [System.Array]) { $_.progress[0] } else { $_.progress }
            $progressValue = 0.0
            if ([double]::TryParse([string]$progressRaw, [ref]$progressValue)) {
                return $progressValue -ge 0.999
            }
        }
        return $false
    })
    Write-Host "Filtro OnlyCompleted: $($torrents.Count) torrents" -ForegroundColor Yellow
}

if ($FullTestTierOnly) {
    $torrents = @($torrents | Where-Object {
        if (Test-TorrentContentOnDisk -Torrent $_) {
            return $true
        }
        if ($_.PSObject.Properties.Name -contains 'test_tier') {
            return [string]$_.test_tier -eq 'full'
        }
        return $false
    })
    Write-Host "Filtro FullTestTierOnly: $($torrents.Count) torrents" -ForegroundColor Yellow
}

Write-Host "Creando CSV..." -ForegroundColor Cyan

$csvRows = @()
foreach ($t in $torrents) {
    $name = if ($t.torrent_name) { [string]$t.torrent_name } else { [string]$t.Torrent }
    $path = if ($t.content_path) { [string]$t.content_path } elseif ($t.Ruta) { [string]$t.Ruta } else { "" }

    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    if (-not (Test-ValidTorrentPathField $path)) {
        Write-Host "  AVISO: ruta invalida omitida para '$($name.Substring(0, [Math]::Min(50, $name.Length)))...'" -ForegroundColor Yellow
        continue
    }

    $csvRows += [PSCustomObject]@{
        torrent_name   = $name
        content_path   = $path
    }
}

Write-Host "Exportando $($csvRows.Count) items a CSV..." -ForegroundColor Green
$utf8Bom = New-Object System.Text.UTF8Encoding $true
$csvLines = $csvRows | ConvertTo-Csv -NoTypeInformation
[System.IO.File]::WriteAllLines($CsvFile, $csvLines, $utf8Bom)

Write-Host "Verificando CSV..." -ForegroundColor Cyan
$check = @(Import-Csv -Path $CsvFile -Encoding UTF8)
Write-Host "Items en CSV: $($check.Count)" -ForegroundColor Green

if ($check.Count -gt 0) {
    Write-Host "Primeros 3 items:" -ForegroundColor Yellow
    $check | Select-Object -First 3 | ForEach-Object {
        Write-Host "  $($_.torrent_name)" -ForegroundColor White
        Write-Host "    -> $($_.content_path)" -ForegroundColor Green
    }
}
elseif ($OnlyWithContent) {
    Write-Host ""
    Write-Host "AVISO: 0 torrents con ruta existente en disco." -ForegroundColor Yellow
    Write-Host "Prueba sin filtro: .\regenerate_csv.ps1" -ForegroundColor DarkGray
    Write-Host "O re-exporta: ..\recursos\listado_qbittorrent\Exportar_listado_qBittorrent.ps1 -OnlyCompleted" -ForegroundColor DarkGray
}
