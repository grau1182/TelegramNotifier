# CONSOLIDATE RESULTS ONLY
# Consolida JSONs individuales sin reprocesar torrents

$BasePath = "C:\Users\grau_\Downloads\TelegramNotifier"
$ResultsFolder = Join-Path $BasePath "test\results"
$TempJsonFolder = Join-Path $ResultsFolder "json\json_temp"
$JsonRealesPath = Join-Path $ResultsFolder "json"
$JsonPruebasPath = Join-Path $ResultsFolder "json\pruebas"

# Crear folders si no existen
@($JsonRealesPath, $JsonPruebasPath) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

Write-Host "[INFO] Consolidando JSONs..."

# Buscar en carpeta temporal si existe, sino en results
$searchFolder = if (Test-Path $TempJsonFolder) { $TempJsonFolder } else { $ResultsFolder }

Write-Host "[INFO] Buscando JSONs en: $searchFolder"

# Buscar todos los JSONs individuales
$allJsonFiles = @(Get-ChildItem $searchFolder -Filter "TelegramNotifier_Test_*.json" -ErrorAction SilentlyContinue | 
    Sort-Object Name)

if ($allJsonFiles.Count -eq 0) {
    Write-Host "[ERROR] No JSON files found"
    exit 1
}

Write-Host "[INFO] Encontrados $($allJsonFiles.Count) JSONs para consolidar"

# Inicializar arrays consolidados
$consolidatedTorrents = @()
$allPatterns = @()
$allTags = @()
$plexInfoCount = 0
$falsoNegativeCount = 0

# Procesar cada JSON
foreach ($jsonFile in $allJsonFiles) {
    try {
        $data = Get-Content $jsonFile.FullName -Encoding UTF8 | ConvertFrom-Json
        
        if ($data.torrents -and $data.torrents.Count -gt 0) {
            foreach ($torrent in $data.torrents) {
                $consolidatedTorrents += $torrent
                
                # Agregar patrones unicos
                if ($torrent.patron_detectado -and $torrent.patron_detectado -notin $allPatterns) {
                    $allPatterns += $torrent.patron_detectado
                }
                
                # Agregar tags unicos
                if ($torrent.tag_tecnico_detectado) {
                    $torrent.tag_tecnico_detectado | ForEach-Object {
                        if ($_ -notin $allTags) {
                            $allTags += $_
                        }
                    }
                }
                
                # Contar con plex info
                if ($torrent.plex_responses.Count -gt 0) {
                    $plexInfoCount++
                }
                
                # Contar falsos negativos
                if ($torrent.plex_no_lo_encontro) {
                    $falsoNegativeCount++
                }
            }
        }
    } catch {
        Write-Host "[WARNING] Error en $($jsonFile.Name): $($_.Exception.Message)"
    }
}

if ($consolidatedTorrents.Count -eq 0) {
    Write-Host "[ERROR] No torrents encontrados en los JSONs"
    exit 1
}

Write-Host "[OK] Consolidados $($consolidatedTorrents.Count) torrents"

# Crear metadata consolidada
$consolidatedMetadata = @{
    fecha_ejecucion         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    timestamp_archivo       = Get-Date -Format "yyyyMMdd_HHmmss"
    cantidad_torrents       = $consolidatedTorrents.Count
    test_mode               = $true
    version_script          = "2.0"
    patrones_detectados     = $allPatterns
    tags_tecnicos_totales   = $allTags
    torrents_con_plex_info  = $plexInfoCount
    torrents_falsos_negativos = $falsoNegativeCount
}

# Crear objeto JSON consolidado
$consolidatedJson = @{
    metadata = $consolidatedMetadata
    torrents = $consolidatedTorrents
}

# Detectar si es de prueba
$isPrueba = $consolidatedTorrents | Where-Object { $_.nombre_limpio -match '^test-' } | Measure-Object | Select-Object -ExpandProperty Count
$destJsonPath = if ($isPrueba -gt 0) { $JsonPruebasPath } else { $JsonRealesPath }

# Guardar JSON consolidado en carpeta apropiada
$consolidatedJsonFile = Join-Path $destJsonPath "TelegramNotifier_Test_$($consolidatedMetadata.timestamp_archivo).json"
$consolidatedJson | ConvertTo-Json -Depth 15 | Set-Content $consolidatedJsonFile -Encoding UTF8

$tipo = if ($isPrueba -gt 0) { "PRUEBA" } else { "REAL" }
Write-Host "[OK] JSON consolidado [$tipo]: $consolidatedJsonFile"
Write-Host "[INFO] Total torrents: $($consolidatedTorrents.Count)"
Write-Host "[INFO] Patrones: $($allPatterns -join ', ')"
Write-Host "[INFO] Tags: $($allTags -join ', ')"
Write-Host "[INFO] Con Plex info: $plexInfoCount"
Write-Host "[INFO] Falsos negativos: $falsoNegativeCount"
Write-Host ""

# Limpiar carpeta temporal si se uso
if ($searchFolder -eq $TempJsonFolder) {
    Write-Host "[INFO] Limpiando carpeta temporal..."
    Get-ChildItem $TempJsonFolder -Filter "*.json" | Remove-Item -Force
    Write-Host "[OK] Carpeta temporal limpia"
    Write-Host ""
}

# Generar analisis
Write-Host "[INFO] Generando analisis HTML..."
& (Join-Path $BasePath "test\AnalyzeResults.ps1")

Write-Host ""
Write-Host "[DONE] Consolidacion completada"
