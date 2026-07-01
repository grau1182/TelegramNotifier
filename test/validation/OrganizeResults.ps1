# ORGANIZE RESULTS INTO PROPER FOLDER STRUCTURE
# Separa análisis y JSONs de pruebas de los reales

$BasePath = "C:\Users\grau_\Downloads\TelegramNotifier"
$ResultsPath = Join-Path $BasePath "test\results"

$AnalisisRealesPath = Join-Path $ResultsPath "analisis"
$AnalisisPruebasPath = Join-Path $ResultsPath "analisis\pruebas"
$JsonRealesPath = Join-Path $ResultsPath "json"
$JsonPruebasPath = Join-Path $ResultsPath "json\pruebas"

Write-Host "[ORGANIZACION] Clasificando y moviendo archivos"
Write-Host "================================================"
Write-Host ""

# Crear directorios si no existen
@($AnalisisRealesPath, $AnalisisPruebasPath, $JsonRealesPath, $JsonPruebasPath) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

# CLASIFICAR JSONs
Write-Host "[JSONS] Analizando y clasificando..."
$jsonFiles = Get-ChildItem $ResultsPath -Filter "*.json" -File

foreach ($file in $jsonFiles) {
    # Archivos especiales que no clasificamos
    if ($file.Name -eq "torrents.json" -or $file.Name -eq "muestra_resultados.json") {
        Write-Host "  [SKIP] $($file.Name) (archivo especial)"
        continue
    }
    
    try {
        $json = Get-Content $file.FullName -Encoding UTF8 | ConvertFrom-Json
        
        # Detectar si es de prueba
        $isPrueba = $false
        
        if ($json.torrents) {
            $testCount = ($json.torrents | Where-Object { 
                $_.nombre_normalizado -match '^test-' -or 
                $_.titulo_final -match '^Test '
            }).Count
            
            if ($testCount -gt 0) {
                $isPrueba = $true
            }
        }
        
        $destPath = if ($isPrueba) { $JsonPruebasPath } else { $JsonRealesPath }
        $destFile = Join-Path $destPath $file.Name
        
        if ($destFile -ne $file.FullName) {
            Move-Item -Path $file.FullName -Destination $destFile -Force
            $tipo = if ($isPrueba) { "PRUEBA" } else { "REAL" }
            Write-Host "  [MOVIDO] $($file.Name) -> json/$tipo/"
        }
    } catch {
        Write-Host "  [ERROR] $($file.Name): $($_.Exception.Message)"
    }
}

Write-Host ""

# CLASIFICAR HTMLs (ANÁLISIS)
Write-Host "[ANALISIS] Analizando y clasificando..."
$htmlFiles = Get-ChildItem $ResultsPath -Filter "TelegramNotifier_Analisis_*.html" -File

foreach ($file in $htmlFiles) {
    try {
        $content = Get-Content $file.FullName -Encoding UTF8 -Raw
        
        # Detectar si es de prueba (contiene "test" en los datos)
        $isPrueba = $content -match "test-s01e01|test-movie|test-s01e02"
        
        $destPath = if ($isPrueba) { $AnalisisPruebasPath } else { $AnalisisRealesPath }
        $destFile = Join-Path $destPath $file.Name
        
        if ($destFile -ne $file.FullName) {
            Move-Item -Path $file.FullName -Destination $destFile -Force
            $tipo = if ($isPrueba) { "PRUEBA" } else { "REAL" }
            Write-Host "  [MOVIDO] $($file.Name) -> analisis/$tipo/"
        }
    } catch {
        Write-Host "  [ERROR] $($file.Name): $($_.Exception.Message)"
    }
}

Write-Host ""

# Resumen final
Write-Host "[RESUMEN]"
Write-Host "========="
Write-Host ""

Write-Host "JSONs REALES:"
(Get-ChildItem $JsonRealesPath -Filter "*.json").Count | ForEach-Object { Write-Host "  Count: $_" }

Write-Host "JSONs PRUEBAS:"
(Get-ChildItem $JsonPruebasPath -Filter "*.json").Count | ForEach-Object { Write-Host "  Count: $_" }

Write-Host ""

Write-Host "Análisis REALES:"
(Get-ChildItem $AnalisisRealesPath -Filter "*.html").Count | ForEach-Object { Write-Host "  Count: $_" }

Write-Host "Análisis PRUEBAS:"
(Get-ChildItem $AnalisisPruebasPath -Filter "*.html").Count | ForEach-Object { Write-Host "  Count: $_" }

Write-Host ""
Write-Host "[HECHO] Organización completada"
