# ==================================================
# VALIDATE PLEX IMPROVEMENTS - Test 121 falsos negativos previos
# ==================================================

param(
    [string]$PreviousJsonFile = "C:\Users\grau_\Downloads\TelegramNotifier\test\results\json\TelegramNotifier_Test_20260701_104010.json"
)

Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "   VALIDACIÓN: Mejoras Get-PlexPoster v3.0-IMPROVED"
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host ""

if (-not (Test-Path $PreviousJsonFile)) {
    Write-Host "❌ ERROR: Archivo JSON anterior no encontrado"
    exit 1
}

# Cargar JSON anterior
$previousData = Get-Content $PreviousJsonFile -Raw | ConvertFrom-Json
$totalTorrents = $previousData.torrents.Count
$falseNegatives = @($previousData.torrents | Where-Object { $_.plex_no_lo_encontro -eq $true })
$falseNegativeCount = $falseNegatives.Count

Write-Host "📊 ESTADÍSTICAS PREVIAS (Baseline v2.0)"
Write-Host "   • Total torrents: $totalTorrents"
Write-Host "   • Falsos negativos detectados: $falseNegativeCount ($([Math]::Round(($falseNegativeCount / $totalTorrents) * 100, 1))%)"
Write-Host "   • Cobertura: $([Math]::Round((($totalTorrents - $falseNegativeCount) / $totalTorrents) * 100, 1))%"
Write-Host ""

Write-Host "🔍 TOP 15 FALSOS NEGATIVOS A VALIDAR:"
Write-Host "─────────────────────────────────────────────────────────────────"

$topFalseNegatives = $falseNegatives | Select-Object -First 15

$i = 1
foreach ($torrent in $topFalseNegatives) {
    $tipo = $torrent.tipo_detectado
    $titulo = $torrent.titulo_final
    $encoding = if ($torrent.nombre_limpio -match 'Ã') { "🔴 ENCODING CORRUPTO" } else { "✓ OK" }
    
    Write-Host "  $i. [$tipo] $titulo $encoding"
    $i++
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""

Write-Host "✅ INSTRUCCIONES DE VALIDACIÓN:"
Write-Host ""
Write-Host "1. Ejecutar versión mejorada:"
Write-Host "   PS> & 'test\generate_test_data_improved.ps1'"
Write-Host ""
Write-Host "2. Comparar resultados:"
Write-Host "   • Abrir JSON NUEVO en results/json/"
Write-Host "   • Contar torrent.poster_encontrado = true"
Write-Host "   • Comparar con baseline: $([Math]::Round((($totalTorrents - $falseNegativeCount) / $totalTorrents) * 100, 1))%"
Write-Host ""
Write-Host "3. Validar caché:"
Write-Host "   • Revisar plex_cache.json tamaño"
Write-Host "   • Verificar search_metrics en JSON"
Write-Host ""
Write-Host "4. Métricas esperadas:"
Write-Host "   • Target cobertura: ≥75% (+25% improvement)"
Write-Host "   • Target velocidad: -80% tiempo (30 seg vs 3 min actual)"
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════"
