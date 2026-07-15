# ==================================================
# PLEX-FUNCTIONS.PS1 - Funciones de Búsqueda Plex
# ==================================================

$script:PlexScanPollSeconds = 5
$script:PlexScanPollMaxAttempts = 12
$script:SkipPlexScan = $false
$script:PlexMoviePathPrefix = "G:\PELIS"
$script:PlexSeriesPathPrefix = "G:\SERIES"

function Normalize-PlexQuery {
    param([string]$Text)
    return $Text.ToLower().Replace(" ", "-").Replace(".", "").Replace("ñ", "n").Replace("á", "a").Replace("é", "e").Replace("í", "i").Replace("ó", "o").Replace("ú", "u").Trim('-')
}

function Normalize-PlexTitle {
    param([string]$Title)
    return $Title.ToLower().Replace(" ", "-").Replace(".", "").Replace("ñ", "n").Replace("á", "a").Replace("é", "e").Replace("í", "i").Replace("ó", "o").Replace("ú", "u").Trim('-')
}

function Normalize-FilePath {
    param([string]$Path)
    return $Path.ToLower().Trim().Replace("/", "\")
}

function Get-PlexItemFilePath {
    param($Item)
    if ($Item.Media.Part.file) { return Normalize-FilePath $Item.Media.Part.file }
    return $null
}

function Get-PlexPosterFromItem {
    param($Item)
    if ($Item.thumb) {
        return $PlexUrl.TrimEnd('/') + $Item.thumb + "?X-Plex-Token=$PlexToken"
    }
    if ($Item.art) {
        return $PlexUrl.TrimEnd('/') + $Item.art + "?X-Plex-Token=$PlexToken"
    }
    return $null
}

function Get-PlexMatchScore {
    param(
        $PlexItem,
        [hashtable]$DetectedMetadata,
        [string]$ContentPath
    )
    $Score = 0

    $NormalizedContentPath = Normalize-FilePath $ContentPath
    $PlexFilePath = Get-PlexItemFilePath $PlexItem

    # Coincidencia de ruta
    if ($PlexFilePath -eq $NormalizedContentPath) {
        $Score += 100
    }
    elseif ($PlexFilePath -and $NormalizedContentPath -and $PlexFilePath.StartsWith($NormalizedContentPath + "\")) {
        $Score += 70
    }
    elseif ($PlexFilePath -and $NormalizedContentPath -and $NormalizedContentPath.StartsWith($PlexFilePath + "\")) {
        $Score += 70
    }

    $NormalizedPlexTitle = Normalize-PlexTitle $PlexItem.title
    $NormalizedDetectedTitle = Normalize-PlexTitle $DetectedMetadata.Title

    # Coincidencia de título
    if ($NormalizedPlexTitle -eq $NormalizedDetectedTitle) {
        $Score += 50
    }
    elseif ($NormalizedPlexTitle.Contains($NormalizedDetectedTitle) -or $NormalizedDetectedTitle.Contains($NormalizedPlexTitle)) {
        $Score += 30
    }
    else {
        $detectedRoot = ($DetectedMetadata.Title -split '[,:]')[0].Trim().ToLower()
        $plexRoot = ($PlexItem.title -split '[,:]')[0].Trim().ToLower()
        if (-not [string]::IsNullOrWhiteSpace($detectedRoot) -and $detectedRoot -eq $plexRoot) {
            $Score += 35
        }

        $fuzzyScore = Get-FuzzyMatchScore (Normalize-CacheKey $DetectedMetadata.Title) (Normalize-CacheKey $PlexItem.title)
        if ($fuzzyScore -ge 85) {
            $Score += 25
        }
        elseif ($fuzzyScore -ge 60) {
            $Score += 15
        }
    }

    # Coincidencia de año (para películas)
    if ($DetectedMetadata.Type -eq "PELICULA" -and $PlexItem.year -eq $DetectedMetadata.Year) {
        $Score += 40
    }

    # Coincidencia de temporada/episodio
    if ($DetectedMetadata.Type -eq "EPISODIO") {
        if ($PlexItem.parentIndex -eq $DetectedMetadata.Season -and $PlexItem.index -eq $DetectedMetadata.Episode) {
            $Score += 60
        }
    }

    if ($DetectedMetadata.Type -eq "TEMPORADA" -and $PlexItem.index -eq $DetectedMetadata.Season) {
        $Score += 50
    }

    return $Score
}

function Test-PlexItemAcceptable {
    param(
        [int]$Score,
        $PlexItem,
        [hashtable]$DetectedMetadata
    )

    if ($Score -ge 100) { return $true }
    if ($Score -ge 90) { return $true }
    if ($Score -ge 70) { return $true }

    if ($Score -ge 40 -and $DetectedMetadata.Year -and $PlexItem.year -eq $DetectedMetadata.Year) {
        $fuzzyScore = Get-FuzzyMatchScore (Normalize-CacheKey $DetectedMetadata.Title) (Normalize-CacheKey $PlexItem.title)
        if (($Score + $fuzzyScore) -ge 60) {
            return $true
        }
    }

    return $false
}

function Get-PlexSearchQueries {
    param([string]$Title)
    return Split-TitleVariants -Title $Title
}

function Get-PlexLibrarySections {
    try {
        $url = "$PlexUrl/library/sections?X-Plex-Token=$PlexToken"
        [xml]$result = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        $sections = @()

        foreach ($directory in @($result.MediaContainer.Directory)) {
            $paths = @()
            foreach ($location in @($directory.Location)) {
                if ($location.path) {
                    $paths += (Normalize-FilePath $location.path)
                }
            }

            $sections += @{
                key   = [string]$directory.key
                title = [string]$directory.title
                type  = [string]$directory.type
                paths = $paths
            }
        }

        return $sections
    }
    catch {
        Write-Log "Error obteniendo secciones Plex: $($_.Exception.Message)" -Level "WARNING"
        return @()
    }
}

function Resolve-PlexSectionForPath {
    param(
        [string]$ContentPath,
        [string]$ContentType = "PELICULA"
    )

    if ([string]::IsNullOrWhiteSpace($ContentPath)) {
        return $null
    }

    $normalizedPath = Normalize-FilePath $ContentPath
    $sections = Get-PlexLibrarySections
    if ($sections.Count -eq 0) {
        return $null
    }

    $fallbackPrefix = if ($ContentType -in @("EPISODIO", "TEMPORADA", "SERIE")) {
        Normalize-FilePath $script:PlexSeriesPathPrefix
    }
    else {
        Normalize-FilePath $script:PlexMoviePathPrefix
    }

    $bestMatch = $null
    $bestPrefixLength = -1

    foreach ($section in $sections) {
        foreach ($sectionPath in @($section.paths)) {
            if ([string]::IsNullOrWhiteSpace($sectionPath)) { continue }

            if ($normalizedPath.StartsWith($sectionPath.TrimEnd('\') + '\') -or $normalizedPath -eq $sectionPath.TrimEnd('\')) {
                if ($sectionPath.Length -gt $bestPrefixLength) {
                    $bestPrefixLength = $sectionPath.Length
                    $bestMatch = $section
                }
            }
        }
    }

    if ($bestMatch) {
        return $bestMatch
    }

    if (-not [string]::IsNullOrWhiteSpace($fallbackPrefix) -and $normalizedPath.StartsWith($fallbackPrefix.TrimEnd('\') + '\')) {
        $expectedType = if ($ContentType -in @("EPISODIO", "TEMPORADA", "SERIE")) { "show" } else { "movie" }
        $typeMatch = $sections | Where-Object { $_.type -eq $expectedType } | Select-Object -First 1
        if ($typeMatch) {
            return $typeMatch
        }
    }

    return $null
}

function Invoke-PlexPartialScan {
    param(
        [string]$SectionId,
        [string]$ContentPath
    )

    if ([string]::IsNullOrWhiteSpace($SectionId) -or [string]::IsNullOrWhiteSpace($ContentPath)) {
        return $false
    }

    try {
        $encodedPath = [System.Uri]::EscapeDataString($ContentPath)
        $url = "$PlexUrl/library/sections/$SectionId/refresh?path=$encodedPath&X-Plex-Token=$PlexToken"
        Write-Log "Escaneo parcial activado: section=$SectionId path=$ContentPath"
        Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Log "Error en escaneo parcial de Plex: $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

function Get-PlexSectionMediaType {
    param([string]$ContentType)

    switch ($ContentType) {
        "PELICULA" { return 1 }
        "EPISODIO" { return 4 }
        "TEMPORADA" { return 2 }
        default { return 1 }
    }
}

function Get-PlexItemsFromContainer {
    param($Result)

    $items = @()
    if ($Result.MediaContainer.Video) { $items += @($Result.MediaContainer.Video) }
    if ($Result.MediaContainer.Directory) { $items += @($Result.MediaContainer.Directory) }
    if ($Result.MediaContainer.Metadata) { $items += @($Result.MediaContainer.Metadata) }
    return $items
}

function Find-PlexItemByPath {
    param(
        [string]$SectionId,
        [string]$ContentPath,
        [hashtable]$DetectedMetadata,
        [int]$RecentItemCount = 50
    )

    if ([string]::IsNullOrWhiteSpace($SectionId) -or [string]::IsNullOrWhiteSpace($ContentPath)) {
        return $null
    }

    $mediaType = Get-PlexSectionMediaType -ContentType $DetectedMetadata.Type
    $url = "$PlexUrl/library/sections/$SectionId/all?type=$mediaType&sort=addedAt:desc&X-Plex-Container-Size=$RecentItemCount&X-Plex-Token=$PlexToken"

    try {
        [xml]$result = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        $items = Get-PlexItemsFromContainer -Result $result

        $bestItem = $null
        $bestScore = 0

        foreach ($item in $items) {
            $score = Get-PlexMatchScore -PlexItem $item -DetectedMetadata $DetectedMetadata -ContentPath $ContentPath
            if ($score -gt $bestScore) {
                $bestScore = $score
                $bestItem = $item
            }
        }

        if ($bestItem -and (Test-PlexItemAcceptable -Score $bestScore -PlexItem $bestItem -DetectedMetadata $DetectedMetadata)) {
            return @{
                item  = $bestItem
                score = $bestScore
            }
        }
    }
    catch {
        Write-Log "Error en lookup por ruta Plex: $($_.Exception.Message)" -Level "WARNING"
    }

    return $null
}

function Wait-ForPlexItem {
    param(
        [string]$SectionId,
        [string]$ContentPath,
        [hashtable]$DetectedMetadata,
        [int]$PollSeconds = 5,
        [int]$MaxAttempts = 12
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $match = Find-PlexItemByPath -SectionId $SectionId -ContentPath $ContentPath -DetectedMetadata $DetectedMetadata
        if ($match) {
            Write-Log "Item encontrado por ruta (intento $attempt, puntuación $($match.score)): $($match.item.title)"
            return $match
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Log "Intento de búsqueda por ruta $attempt/$MaxAttempts sin resultado, esperando ${PollSeconds}s..."
            Start-Sleep -Seconds $PollSeconds
        }
    }

    return $null
}

function Get-PlexSearchTypes {
    param([string]$ContentType)

    $searchTypes = @()
    switch ($ContentType) {
        "PELICULA"  { $searchTypes += @{ Type = 1; Description = "pelicula" } }
        "EPISODIO"  { $searchTypes += @{ Type = 8; Description = "episodio" }; $searchTypes += @{ Type = 2; Description = "serie" } }
        "TEMPORADA" { $searchTypes += @{ Type = 2; Description = "serie" } }
        default     { $searchTypes += @{ Type = 1; Description = "pelicula" }; $searchTypes += @{ Type = 2; Description = "serie" } }
    }
    $searchTypes += @{ Type = $null; Description = "generica" }
    return $searchTypes
}

function Search-PlexWithQueries {
    param(
        [string[]]$Queries,
        [hashtable]$DetectedMetadata,
        [string]$ContentPath,
        [string]$SearchTitle
    )

    $searchTypes = Get-PlexSearchTypes -ContentType $DetectedMetadata.Type
    $bestPosterUrl = $null
    $bestScore = 0
    $bestItem = $null
    $matchMethod = "none"

    foreach ($query in $Queries) {
        foreach ($searchType in $searchTypes) {
            $plexSearchUrl = "$PlexUrl/search?query=$([System.Uri]::EscapeDataString($query))&X-Plex-Token=$PlexToken"
            if ($searchType.Type) {
                $plexSearchUrl += "&type=$($searchType.Type)"
            }

            Write-Log "Intentando busqueda Plex ($($searchType.Description), query='$query'): $plexSearchUrl"

            try {
                [xml]$result = Invoke-RestMethod -Uri $plexSearchUrl -Method Get -ErrorAction Stop
                $plexItems = @()

                if ($result.MediaContainer.Video) { $plexItems += @($result.MediaContainer.Video) }
                if ($result.MediaContainer.Directory) { $plexItems += @($result.MediaContainer.Directory) }
                if ($result.MediaContainer.Metadata) { $plexItems += @($result.MediaContainer.Metadata) }
                if ($result.MediaContainer.SearchResult) { $plexItems += @($result.MediaContainer.SearchResult) }

                Write-Log "Plex devolvio $($plexItems.Count) items para query '$query' ($($searchType.Description))"

                foreach ($item in $plexItems) {
                    $currentScore = Get-PlexMatchScore -PlexItem $item -DetectedMetadata $DetectedMetadata -ContentPath $ContentPath

                    if ((Test-PlexItemAcceptable -Score $currentScore -PlexItem $item -DetectedMetadata $DetectedMetadata) -and $currentScore -gt $bestScore) {
                        $poster = Get-PlexPosterFromItem $item
                        if ($poster) {
                            $bestScore = $currentScore
                            $bestPosterUrl = $poster
                            $bestItem = $item
                            $matchMethod = "$($searchType.Description):$query"
                            Write-Log "  Match aceptable (score $currentScore): $($item.title)"
                        }
                    }
                }
            }
            catch {
                Write-Log "Error durante la busqueda Plex ($($searchType.Description), query='$query'): $($_.Exception.Message)" -Level "WARNING"
            }
        }

        if ($bestPosterUrl -and $bestScore -ge 90) {
            break
        }
    }

    if ($bestPosterUrl) {
        return @{
            posterUrl   = $bestPosterUrl
            item        = $bestItem
            score       = $bestScore
            matchMethod = $matchMethod
        }
    }

    return $null
}

function Save-PlexPosterResult {
    param(
        $BestItem,
        [string]$PosterUrl,
        [string]$SearchTitle,
        [string]$BasePath,
        [string]$ProjectRoot
    )

    if (-not $BestItem -or -not $BestItem.ratingKey -or -not $BestItem.title) {
        return
    }

    $itemType = if ($BestItem.type -eq "show") { "SERIE" } else { "PELICULA" }
    $yearValue = 0
    if ($BestItem.year) {
        [void][int]::TryParse([string]$BestItem.year, [ref]$yearValue)
    }

    $aliases = @()
    if ($SearchTitle -and (Normalize-CacheKey $BestItem.title) -ne (Normalize-CacheKey $SearchTitle)) {
        $aliases += $SearchTitle
    }

    Add-ToCache -Title $BestItem.title `
                -RatingKey $BestItem.ratingKey `
                -Type $itemType `
                -PosterUrl $PosterUrl `
                -Year $yearValue `
                -Aliases $aliases `
                -BasePath $BasePath `
                -ProjectRoot $ProjectRoot
}

function Get-PlexPoster {
    param(
        [string]$Title,
        [string]$ContentPath,
        [hashtable]$DetectedMetadata,
        [string]$BasePath = ".",
        [int]$PlexScanPollSeconds = 0,
        [int]$PlexScanPollMaxAttempts = 0,
        [switch]$SkipPlexScan
    )

    if ($PlexScanPollSeconds -le 0) { $PlexScanPollSeconds = $script:PlexScanPollSeconds }
    if ($PlexScanPollMaxAttempts -le 0) { $PlexScanPollMaxAttempts = $script:PlexScanPollMaxAttempts }
    if (-not $PSBoundParameters.ContainsKey('SkipPlexScan')) {
        $SkipPlexScan = [bool]$script:SkipPlexScan
    }

    Write-Log "Iniciando busqueda de poster para '$($DetectedMetadata.Title)' (Tipo: $($DetectedMetadata.Type))"

    if (-not $script:PlexCacheLoaded) {
        Initialize-PlexCache -SkipDelay $true -BasePath $BasePath -ProjectRoot $script:ProjectRoot
    }

    $searchTitle = Get-SearchTitle -Title $Title -Type $DetectedMetadata.Type
    $ratingKeyToSearch = Resolve-RatingKey -Title $searchTitle `
                                           -DetectedMetadata $DetectedMetadata `
                                           -BasePath $BasePath `
                                           -ProjectRoot $script:ProjectRoot

    Write-Log "Búsqueda poster: título='$searchTitle', RatingKey='$ratingKeyToSearch'"

    $cacheResult = Get-PosterByCache -Title $searchTitle -RatingKey $ratingKeyToSearch -DetectedMetadata $DetectedMetadata
    if ($cacheResult.found) {
        Write-Log "Poster encontrado en caché (método: $($cacheResult.method), score: $($cacheResult.score)%)"
        if ($cacheResult.title) {
            $script:LastPosterDisplayTitle = $cacheResult.title
        }
        if (Get-Variable -Name PlexSearchLog -Scope Script -ErrorAction SilentlyContinue) {
            $script:PlexSearchLog += @{
                method    = $cacheResult.method
                title     = $cacheResult.title
                score     = $cacheResult.score
                ratingKey = $cacheResult.ratingKey
            }
        }
        return $cacheResult.url
    }

    Write-Log "Poster NO encontrado en caché. Intentando API..."

    # FASE 1: partial scan + lookup por ruta
    if (-not $SkipPlexScan -and -not [string]::IsNullOrWhiteSpace($ContentPath)) {
        $section = Resolve-PlexSectionForPath -ContentPath $ContentPath -ContentType $DetectedMetadata.Type
        if ($section) {
            Invoke-PlexPartialScan -SectionId $section.key -ContentPath $ContentPath | Out-Null
            $pathMatch = Wait-ForPlexItem -SectionId $section.key `
                                           -ContentPath $ContentPath `
                                           -DetectedMetadata $DetectedMetadata `
                                           -PollSeconds $PlexScanPollSeconds `
                                           -MaxAttempts $PlexScanPollMaxAttempts
            if ($pathMatch) {
                $posterUrl = Get-PlexPosterFromItem $pathMatch.item
                if ($posterUrl) {
                    Write-Log "Poster final seleccionado (Score: $($pathMatch.score), Metodo: path_lookup): $posterUrl"
                    $script:LastPosterDisplayTitle = $pathMatch.item.title
                    Save-PlexPosterResult -BestItem $pathMatch.item `
                                          -PosterUrl $posterUrl `
                                          -SearchTitle $searchTitle `
                                          -BasePath $BasePath `
                                          -ProjectRoot $script:ProjectRoot
                    return $posterUrl
                }
            }
        }
        else {
            Write-Log "No se pudo resolver seccion Plex para ruta: $ContentPath" -Level "WARNING"
        }
    }
    elseif ($SkipPlexScan) {
        Write-Log "SkipPlexScan activo, omitiendo partial scan"
    }

    # FASE 2: búsqueda progresiva por variantes de título
    $queries = Get-PlexSearchQueries -Title $searchTitle
    Write-Log "Queries progresivas: $($queries -join ' | ')"

    $searchResult = Search-PlexWithQueries -Queries $queries `
                                           -DetectedMetadata $DetectedMetadata `
                                           -ContentPath $ContentPath `
                                           -SearchTitle $searchTitle

    if ($searchResult) {
        Write-Log "Poster final seleccionado (Score: $($searchResult.score), Metodo: $($searchResult.matchMethod)): $($searchResult.posterUrl)"
        $script:LastPosterDisplayTitle = $searchResult.item.title
        Save-PlexPosterResult -BestItem $searchResult.item `
                              -PosterUrl $searchResult.posterUrl `
                              -SearchTitle $searchTitle `
                              -BasePath $BasePath `
                              -ProjectRoot $script:ProjectRoot
        return $searchResult.posterUrl
    }

    Write-Log "No se encontro ningun poster adecuado en Plex."
    return $null
}
