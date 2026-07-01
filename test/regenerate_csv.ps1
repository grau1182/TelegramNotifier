# Generar CSV correcto desde JSON
$BasePath = "C:\Users\grau_\Downloads\TelegramNotifier"
$JsonFile = Join-Path $BasePath "recursos\listado_qbittorrent\qBittorrent_listado.json"
$CsvFile = Join-Path $BasePath "recursos\torrents.csv"

Write-Host "Leyendo JSON..." -ForegroundColor Cyan
$data = Get-Content $JsonFile -Raw | ConvertFrom-Json

if ($data -is [array]) {
    $torrents = $data
} else {
    $torrents = @($data)
}

Write-Host "Creando CSV con PSCustomObject..." -ForegroundColor Cyan

$csvRows = @()
foreach ($t in $torrents) {
    $csvRows += [PSCustomObject]@{
        torrent_name = $t.Torrent
        content_path = $t.Ruta
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
        Write-Host "  $($_.torrent_name) -> $($_.content_path)" -ForegroundColor Green
    }
}
