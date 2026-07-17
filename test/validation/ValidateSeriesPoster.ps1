# ==================================================
# ValidateSeriesPoster.ps1
# Valida jerarquía de poster, scoring series y caché por show
# Usa test/lib (no requiere Plex en red para la mayoría de casos)
# ==================================================

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$TestLibPath = Join-Path $ProjectRoot "test\lib"

function Write-StubLog { param([string]$Text, [string]$Level = "INFO") }

$PlexUrl = "http://127.0.0.1:32400"
$PlexToken = "test-token"

. (Join-Path $TestLibPath "utilities.ps1")
. (Join-Path $TestLibPath "cache-manager.ps1")
. (Join-Path $TestLibPath "plex-functions.ps1")

$passed = 0
$failed = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if ($Condition) {
        Write-Host "  PASS: $Message" -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host "  FAIL: $Message" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host "Validacion series - poster jerarquico y scoring" -ForegroundColor Cyan
Write-Host ""

# --- Mock metadata basado en Plex real (Percy 8209, Boys 7225, Blade 8190) ---

$percyEpisode = @{
    type                  = "episode"
    ratingKey             = "8209"
    title                 = "Palomas demoniacas atacan"
    grandparentTitle      = "Percy Jackson y los dioses del Olimpo"
    parentTitle           = "El mar de los monstruos"
    parentRatingKey       = "8202"
    grandparentRatingKey  = "8201"
    parentIndex           = 2
    index                 = 2
    thumb                 = "/library/metadata/8209/thumb/1784246735"
    parentThumb           = "/library/metadata/8202/thumb/1784218999"
    grandparentThumb      = "/library/metadata/8201/thumb/1784218998"
    Image                 = @(
        @{ type = "coverPoster"; url = "/library/metadata/8201/thumb/1784218998" }
        @{ type = "snapshot"; url = "/library/metadata/8209/thumb/1784246735" }
    )
}

$boysEpisode = @{
    type                  = "episode"
    ratingKey             = "7225"
    title                 = "Cuarenta centimetros de pura dinamita"
    grandparentTitle      = "The Boys"
    parentTitle           = "Temporada 5"
    parentRatingKey       = "7224"
    grandparentRatingKey  = "7223"
    parentIndex           = 5
    index                 = 1
    thumb                 = "/library/metadata/7225/thumb/1779673004"
    parentThumb           = "/library/metadata/7224/thumb/1775871072"
    grandparentThumb      = "/library/metadata/7223/thumb/1782441161"
    Image                 = @(
        @{ type = "coverPoster"; url = "/library/metadata/7223/thumb/1782441161" }
        @{ type = "snapshot"; url = "/library/metadata/7225/thumb/1779673004" }
    )
}

$bladeMovie = @{
    type      = "movie"
    ratingKey = "8190"
    title     = "Blade Runner 2049"
    thumb     = "/library/metadata/8190/thumb/1784074249"
    year      = "2017"
}

$percyShow = @{
    type  = "show"
    ratingKey = "8201"
    title = "Percy Jackson y los dioses del Olimpo"
    year  = "2023"
    thumb = "/library/metadata/8201/thumb/1784218998"
}

Write-Host "1. Jerarquia poster episodio Percy (8209)" -ForegroundColor Yellow
$percyPoster = Get-PlexPosterFromItem -Item $percyEpisode -DetectedMetadata @{ Type = "TEMPORADA"; Season = 2 }
Assert-True ($percyPoster -match "/8202/") "parentThumb temporada 8202"
Assert-True ($percyPoster -notmatch "/8209/") "no usa snapshot episodio 8209"

Write-Host ""
Write-Host "2. Jerarquia poster episodio The Boys (7225)" -ForegroundColor Yellow
$boysPoster = Get-PlexPosterFromItem -Item $boysEpisode -DetectedMetadata @{ Type = "EPISODIO"; Season = 5; Episode = 1 }
Assert-True ($boysPoster -match "/7224/") "parentThumb temporada 7224"
Assert-True ($boysPoster -notmatch "/7225/") "no usa snapshot episodio 7225"

Write-Host ""
Write-Host "3. Poster pelicula Blade Runner (8190)" -ForegroundColor Yellow
$moviePoster = Get-PlexPosterFromItem -Item $bladeMovie -DetectedMetadata @{ Type = "PELICULA" }
Assert-True ($moviePoster -match "/8190/") "thumb pelicula 8190"

Write-Host ""
Write-Host "4. Caché por grandparentRatingKey (serie)" -ForegroundColor Yellow
$cacheEntry = Get-PlexCacheEntryFromItem -Item $percyEpisode -DetectedMetadata @{ Type = "TEMPORADA" }
Assert-True ($cacheEntry.RatingKey -eq "8201") "ratingKey caché = show 8201"
Assert-True ($cacheEntry.Type -eq "SERIE") "tipo caché SERIE"

Write-Host ""
Write-Host "5. Scoring TEMPORADA Percy vs show (query 1 del log)" -ForegroundColor Yellow
$percyMeta = @{
    Title  = "Percy Jackson Y Los Dioses Del Olimpo"
    Season = 2
    Type   = "TEMPORADA"
}
$showScore = Get-PlexMatchScore -PlexItem $percyShow -DetectedMetadata $percyMeta -ContentPath "G:\SERIES\PERCY_JACKSON_Y_LOS_DIOSES_DEL_OLIMPO"
$showOk = Test-PlexItemAcceptable -Score $showScore -PlexItem $percyShow -DetectedMetadata $percyMeta
Write-Host "  Score show: $showScore | Aceptable: $showOk"
Assert-True ($showOk) "show 8201 aceptable sin (2023) en titulo"

Write-Host ""
Write-Host "6. Scoring TEMPORADA: episodio penalizado vs show" -ForegroundColor Yellow
$episodePath = "G:\SERIES\PERCY_JACKSON_Y_LOS_DIOSES_DEL_OLIMPO\Percy Jackson S02E02.mkv"
$percyEpisodeWithPath = @{
    type                 = "episode"
    ratingKey            = "8209"
    title                = "Palomas demoniacas atacan"
    grandparentTitle     = "Percy Jackson y los dioses del Olimpo"
    parentIndex          = 2
    index                = 2
    grandparentRatingKey = "8201"
    Media                = @{ Part = @{ file = $episodePath } }
}
$epScore = Get-PlexMatchScore -PlexItem $percyEpisodeWithPath -DetectedMetadata $percyMeta -ContentPath "G:\SERIES\PERCY_JACKSON_Y_LOS_DIOSES_DEL_OLIMPO"
Write-Host "  Score episodio (path folder): $epScore | Score show: $showScore"
Assert-True ($showScore -gt $epScore) "show gana sobre episodio en PACK temporada"

Write-Host ""
Write-Host "7. Parseo TEMPORADA sin año" -ForegroundColor Yellow
$searchTitle = Get-SearchTitle -Title "Percy Jackson Y Los Dioses Del Olimpo (2023)" -Type "TEMPORADA"
Assert-True ($searchTitle -notmatch "\(2023\)") "Get-SearchTitle quita (2023)"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Resumen: $passed PASS, $failed FAIL" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -gt 0) {
    exit 1
}

exit 0
