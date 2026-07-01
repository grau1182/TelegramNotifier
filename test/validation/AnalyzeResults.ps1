# ANALYZE RESULTS
# Script que parsea JSON de pruebas y genera reporte HTML

$BasePath = "C:\Users\grau_\Downloads\TelegramNotifier"
$ResultsFolder = Join-Path $BasePath "test\results"
$AnalisisRealesPath = Join-Path $ResultsFolder "analisis"
$AnalisisPruebasPath = Join-Path $ResultsFolder "analisis\pruebas"

# Buscar JSON mas reciente en ambas carpetas
$pruebasJson = Get-ChildItem (Join-Path $ResultsFolder "json\pruebas") -Filter "TelegramNotifier_Test_*.json" -ErrorAction SilentlyContinue | 
    Sort-Object Name -Descending | 
    Select-Object -First 1
    
$realesJson = Get-ChildItem (Join-Path $ResultsFolder "json") -Filter "TelegramNotifier_Test_*.json" -ErrorAction SilentlyContinue | 
    Sort-Object Name -Descending | 
    Select-Object -First 1

# Usar el JSON mas reciente
$latestJson = if ($pruebasJson -and (!$realesJson -or $pruebasJson.CreationTime -gt $realesJson.CreationTime)) { $pruebasJson } else { $realesJson }

if (-not $latestJson) {
    Write-Host "[ERROR] No JSON found"
    exit 1
}

Write-Host "[OK] Analyzing: $($latestJson.Name)"

# Cargar datos
$data = Get-Content $latestJson.FullName -Encoding UTF8 | ConvertFrom-Json
$torrents = $data.torrents
$total = $torrents.Count

if ($total -eq 0) {
    Write-Host "[ERROR] No torrents in JSON"
    exit 1
}

Write-Host "[OK] Processing $total torrents..."

# Calcular metricas
$conPoster = @($torrents | Where-Object { $_.poster_encontrado -eq $true }).Count
$sinPoster = @($torrents | Where-Object { $_.poster_encontrado -eq $false }).Count
$conPlexInfo = @($torrents | Where-Object { $_.plex_responses.Count -gt 0 }).Count
$conErrores = @($torrents | Where-Object { $_.error_general -ne $null }).Count
$avgConf = ($torrents | Measure-Object -Property parse_confidence -Average).Average

# Distribucion de confianza
$confDist = @{
    "0-20" = @($torrents | Where-Object { $_.parse_confidence -lt 20 }).Count
    "20-40" = @($torrents | Where-Object { $_.parse_confidence -ge 20 -and $_.parse_confidence -lt 40 }).Count
    "40-60" = @($torrents | Where-Object { $_.parse_confidence -ge 40 -and $_.parse_confidence -lt 60 }).Count
    "60-80" = @($torrents | Where-Object { $_.parse_confidence -ge 60 -and $_.parse_confidence -lt 80 }).Count
    "80-100" = @($torrents | Where-Object { $_.parse_confidence -ge 80 }).Count
}

# Contar patrones
$patronCount = @{}
foreach ($t in $torrents) {
    $pattern = $t.patron_detectado
    if ($pattern) {
        if ($patronCount[$pattern]) {
            $patronCount[$pattern]++
        } else {
            $patronCount[$pattern] = 1
        }
    }
}

# Torrents con errores
$torrentsConError = @($torrents | Where-Object { $_.error_general -ne $null })

# Detectar si es de prueba
$isPrueba = $torrents | Where-Object { $_.nombre_limpio -match '^test-' } | Measure-Object | Select-Object -ExpandProperty Count
$destFolder = if ($isPrueba -gt 0) { $AnalisisPruebasPath } else { $AnalisisRealesPath }

# Crear folders si no existen
@($AnalisisRealesPath, $AnalisisPruebasPath) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

# Generar HTML
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$htmlFile = Join-Path $destFolder "TelegramNotifier_Analisis_$timestamp.html"

