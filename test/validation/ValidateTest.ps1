# ==================================================
# TEST VALIDATION - Quick test with single torrent
# ==================================================

$BasePath = "C:\Users\grau_\Downloads\TelegramNotifier"
$TestScriptPath = Join-Path $BasePath "test\TelegramTorrent_Test.ps1"
$ResultsFolder = Join-Path $BasePath "test\results"

Write-Host "[VALIDACION] Prueba de Validacion Rapida"
Write-Host "================================="
Write-Host ""

# Limpiar resultados anteriores
if (Test-Path $ResultsFolder) {
    $oldFiles = Get-ChildItem $ResultsFolder -Filter "TelegramNotifier_Test_*.json" | Sort-Object CreationTime -Descending | Select-Object -Skip 1
    $oldFiles | Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host "[1/3] Ejecutando prueba con un torrent de ejemplo..."
Write-Host ""

# Ejecutar con un torrent de prueba
& $TestScriptPath `
    -TorrentName "Test S01E01 2160p WEB-DL.mkv" `
    -ContentPath "G:\TEST" `
    -TestMode:$true

Write-Host ""
Write-Host "[2/3] Verificando que se capturaron datos..."

# Buscar el JSON más reciente
$latestJson = Get-ChildItem $ResultsFolder -Filter "TelegramNotifier_Test_*.json" -ErrorAction SilentlyContinue | 
    Sort-Object Name -Descending | 
    Select-Object -First 1

if ($latestJson) {
    Write-Host "[OK] JSON encontrado: $($latestJson.Name)"
    
    $data = Get-Content $latestJson.FullName -Encoding UTF8 | ConvertFrom-Json
    
    Write-Host ""
    Write-Host "[DATOS] Información capturada:"
    Write-Host "  - Total torrents: $($data.torrents.Count)"
    Write-Host "  - Patron detectado: $($data.torrents[0].patron_detectado)"
    Write-Host "  - Parse confidence: $($data.torrents[0].parse_confidence)%"
    Write-Host "  - Tipo detectado: $($data.torrents[0].tipo_detectado)"
    Write-Host "  - Tags tecnicos: $($data.torrents[0].tag_tecnico_detectado -join ', ')"
    Write-Host "  - Poster encontrado: $($data.torrents[0].poster_encontrado)"
    Write-Host "  - Respuestas Plex capturadas: $($data.torrents[0].plex_responses.Count)"
    Write-Host "  - Duracion: $($data.torrents[0].duracion_ms)ms"
    
    Write-Host ""
    Write-Host "[3/3] Generando analisis HTML..."
    
    # Generar análisis
    & (Join-Path $BasePath "test\AnalyzeResults.ps1")
    
} else {
    Write-Host "[ERROR] No se encontro archivo JSON"
}

Write-Host ""
Write-Host "[OK] Validacion completada"
