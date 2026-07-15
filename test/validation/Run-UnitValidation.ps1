# ==================================================
# Run-UnitValidation.ps1
# Ejecuta todos los tests unitarios de validación
# ==================================================

$ErrorActionPreference = "Stop"
$ValidationPath = $PSScriptRoot

$scripts = @(
    @{
        Name = "Parseo películas + caché"
        File = "ValidateMovieTitleParse.ps1"
    },
    @{
        Name = "Variantes y scoring (Kingsman)"
        File = "ValidateKingsmanSearch.ps1"
    }
)

Write-Host "Validacion unitaria - suite completa" -ForegroundColor Cyan
Write-Host ""

$totalPassed = 0
$totalFailed = 0
$failedSuites = @()

foreach ($suite in $scripts) {
    $scriptPath = Join-Path $ValidationPath $suite.File

    if (-not (Test-Path $scriptPath)) {
        Write-Host "FAIL: no encontrado $($suite.File)" -ForegroundColor Red
        $totalFailed++
        $failedSuites += $suite.Name
        continue
    }

    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "Suite: $($suite.Name)" -ForegroundColor Yellow
    Write-Host "Script: $($suite.File)" -ForegroundColor DarkGray
    Write-Host ""

    & $scriptPath
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        $totalFailed++
        $failedSuites += $suite.Name
        Write-Host ""
        Write-Host "Suite FALLIDA: $($suite.Name)" -ForegroundColor Red
    }
    else {
        $totalPassed++
        Write-Host ""
        Write-Host "Suite OK: $($suite.Name)" -ForegroundColor Green
    }

    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Resumen: $totalPassed suite(s) OK, $totalFailed suite(s) fallidas" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })

if ($failedSuites.Count -gt 0) {
    Write-Host "Fallidas: $($failedSuites -join ', ')" -ForegroundColor Red
    exit 1
}

exit 0