$metric1 = ($conPoster / $total * 100).ToString("F1")
$metric2 = ($sinPoster / $total * 100).ToString("F1")
$metric3 = ($conPlexInfo / $total * 100).ToString("F1")
$metric4 = ($conErrores / $total * 100).ToString("F1")
$metric5 = $avgConf.ToString("F0")

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>TelegramNotifier Analisis</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding: 10px 0; }
        h2 { color: #555; margin-top: 30px; }
        .metrics { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin: 20px 0; }
        .metric { background: white; padding: 15px; border-left: 4px solid #007bff; border-radius: 5px; }
        .metric-label { color: #888; font-size: 12px; }
        .metric-value { font-size: 24px; font-weight: bold; color: #007bff; }
        .chart-container { background: white; padding: 15px; margin: 20px 0; border-radius: 5px; height: 400px; }
        table { width: 100%; border-collapse: collapse; background: white; margin: 15px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #007bff; color: white; }
        tr:hover { background: #f9f9f9; }
        .error-row { background: #fff5f5; }
    </style>
</head>
<body>
    <div class="container">
        <h1>TelegramNotifier Analisis Resultados</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        
        <h2>Metricas Principales</h2>
        <div class="metrics">
            <div class="metric">
                <div class="metric-label">TOTAL TORRENTS</div>
                <div class="metric-value">$total</div>
            </div>
            <div class="metric">
                <div class="metric-label">CON POSTER</div>
                <div class="metric-value">$conPoster</div>
                <div>$metric1 pct</div>
            </div>
            <div class="metric">
                <div class="metric-label">SIN POSTER</div>
                <div class="metric-value">$sinPoster</div>
                <div>$metric2 pct</div>
            </div>
            <div class="metric">
                <div class="metric-label">CON PLEX INFO</div>
                <div class="metric-value">$conPlexInfo</div>
                <div>$metric3 pct</div>
            </div>
            <div class="metric">
                <div class="metric-label">CON ERRORES</div>
                <div class="metric-value">$conErrores</div>
                <div>$metric4 pct</div>
            </div>
            <div class="metric">
                <div class="metric-label">AVG CONFIDENCE</div>
                <div class="metric-value">$metric5 pct</div>
            </div>
        </div>
        
        <h2>Distribucion Confianza</h2>
        <div class="chart-container">
            <canvas id="confChart"></canvas>
        </div>
        
        <h2>Patrones Detectados</h2>
        <table>
            <tr>
                <th>Patron</th>
                <th>Cantidad</th>
                <th>Porcentaje</th>
            </tr>
"@

foreach ($pattern in $patronCount.Keys | Sort-Object) {
    $count = $patronCount[$pattern]
    $pct = ($count / $total * 100).ToString("F1")
    $html += "            <tr><td>$pattern</td><td>$count</td><td>$pct pct</td></tr>"
}

$html += @"
        </table>
        
        <h2>Detalles Torrents</h2>
        <table>
            <tr>
                <th>Nombre Limpio</th>
                <th>Patron</th>
                <th>Confianza</th>
                <th>Tipo</th>
                <th>Poster</th>
                <th>Imagen</th>
                <th>Plex Resp</th>
            </tr>
"@

foreach ($t in $torrents) {
    $poster = if ($t.poster_encontrado) { "Si" } else { "No" }
    $nombre = if ($t.nombre_limpio) { $t.nombre_limpio } else { $t.torrent_name }
    
    # Mostrar imagen del poster si existe
    $posterImage = if ($t.poster_url) { 
        "<img src='$($t.poster_url)' style='height:60px; width:auto; border-radius:4px; box-shadow:0 2px 4px rgba(0,0,0,0.2);' title='$($t.titulo_detectado)'>" 
    } else { 
        "<span style='color:#ccc; font-size:12px;'>-</span>" 
    }
    
    $html += "            <tr><td>$nombre</td><td>$($t.patron_detectado)</td><td>$($t.parse_confidence)pct</td><td>$($t.tipo_detectado)</td><td>$poster</td><td style='text-align:center; padding:5px;'>$posterImage</td><td>$($t.plex_responses.Count)</td></tr>"
}

$html += @"
        </table>
        
        <h2>Torrents Errores</h2>
"@

if ($torrentsConError.Count -gt 0) {
    $html += @"
        <table>
            <tr>
                <th>Torrent</th>
                <th>Ruta</th>
                <th>Error</th>
            </tr>
"@
    foreach ($t in $torrentsConError) {
        $html += "            <tr class='error-row'><td>$($t.torrent_nombre)</td><td>$($t.content_path)</td><td>$($t.error_general)</td></tr>"
    }
    $html += "        </table>"
} else {
    $html += "        <p>No errors found.</p>"
}

$html += @"
    </div>
    
    <script>
        var confCtx = document.getElementById('confChart').getContext('2d');
        new Chart(confCtx, {
            type: 'doughnut',
            data: {
                labels: ['0-20pct', '20-40pct', '40-60pct', '60-80pct', '80-100pct'],
                datasets: [{
                    data: [$($confDist["0-20"]), $($confDist["20-40"]), $($confDist["40-60"]), $($confDist["60-80"]), $($confDist["80-100"])],
                    backgroundColor: ['#dc3545', '#ffc107', '#20c997', '#28a745', '#0d6efd']
                }]
            },
            options: { responsive: true, maintainAspectRatio: false }
        });
    </script>
</body>
</html>
"@

$html | Set-Content $htmlFile -Encoding UTF8
$tipo = if ($isPrueba -gt 0) { "PRUEBA" } else { "REAL" }
Write-Host "[OK] HTML generado [$tipo]: $htmlFile"
Start-Process $htmlFile
