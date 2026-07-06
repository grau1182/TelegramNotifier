# ==================================================
# ValidateKingsmanSearch.ps1
# Valida variantes de título y scoring para casos Kingsman
# ==================================================

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$LibPath = Join-Path $ProjectRoot "core\lib"

. (Join-Path $LibPath "logger.ps1")
. (Join-Path $LibPath "utilities.ps1")
. (Join-Path $LibPath "cache-manager.ps1")
. (Join-Path $LibPath "plex-functions.ps1") -PlexUrl "http://127.0.0.1:32400" -PlexToken "test"

$cases = @(
    @{
        torrentTitle = "Kingsman, El Servicio Secreto"
        plexTitle    = "Kingsman: The Secret Service"
        year         = "2014"
    },
    @{
        torrentTitle = "Kingsman, El Circulo De Oro"
        plexTitle    = "Kingsman: The Golden Circle"
        year         = "2017"
    },
    @{
        torrentTitle = "The King's Man, La Primera Mision"
        plexTitle    = "The King's Man"
        year         = "2021"
    }
)

Write-Host "Validacion Kingsman - variantes y scoring" -ForegroundColor Cyan
$passed = 0
$failed = 0

foreach ($case in $cases) {
    Write-Host ""
    Write-Host "Caso: $($case.torrentTitle)" -ForegroundColor Yellow

    $variants = Split-TitleVariants -Title $case.torrentTitle
    Write-Host "  Variantes: $($variants -join ' | ')"

    if ($case.torrentTitle -like "Kingsman*" -and $variants -notcontains "Kingsman") {
        Write-Host "  FAIL: falta variante 'Kingsman'" -ForegroundColor Red
        $failed++
        continue
    }

    if ($case.torrentTitle -match '^([^,]+),') {
        $expectedRoot = $Matches[1].Trim()
        if ($variants -notcontains $expectedRoot) {
            Write-Host "  FAIL: falta variante raiz '$expectedRoot'" -ForegroundColor Red
            $failed++
            continue
        }
    }

    $meta = @{
        Title = $case.torrentTitle
        Year  = $case.year
        Type  = "PELICULA"
    }
    $plexItem = @{
        title = $case.plexTitle
        year  = $case.year
    }

    $score = Get-PlexMatchScore -PlexItem $plexItem -DetectedMetadata $meta -ContentPath ""
    $acceptable = Test-PlexItemAcceptable -Score $score -PlexItem $plexItem -DetectedMetadata $meta

    Write-Host "  Plex title: $($case.plexTitle)"
    Write-Host "  Score: $score | Aceptable: $acceptable"

    if ($acceptable) {
        Write-Host "  PASS" -ForegroundColor Green
        $passed++
    }
    else {
        Write-Host "  FAIL: score insuficiente para aceptar match" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Resultado: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) { exit 1 }
