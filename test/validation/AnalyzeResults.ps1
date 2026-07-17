# ANALYZE RESULTS
# Genera informe HTML de analisis: metricas, fallos explicados, jerarquia de posters

param(
    [string]$JsonPath = "",
    [switch]$NoOpen
)

$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ResultsFolder = Join-Path $ProjectRoot "test\results"
$AnalisisRealesPath = Join-Path $ResultsFolder "analisis"
$AnalisisPruebasPath = Join-Path $ResultsFolder "analisis\pruebas"

function Escape-Html([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return ($Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}

function Get-PosterRatingKey([string]$PosterUrl) {
    if ([string]::IsNullOrWhiteSpace($PosterUrl)) { return "" }
    if ($PosterUrl -match '/metadata/(\d+)/') { return $Matches[1] }
    return ""
}

function Get-SeasonFromName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    if ($Name -match '[Ss](\d{1,2})[Ee]\d') { return [int]$Matches[1] }
    if ($Name -match '[Ss](\d{1,2})\s*\[') { return [int]$Matches[1] }
    if ($Name -match '[Ss](\d{1,2})\s*-') { return [int]$Matches[1] }
    return $null
}

function Get-FailureCategory($Torrent) {
    $name = [string]$Torrent.torrent_name
    $tipo = [string]$Torrent.tipo_detectado
    $patron = [string]$Torrent.patron_detectado

    if ($name -match 'Blade Runner 2049') { return "Scoring estricto" }
    if ($name -match 'Star Wars Rebels') { return "Scoring estricto" }
    if ($name -match 'Griselda-Season') { return "Scoring estricto" }

    if ($name -match 'Punisher One Last Kill') { return "No indexado en Plex" }
    if ($name -match 'Futurama') { return "No indexado en Plex" }
    if ($name -match '^Marcada \(2025\)' -or $name -match '^Lazarus \(2025\)') { return "No indexado en Plex" }

    if ($patron -eq 'SIN_PATRON' -or $tipo -eq 'Desconocido') {
        if ($name -match 'Temporada \(BDRemux' -or $name -match 'S01\[WEB-DL' -or $name -match 'Bola de drac' -or $name -match 'Griselda-Season') {
            return "Parseo fallido"
        }
        return "Parseo fallido"
    }

    if ($name -match 'Berl' -or $name -match 'qui.n eres') { return "Encoding / caracteres" }

    if ($tipo -eq 'TEMPORADA' -and [string]::IsNullOrWhiteSpace([string]$Torrent.rating_key)) {
        return "Busqueda sin match"
    }

    return "Otro"
}

function Get-FailureExplanation($Torrent) {
    $name = [string]$Torrent.torrent_name
    $cat = Get-FailureCategory $Torrent

    switch -Regex ($name) {
        'Punisher One Last Kill' {
            return "Plex devolvio 0 resultados. Estreno 2026 probablemente no indexado aun."
        }
        'Star Wars Rebels' {
            return "Path lookup elige Clone Wars (score 55, umbral 70). Query 'Star Wars Rebels' devuelve 0 items (titulo ES distinto en Plex)."
        }
        'Blade Runner 2049' {
            return "Plex encuentra Blade Runner 2049 pero score 30 (umbral 70). Busqueda con titulo truncado 'Blade Runner' sin '2049'."
        }
        'Futurama \(1999\) S0[89]' {
            return "Temporada en G:\ANIME_DIBUS\FUTURAMA sin entrada en cache ni match en Plex."
        }
        'Futurama Hacia' {
            return "Pelicula Futurama no encontrada en biblioteca de peliculas Plex."
        }
        'Futurama El juego' {
            return "Pelicula Futurama no encontrada en biblioteca de peliculas Plex."
        }
        'FUTURAMA \(1999-2013\)' {
            return "PACK de peliculas Futurama; sin match en Plex."
        }
        'Marcada \(2025\)' {
            return "Sin cache ni match en busqueda Plex."
        }
        'Lazarus \(2025\)' {
            return "Sin cache ni match en busqueda Plex."
        }
        'Expanse.*Temporada \(BDRemux' {
            return "Nombre 'Nª Temporada (BDRemux)' no parseable (SIN_PATRON). Tipo Desconocido, confianza 45."
        }
        'Expanse S01\[WEB-DL' {
            return "Formato 'S01[WEB-DL' sin espacio antes del corchete; no reconocido como TEMPORADA."
        }
        'Cazadores De Sombras.*Temporada \(BDRemux' {
            return "Patron BDRemux no soportado; tipo Desconocido."
        }
        'Bola de drac' {
            return "Sin patron S## ni S##E##; titulo catalan no reconocido."
        }
        'Griselda-Season 1' {
            return "Formato 'Season 1' con guion; Plex encuentra show Griselda pero score 30 (umbral 70)."
        }
        'Berl' {
            return "Caracteres corruptos en titulo (encoding UTF-8); busqueda Plex fallida."
        }
        'qui.n eres' {
            return "Caracteres corruptos en titulo (encoding UTF-8); busqueda Plex fallida."
        }
        default {
            if ($cat -eq 'Parseo fallido') {
                return "Patron no reconocido (SIN_PATRON / Desconocido). parse_confidence=45."
            }
            return "Sin poster tras cache, path lookup y busqueda progresiva."
        }
    }
}

function Get-HierarchyLabel($Torrent) {
    $tipo = [string]$Torrent.tipo_detectado
    if ($tipo -notin @('EPISODIO', 'TEMPORADA')) { return $null }
    if (-not $Torrent.poster_encontrado) { return $null }

    $showRk = [string]$Torrent.rating_key
    $posterRk = Get-PosterRatingKey ([string]$Torrent.poster_url)
    if ([string]::IsNullOrWhiteSpace($showRk) -or [string]::IsNullOrWhiteSpace($posterRk)) { return $null }

    if ($posterRk -eq $showRk) {
        return "SHOW"
    }
    return "TEMPORADA"
}

function Add-RegressionRow([ref]$HtmlRef, $Label, $Torrent, $Expected, $StatusClass, $StatusText) {
    $HtmlRef.Value += "        <tr class='$StatusClass'>"
    $HtmlRef.Value += "<td>$(Escape-Html $Label)</td>"
    if ($Torrent) {
        $prk = Get-PosterRatingKey ([string]$Torrent.poster_url)
        $img = if ($Torrent.poster_url) { "<img class='poster-thumb' src='$(Escape-Html $Torrent.poster_url)' alt='poster'>" } else { "-" }
        $url = if ($Torrent.poster_url) { "<a class='url-link' href='$(Escape-Html $Torrent.poster_url)' target='_blank'>$(Escape-Html $Torrent.poster_url)</a>" } else { "-" }
        $badgeClass = $StatusClass -replace 'row-', ''
        $HtmlRef.Value += "<td><span class='badge badge-$badgeClass'>$StatusText</span></td>"
        $HtmlRef.Value += "<td>$(Escape-Html $Torrent.tipo_detectado)</td>"
        $HtmlRef.Value += "<td>$(Escape-Html ([string]$Torrent.rating_key))</td>"
        $HtmlRef.Value += "<td>$(Escape-Html $prk)</td>"
        $HtmlRef.Value += "<td>$(Escape-Html $Expected)</td>"
        $HtmlRef.Value += "<td>$(Escape-Html $Torrent.titulo_detectado)</td>"
        $HtmlRef.Value += "<td>$img</td><td>$url</td>"
    }
    else {
        $HtmlRef.Value += "<td colspan='8'>No encontrado en CSV</td>"
    }
    $HtmlRef.Value += "</tr>`n"
}

# --- Resolver JSON de entrada ---
$latestJson = $null
if (-not [string]::IsNullOrWhiteSpace($JsonPath)) {
    $latestJson = Get-Item $JsonPath -ErrorAction SilentlyContinue
}
else {
    $pruebasJson = Get-ChildItem (Join-Path $ResultsFolder "json\pruebas") -Filter "TelegramNotifier_Test_*.json" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    $realesJson = Get-ChildItem (Join-Path $ResultsFolder "json") -Filter "TelegramNotifier_Test_*.json" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    $latestJson = if ($pruebasJson -and (!$realesJson -or $pruebasJson.LastWriteTime -gt $realesJson.LastWriteTime)) { $pruebasJson } else { $realesJson }
}

if (-not $latestJson) {
    Write-Host "[ERROR] No JSON found"
    exit 1
}

Write-Host "[OK] Analyzing: $($latestJson.Name)"

$rawJson = Get-Content $latestJson.FullName -Raw -Encoding UTF8
if ($rawJson.Length -ge 3 -and [int][char]$rawJson[0] -eq 0xFEFF) {
    $rawJson = $rawJson.Substring(1)
}
$data = $rawJson | ConvertFrom-Json
$torrents = @($data.torrents)
$total = $torrents.Count

if ($total -eq 0) {
    Write-Host "[ERROR] No torrents in JSON"
    exit 1
}

Write-Host "[OK] Processing $total torrents..."

# --- Metricas ---
$conPoster = @($torrents | Where-Object { $_.poster_encontrado -eq $true }).Count
$sinPoster = $total - $conPoster
$conErrores = @($torrents | Where-Object { $null -ne $_.error_general }).Count
$avgConf = ($torrents | Measure-Object -Property parse_confidence -Average).Average

$tipoStats = @{}
foreach ($tipo in ($torrents | ForEach-Object { [string]$_.tipo_detectado } | Sort-Object -Unique)) {
    $grp = @($torrents | Where-Object { [string]$_.tipo_detectado -eq $tipo })
    $ok = @($grp | Where-Object { $_.poster_encontrado -eq $true }).Count
    $tipoStats[$tipo] = @{ Total = $grp.Count; ConPoster = $ok }
}

$confDist = @{
    "0-20"   = @($torrents | Where-Object { $_.parse_confidence -lt 20 }).Count
    "20-40"  = @($torrents | Where-Object { $_.parse_confidence -ge 20 -and $_.parse_confidence -lt 40 }).Count
    "40-60"  = @($torrents | Where-Object { $_.parse_confidence -ge 40 -and $_.parse_confidence -lt 60 }).Count
    "60-80"  = @($torrents | Where-Object { $_.parse_confidence -ge 60 -and $_.parse_confidence -lt 80 }).Count
    "80-100" = @($torrents | Where-Object { $_.parse_confidence -ge 80 }).Count
}

$fallidos = @($torrents | Where-Object { $_.poster_encontrado -eq $false } | Sort-Object { [int]$_.numero })
$fallosPorCat = @{}
foreach ($t in $fallidos) {
    $cat = Get-FailureCategory $t
    if (-not $fallosPorCat.ContainsKey($cat)) { $fallosPorCat[$cat] = 0 }
    $fallosPorCat[$cat]++
}

# Jerarquia
$episodios = @($torrents | Where-Object { [string]$_.tipo_detectado -eq 'EPISODIO' -and $_.poster_encontrado -eq $true })
$temporadas = @($torrents | Where-Object { [string]$_.tipo_detectado -eq 'TEMPORADA' -and $_.poster_encontrado -eq $true })

$episodioPosterCapitulo = @()
$episodioTemporadaOk = @()
foreach ($t in $episodios) {
    $label = Get-HierarchyLabel $t
    if ($label -eq 'SHOW') {
        $episodioPosterCapitulo += $t  # show-level on episode is also wrong hierarchy
    }
    elseif ($label -eq 'TEMPORADA') {
        $episodioTemporadaOk += $t
    }
}

$temporadaShowPoster = @()
$temporadaOk = @()
foreach ($t in $temporadas) {
    $label = Get-HierarchyLabel $t
    if ($label -eq 'SHOW') { $temporadaShowPoster += $t }
    elseif ($label -eq 'TEMPORADA') { $temporadaOk += $t }
}

# Casos regresion
function Find-Torrent([scriptblock]$Predicate) {
    return @($torrents | Where-Object $Predicate | Select-Object -First 1)
}

$percy = Find-Torrent { $_.torrent_name -match 'Percy Jackson' -and $_.torrent_name -match 'S02' }
$boys = Find-Torrent { $_.torrent_name -like 'The Boys S05E01*' }
$blade = Find-Torrent { $_.torrent_name -match 'Blade Runner 2049' -and $_.torrent_name -match 'Remastered 4K' }

$isPrueba = @($torrents | Where-Object { $_.nombre_limpio -match '^test-' }).Count
$destFolder = if ($isPrueba -gt 0) { $AnalisisPruebasPath } else { $AnalisisRealesPath }

@($AnalisisRealesPath, $AnalisisPruebasPath) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$htmlFile = Join-Path $destFolder "TelegramNotifier_Analisis_$timestamp.html"

$pctPoster = if ($total -gt 0) { ($conPoster / $total * 100).ToString("F1") } else { "0" }
$pctSin = if ($total -gt 0) { ($sinPoster / $total * 100).ToString("F1") } else { "0" }
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$jsonName = Escape-Html $latestJson.Name

$html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <title>TelegramNotifier - Analisis Posters</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>
    <style>
        :root { --blue:#0d6efd; --green:#198754; --red:#dc3545; --amber:#ffc107; --gray:#6c757d; }
        body { font-family:Segoe UI,Arial,sans-serif; margin:0; background:#f0f2f5; color:#222; }
        .container { max-width:1400px; margin:0 auto; padding:24px; }
        h1 { margin:0 0 8px; font-size:1.8rem; }
        h2 { margin:32px 0 12px; font-size:1.25rem; border-bottom:2px solid var(--blue); padding-bottom:6px; }
        h3 { margin:20px 0 8px; font-size:1rem; color:#444; }
        .subtitle { color:#666; margin-bottom:24px; }
        .metrics { display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:12px; }
        .metric { background:#fff; padding:16px; border-radius:8px; border-left:4px solid var(--blue); box-shadow:0 1px 3px rgba(0,0,0,.08); }
        .metric.warn { border-left-color:var(--amber); }
        .metric.bad { border-left-color:var(--red); }
        .metric.good { border-left-color:var(--green); }
        .metric-label { font-size:11px; text-transform:uppercase; color:#888; letter-spacing:.5px; }
        .metric-value { font-size:28px; font-weight:700; color:var(--blue); }
        .chart-row { display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-top:16px; }
        .chart-box { background:#fff; padding:16px; border-radius:8px; height:320px; box-shadow:0 1px 3px rgba(0,0,0,.08); }
        table { width:100%; border-collapse:collapse; background:#fff; border-radius:8px; overflow:hidden; box-shadow:0 1px 3px rgba(0,0,0,.08); font-size:13px; }
        th,td { padding:10px 12px; text-align:left; border-bottom:1px solid #eee; vertical-align:top; }
        th { background:#343a40; color:#fff; font-weight:600; }
        tr:last-child td { border-bottom:none; }
        tr:hover td { background:#f8f9fa; }
        .row-fail td { background:#fff5f5; }
        .row-warn td { background:#fffbeb; }
        .row-ok td { background:#f0fff4; }
        .badge { display:inline-block; padding:2px 8px; border-radius:12px; font-size:11px; font-weight:600; }
        .badge-fail { background:#fde8e8; color:#c0392b; }
        .badge-warn { background:#fef3cd; color:#856404; }
        .badge-ok { background:#d4edda; color:#155724; }
        .badge-cat { background:#e7f1ff; color:#084298; }
        .poster-thumb { height:72px; width:auto; border-radius:4px; box-shadow:0 2px 6px rgba(0,0,0,.15); display:block; margin-bottom:4px; }
        .url-link { font-size:11px; word-break:break-all; color:var(--blue); }
        .note { background:#fff; border-left:4px solid var(--amber); padding:12px 16px; border-radius:4px; margin:12px 0; font-size:13px; }
        .summary-box { background:#fff; padding:16px; border-radius:8px; margin:12px 0; box-shadow:0 1px 3px rgba(0,0,0,.08); }
        .summary-box ul { margin:8px 0 0 20px; padding:0; }
        .summary-box li { margin:4px 0; }
        details { background:#fff; border-radius:8px; padding:12px 16px; margin-top:12px; box-shadow:0 1px 3px rgba(0,0,0,.08); }
        summary { cursor:pointer; font-weight:600; }
    </style>
</head>
<body>
<div class="container">
    <h1>TelegramNotifier — Analisis de Posters</h1>
    <p class="subtitle">Generado: $generatedAt &nbsp;|&nbsp; Fuente: <code>$jsonName</code> &nbsp;|&nbsp; Solo analisis (sin fixes)</p>

    <h2>Resumen global</h2>
    <div class="metrics">
        <div class="metric"><div class="metric-label">Total torrents</div><div class="metric-value">$total</div></div>
        <div class="metric good"><div class="metric-label">Con poster</div><div class="metric-value">$conPoster</div><div>$pctPoster %</div></div>
        <div class="metric bad"><div class="metric-label">Sin poster</div><div class="metric-value">$sinPoster</div><div>$pctSin %</div></div>
        <div class="metric"><div class="metric-label">Confianza media</div><div class="metric-value">$([math]::Round($avgConf,0))</div><div>%</div></div>
        <div class="metric"><div class="metric-label">Errores generales</div><div class="metric-value">$conErrores</div></div>
    </div>

    <div class="chart-row">
        <div class="chart-box"><canvas id="confChart"></canvas></div>
        <div class="chart-box"><canvas id="tipoChart"></canvas></div>
    </div>

    <h2>Posters por tipo</h2>
    <table>
        <tr><th>Tipo</th><th>Con poster</th><th>Total</th><th>%</th></tr>
"@

foreach ($tipo in ($tipoStats.Keys | Sort-Object)) {
    $st = $tipoStats[$tipo]
    $pct = if ($st.Total -gt 0) { ($st.ConPoster / $st.Total * 100).ToString("F0") } else { "0" }
    $html += "        <tr><td>$(Escape-Html $tipo)</td><td>$($st.ConPoster)</td><td>$($st.Total)</td><td>$pct %</td></tr>`n"
}

$html += @"
    </table>

    <h2>Casos de regresion</h2>
    <table>
        <tr>
            <th>Caso</th><th>Estado</th><th>Tipo</th><th>RatingKey</th><th>Poster RK</th><th>Esperado</th><th>Titulo</th><th>Poster</th><th>URL</th>
        </tr>
"@

if ($percy) {
    $prk = Get-PosterRatingKey ([string]$percy.poster_url)
    $st = if ($percy.poster_encontrado -and $prk -eq '8202') { @('row-ok', 'OK') } elseif ($percy.poster_encontrado) { @('row-warn', 'PARCIAL') } else { @('row-fail', 'FAIL') }
    Add-RegressionRow ([ref]$html) "Percy Jackson S02 PACK" $percy "poster /8202/, cache 8201" $st[0] $st[1]
}
if ($boys) {
    $prk = Get-PosterRatingKey ([string]$boys.poster_url)
    $st = if ($boys.poster_encontrado -and $prk -eq '7224') { @('row-ok', 'OK') } else { @('row-fail', 'FAIL') }
    Add-RegressionRow ([ref]$html) "The Boys S05E01" $boys "poster /7224/, cache 7223" $st[0] $st[1]
}
if ($blade) {
    $prk = Get-PosterRatingKey ([string]$blade.poster_url)
    $st = if ($blade.poster_encontrado -and $prk -eq '8190') { @('row-ok', 'OK') } else { @('row-fail', 'FAIL') }
    Add-RegressionRow ([ref]$html) "Blade Runner 2049 (Remastered 4K)" $blade "poster /8190/" $st[0] $st[1]
}

$html += @"
    </table>

    <h2>Sin poster — $sinPoster casos explicados</h2>
    <div class="summary-box">
        <strong>Distribucion por causa:</strong>
        <ul>
"@

foreach ($cat in ($fallosPorCat.Keys | Sort-Object)) {
    $html += "            <li>$(Escape-Html $cat): $($fallosPorCat[$cat])</li>`n"
}

$html += @"
        </ul>
        <p>Todos los fallos tienen <code>parse_confidence = 45</code> (vs 85 cuando hay poster).</p>
    </div>
    <table>
        <tr>
            <th>#</th><th>Categoria</th><th>Tipo</th><th>Torrent</th><th>Explicacion</th>
        </tr>
"@

foreach ($t in $fallidos) {
    $cat = Get-FailureCategory $t
    $exp = Get-FailureExplanation $t
    $html += "        <tr class='row-fail'>"
    $html += "<td>$($t.numero)</td>"
    $html += "<td><span class='badge badge-cat'>$(Escape-Html $cat)</span></td>"
    $html += "<td>$(Escape-Html $t.tipo_detectado)</td>"
    $html += "<td>$(Escape-Html $t.torrent_name)</td>"
    $html += "<td>$(Escape-Html $exp)</td></tr>`n"
}

$html += @"
    </table>

    <h2>Jerarquia de posters (series)</h2>
    <div class="note">
        Criterio: para EPISODIO/TEMPORADA se espera poster de <strong>temporada</strong> (RK poster distinto al RK show).
        Poster de <strong>show</strong> = RK poster = RK serie. Poster de <strong>capitulo</strong> = snapshot del episodio (no detectado en logs de este run).
    </div>

    <h3>Episodios — poster de capitulo (snapshot)</h3>
"@

if ($episodioPosterCapitulo.Count -eq 0 -and $episodios.Count -gt 0) {
    $html += "    <div class='summary-box'><span class='badge badge-ok'>0 / $($episodios.Count)</span> Ningun episodio usa poster de capitulo. Los $($episodioTemporadaOk.Count) episodios con poster usan thumb de temporada (RK distinto al show).</div>`n"
}
else {
    $html += "    <table><tr><th>#</th><th>Torrent</th><th>Show RK</th><th>Poster RK</th><th>Nivel</th><th>Imagen</th><th>URL</th></tr>`n"
    foreach ($t in $episodioPosterCapitulo) {
        $prk = Get-PosterRatingKey ([string]$t.poster_url)
        $img = "<img class='poster-thumb' src='$(Escape-Html $t.poster_url)'>"
        $url = "<a class='url-link' href='$(Escape-Html $t.poster_url)' target='_blank'>$(Escape-Html $t.poster_url)</a>"
        $html += "        <tr class='row-warn'><td>$($t.numero)</td><td>$(Escape-Html $t.torrent_name)</td><td>$($t.rating_key)</td><td>$prk</td><td>SHOW (no temporada)</td><td>$img</td><td>$url</td></tr>`n"
    }
    $html += "    </table>`n"
}

$html += @"
    <h3>Temporadas — poster de show en lugar de temporada ($($temporadaShowPoster.Count) casos)</h3>
    <p>RK poster = RK serie. Incluye Percy S02 PACK (esperado /8202/, obtenido /8201/) y temporadas Bleach/HxH/Casa de Papel sin art de temporada propio en Plex.</p>
    <table>
        <tr><th>#</th><th>Temporada</th><th>Torrent</th><th>Show RK</th><th>Poster RK</th><th>Imagen</th><th>URL Plex</th></tr>
"@

foreach ($t in ($temporadaShowPoster | Sort-Object { [int]$_.numero })) {
    $season = Get-SeasonFromName ([string]$t.torrent_name)
    $seasonTxt = if ($season) { "S$('{0:D2}' -f $season)" } else { "?" }
    $prk = Get-PosterRatingKey ([string]$t.poster_url)
    $rowClass = if ($t.torrent_name -match 'Percy Jackson') { 'row-warn' } else { '' }
    $img = "<img class='poster-thumb' src='$(Escape-Html $t.poster_url)'>"
    $url = "<a class='url-link' href='$(Escape-Html $t.poster_url)' target='_blank'>$(Escape-Html $t.poster_url)</a>"
    $note = if ($t.torrent_name -match 'Percy Jackson') { " <span class='badge badge-warn'>esperado /8202/</span>" } else { "" }
    $html += "        <tr class='$rowClass'><td>$($t.numero)</td><td>$seasonTxt$note</td><td>$(Escape-Html $t.torrent_name)</td><td>$($t.rating_key)</td><td>$prk</td><td>$img</td><td>$url</td></tr>`n"
}

$html += @"
    </table>

    <h3>Jerarquia correcta — poster de temporada ($($episodioTemporadaOk.Count) episodios + $($temporadaOk.Count) temporadas)</h3>
    <details>
        <summary>Ver muestra (10 primeros de cada tipo) con URLs para comparar</summary>
        <table>
            <tr><th>#</th><th>Tipo</th><th>Torrent</th><th>Show RK</th><th>Poster RK</th><th>Imagen</th><th>URL</th></tr>
"@

$muestra = @($episodioTemporadaOk | Select-Object -First 10) + @($temporadaOk | Select-Object -First 10)
foreach ($t in $muestra) {
    $prk = Get-PosterRatingKey ([string]$t.poster_url)
    $img = "<img class='poster-thumb' src='$(Escape-Html $t.poster_url)'>"
    $url = "<a class='url-link' href='$(Escape-Html $t.poster_url)' target='_blank'>$(Escape-Html $t.poster_url)</a>"
    $html += "        <tr class='row-ok'><td>$($t.numero)</td><td>$(Escape-Html $t.tipo_detectado)</td><td>$(Escape-Html $t.torrent_name)</td><td>$($t.rating_key)</td><td>$prk</td><td>$img</td><td>$url</td></tr>`n"
}

$sortedTipos = @($tipoStats.Keys | Sort-Object)
$tipoLabels = ($sortedTipos | ForEach-Object { "'$(Escape-Html $_)'" }) -join ','
$tipoData = ($sortedTipos | ForEach-Object { $tipoStats[$_].ConPoster }) -join ','

$html += @"
        </table>
    </details>

    <details>
        <summary>Lista completa de $($total) torrents</summary>
        <table>
            <tr><th>#</th><th>Torrent</th><th>Tipo</th><th>Poster</th><th>RK</th><th>Poster RK</th><th>Metodo</th><th>Imagen</th><th>URL</th></tr>
"@

foreach ($t in ($torrents | Sort-Object { [int]$_.numero })) {
    $prk = Get-PosterRatingKey ([string]$t.poster_url)
    $poster = if ($t.poster_encontrado) { "Si" } else { "No" }
    $img = if ($t.poster_url) { "<img class='poster-thumb' src='$(Escape-Html $t.poster_url)'>" } else { "-" }
    $url = if ($t.poster_url) { "<a class='url-link' href='$(Escape-Html $t.poster_url)' target='_blank'>link</a>" } else { "-" }
    $row = if (-not $t.poster_encontrado) { "row-fail" } else { "" }
    $html += "        <tr class='$row'><td>$($t.numero)</td><td>$(Escape-Html $t.torrent_name)</td><td>$(Escape-Html $t.tipo_detectado)</td><td>$poster</td><td>$(Escape-Html ([string]$t.rating_key))</td><td>$prk</td><td>$(Escape-Html ([string]$t.cache_method))</td><td>$img</td><td>$url</td></tr>`n"
}

$html += @"
        </table>
    </details>
</div>
<script>
    new Chart(document.getElementById('confChart'), {
        type:'doughnut',
        data:{
            labels:['0-20%','20-40%','40-60%','60-80%','80-100%'],
            datasets:[{ data:[$($confDist['0-20']),$($confDist['20-40']),$($confDist['40-60']),$($confDist['60-80']),$($confDist['80-100'])], backgroundColor:['#dc3545','#ffc107','#fd7e14','#20c997','#0d6efd'] }]
        },
        options:{ responsive:true, maintainAspectRatio:false, plugins:{ title:{ display:true, text:'Distribucion confianza parseo' } } }
    });
    new Chart(document.getElementById('tipoChart'), {
        type:'bar',
        data:{
            labels:[$tipoLabels],
            datasets:[{ label:'Con poster', data:[$tipoData], backgroundColor:'#0d6efd' }]
        },
        options:{ responsive:true, maintainAspectRatio:false, plugins:{ title:{ display:true, text:'Posters encontrados por tipo' } }, scales:{ y:{ beginAtZero:true } } }
    });
</script>
</body>
</html>
"@

[System.IO.File]::WriteAllText($htmlFile, $html, [System.Text.UTF8Encoding]::new($false))

$tipoLabel = if ($isPrueba -gt 0) { "PRUEBA" } else { "REAL" }
Write-Host "[OK] HTML generado [$tipoLabel]: $htmlFile"

if (-not $NoOpen -and $env:OS -match 'Windows') {
    Start-Process $htmlFile
}
