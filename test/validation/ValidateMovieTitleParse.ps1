# ==================================================
# ValidateMovieTitleParse.ps1
# Valida parseo de título/año y resolución de caché para películas
# ==================================================

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$LibPath = Join-Path $ProjectRoot "core\lib"

. (Join-Path $LibPath "logger.ps1")
. (Join-Path $LibPath "utilities.ps1")
. (Join-Path $LibPath "cache-manager.ps1")

$parseCases = @(
    @{
        torrentName = "Blade Runner 2049 (2017) [2160p UHD BluRay REMUX HEVC TrueHD 7.1].mkv"
        title       = "Blade Runner 2049"
        year        = "2017"
    },
    @{
        torrentName = "Minority Report (2002) [1080p BluRay x264].mkv"
        title       = "Minority Report"
        year        = "2002"
    },
    @{
        torrentName = "2010 The Year We Make Contact (1984) [1080p].mkv"
        title       = "2010 The Year We Make Contact"
        year        = "1984"
    }
)

Write-Host "Validacion parseo de peliculas" -ForegroundColor Cyan
$passed = 0
$failed = 0

foreach ($case in $parseCases) {
    Write-Host ""
    Write-Host "Caso: $($case.torrentName)" -ForegroundColor Yellow

    $parsed = Get-MovieTitleAndYear -OriginalName $case.torrentName
    Write-Host "  Parseado: '$($parsed.Title)' ($($parsed.Year)) Found=$($parsed.Found)"

    if (-not $parsed.Found) {
        Write-Host "  FAIL: no se detecto titulo/anio" -ForegroundColor Red
        $failed++
        continue
    }

    if ($parsed.Title -ne $case.title -or [string]$parsed.Year -ne $case.year) {
        Write-Host "  FAIL: esperado '$($case.title)' ($($case.year))" -ForegroundColor Red
        $failed++
        continue
    }

    $variants = Split-TitleVariants -Title $parsed.Title
    Write-Host "  Variantes: $($variants -join ' | ')"

    if ($case.title -eq "Blade Runner 2049" -and ($variants -contains "Blade")) {
        Write-Host "  FAIL: variante 'Blade' no deberia generarse" -ForegroundColor Red
        $failed++
        continue
    }

    Write-Host "  PASS" -ForegroundColor Green
    $passed++
}

Write-Host ""
Write-Host "Validacion cache Blade Runner 2049 vs Blade" -ForegroundColor Cyan

$script:ProjectRoot = $ProjectRoot
Initialize-PlexCache -SkipDelay $true -ProjectRoot $ProjectRoot | Out-Null

$meta = @{
    Title = "Blade Runner 2049"
    Year  = "2017"
    Type  = "PELICULA"
}

$resolvedKey = Resolve-RatingKey -Title $meta.Title -DetectedMetadata $meta -ProjectRoot $ProjectRoot
Write-Host "  Resolve-RatingKey: '$resolvedKey' (esperado vacio)"

if (-not [string]::IsNullOrEmpty($resolvedKey)) {
    Write-Host "  FAIL: Resolve-RatingKey no deberia devolver ratingKey por fuzzy" -ForegroundColor Red
    $failed++
}
else {
    Write-Host "  PASS Resolve-RatingKey" -ForegroundColor Green
    $passed++
}

$cacheResult = Get-PosterByCache -Title $meta.Title -RatingKey $resolvedKey -DetectedMetadata $meta
Write-Host "  Get-PosterByCache: found=$($cacheResult.found) method=$($cacheResult.method) ratingKey=$($cacheResult.ratingKey)"

if ($cacheResult.found -and [string]$cacheResult.ratingKey -eq "4424") {
    Write-Host "  FAIL: no deberia resolver poster de Blade (4424)" -ForegroundColor Red
    $failed++
}
else {
    Write-Host "  PASS Get-PosterByCache" -ForegroundColor Green
    $passed++
}

$fuzzyScore = Get-FuzzyMatchScore "bladerunner2049" "blade"
Write-Host "  Fuzzy bladerunner2049 vs blade: $fuzzyScore (esperado < 90)"

if ($fuzzyScore -ge 90) {
    Write-Host "  FAIL: bonus Contains demasiado generoso" -ForegroundColor Red
    $failed++
}
else {
    Write-Host "  PASS Get-FuzzyMatchScore" -ForegroundColor Green
    $passed++
}

Write-Host ""
Write-Host "Resultado: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) { exit 1 }
