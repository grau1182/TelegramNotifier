# Genera recursos/torrents.csv desde qBittorrent_listado.json (v1 o v2)

param(
    [switch]$OnlyWithContent,
    [switch]$OnlyCompleted,
    [switch]$FullTestTierOnly
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$JsonFile = Join-Path $ProjectRoot "recursos\listado_qbittorrent\qBittorrent_listado.json"
$CsvFile = Join-Path $ProjectRoot "recursos\torrents.csv"

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
    $torrents = @($data.torrents)
}
elseif ($data -is [System.Array]) {
    Write-Host "Formato JSON legacy (array plano)" -ForegroundColor DarkGray
    $torrents = @($data)
}
else {
    $torrents = @($data)
}

if ($OnlyWithContent) {
    $torrents = @($torrents | Where-Object {
        if ($_.PSObject.Properties.Name -contains 'content_exists') {
            return [bool]$_.content_exists
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$_.content_path)) {
            return Test-Path -LiteralPath ([string]$_.content_path)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$_.Ruta)) {
            return Test-Path -LiteralPath ([string]$_.Ruta)
        }
        return $false
    })
    Write-Host "Filtro OnlyWithContent: $($torrents.Count) torrents" -ForegroundColor Yellow
}

if ($OnlyCompleted) {
    $torrents = @($torrents | Where-Object {
        if ($_.PSObject.Properties.Name -contains 'progress') {
            return [double]$_.progress -ge 1.0
        }
        if ($_.PSObject.Properties.Name -contains 'state') {
            return [string]$_.state -in @('uploading', 'stalledUP', 'pausedUP')
        }
        return $true
    })
    Write-Host "Filtro OnlyCompleted: $($torrents.Count) torrents" -ForegroundColor Yellow
}

if ($FullTestTierOnly) {
    $torrents = @($torrents | Where-Object {
        if ($_.PSObject.Properties.Name -contains 'test_tier') {
            return [string]$_.test_tier -eq 'full'
        }
        return $true
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

    $csvRows += [PSCustomObject]@{
        torrent_name   = $name
        content_path   = $path
    }
}

Write-Host "Exportando $($csvRows.Count) items a CSV..." -ForegroundColor Green
$csvRows | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8

Write-Host "Verificando CSV..." -ForegroundColor Cyan
$check = @(Import-Csv -Path $CsvFile)
Write-Host "Items en CSV: $($check.Count)" -ForegroundColor Green

if ($check.Count -gt 0) {
    Write-Host "Primeros 3 items:" -ForegroundColor Yellow
    $check | Select-Object -First 3 | ForEach-Object {
        Write-Host "  $($_.torrent_name)" -ForegroundColor White
        Write-Host "    -> $($_.content_path)" -ForegroundColor Green
    }
}
