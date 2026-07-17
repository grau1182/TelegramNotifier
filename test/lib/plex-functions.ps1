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

function Get-PlexPosterUrlFromPath {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $null
    }

    return $PlexUrl.TrimEnd('/') + $RelativePath + "?X-Plex-Token=$PlexToken"
}

function Get-PlexItemTypeName {
    param($Item)

    if (-not $Item -or -not $Item.type) {
        return ""
    }

    return [string]$Item.type
}

function Test-PlexSeriesContentType {
    param(
        $Item,
        [hashtable]$DetectedMetadata = $null
    )

    if ($DetectedMetadata -and $DetectedMetadata.Type -in @("EPISODIO", "TEMPORADA", "SERIE")) {
        return $true
    }

    return (Get-PlexItemTypeName $Item) -in @("episode", "season", "show")
}

function Get-PlexCoverPosterImageUrl {
    param(
        $Item,
        [string]$PreferredRatingKey = ""
    )

    if (-not $Item.Image) {
        return $null
    }

    foreach ($image in @($Item.Image)) {
        if ($image.type -ne "coverPoster" -or [string]::IsNullOrWhiteSpace($image.url)) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($PreferredRatingKey)) {
            if ($image.url -match "/metadata/$PreferredRatingKey/") {
                return [string]$image.url
            }
            continue
        }

        if ((Get-PlexItemTypeName $Item) -eq "episode") {
            continue
        }

        return [string]$image.url
    }

    return $null
}

function Get-PlexPosterFromItem {
    param(
        $Item,
        [hashtable]$DetectedMetadata = $null
    )

    if (-not $Item) {
        return $null
    }

    $itemType = Get-PlexItemTypeName $Item

    if (Test-PlexSeriesContentType -Item $Item -DetectedMetadata $DetectedMetadata) {
        if ($itemType -eq "season") {
            if ($Item.thumb) {
                $url = Get-PlexPosterUrlFromPath ([string]$Item.thumb)
                Write-Log "Poster serie: thumb temporada -> $url"
                return $url
            }

            $seasonPoster = Get-PlexCoverPosterImageUrl -Item $Item -PreferredRatingKey ([string]$Item.ratingKey)
            if ($seasonPoster) {
                $url = Get-PlexPosterUrlFromPath $seasonPoster
                Write-Log "Poster serie: coverPoster temporada -> $url"
                return $url
            }

            if ($Item.parentThumb) {
                $url = Get-PlexPosterUrlFromPath ([string]$Item.parentThumb)
                Write-Log "Poster serie: parentThumb show (fallback temporada) -> $url"
                return $url
            }

            return $null
        }

        if ($itemType -eq "show") {
            if ($DetectedMetadata -and $DetectedMetadata.Type -in @("TEMPORADA", "EPISODIO")) {
                return $null
            }

            if ($Item.thumb) {
                $url = Get-PlexPosterUrlFromPath ([string]$Item.thumb)
                Write-Log "Poster serie: thumb show -> $url"
                return $url
            }

            $showPoster = Get-PlexCoverPosterImageUrl -Item $Item -PreferredRatingKey ([string]$Item.ratingKey)
            if ($showPoster) {
                $url = Get-PlexPosterUrlFromPath $showPoster
                Write-Log "Poster serie: coverPoster show -> $url"
                return $url
            }

            return $null
        }

        # episode (o item jerárquico con parent/grandparent): temporada -> serie, nunca snapshot del capítulo
        if ($Item.parentThumb) {
            $url = Get-PlexPosterUrlFromPath ([string]$Item.parentThumb)
            Write-Log "Poster serie: parentThumb (temporada) -> $url"
            return $url
        }

        if ($Item.grandparentThumb) {
            $url = Get-PlexPosterUrlFromPath ([string]$Item.grandparentThumb)
            Write-Log "Poster serie: grandparentThumb (show) -> $url"
            return $url
        }

        $showRatingKey = if ($Item.grandparentRatingKey) { [string]$Item.grandparentRatingKey } else { "" }
        $showPoster = Get-PlexCoverPosterImageUrl -Item $Item -PreferredRatingKey $showRatingKey
        if ($showPoster) {
            $url = Get-PlexPosterUrlFromPath $showPoster
            Write-Log "Poster serie: coverPoster show -> $url"
            return $url
        }

        Write-Log "Poster serie: sin poster temporada/show para item type=$itemType ratingKey=$($Item.ratingKey)" -Level "WARNING"
        return $null
    }

    if ($Item.thumb) {
        return Get-PlexPosterUrlFromPath ([string]$Item.thumb)
    }
    if ($Item.art) {
        return Get-PlexPosterUrlFromPath ([string]$Item.art)
    }

    return $null
}

function Get-PlexMatchTitle {
    param(
        $PlexItem,
        [hashtable]$DetectedMetadata
    )

    $itemType = Get-PlexItemTypeName $PlexItem

    if ($DetectedMetadata.Type -in @("EPISODIO", "TEMPORADA")) {
        if ($PlexItem.grandparentTitle) {
            return [string]$PlexItem.grandparentTitle
        }
        if ($itemType -eq "show") {
            return [string]$PlexItem.title
        }
        if ($itemType -eq "season" -and $PlexItem.parentTitle) {
            return [string]$PlexItem.parentTitle
        }
    }

    return [string]$PlexItem.title
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
    $itemType = Get-PlexItemTypeName $PlexItem

    if ($DetectedMetadata.Type -eq "TEMPORADA" -and $itemType -eq "episode") {
        if ($PlexFilePath -eq $NormalizedContentPath) {
            $Score += 100
        }
    }
    else {
        if ($PlexFilePath -eq $NormalizedContentPath) {
            $Score += 100
        }
        elseif ($PlexFilePath -and $NormalizedContentPath -and $PlexFilePath.StartsWith($NormalizedContentPath + "\")) {
            $Score += 70
        }
        elseif ($PlexFilePath -and $NormalizedContentPath -and $NormalizedContentPath.StartsWith($PlexFilePath + "\")) {
            $Score += 70
        }
    }

    $scoreTitle = Get-SearchTitle -Title $DetectedMetadata.Title -Type $DetectedMetadata.Type
    $plexMatchTitle = Get-PlexMatchTitle -PlexItem $PlexItem -DetectedMetadata $DetectedMetadata

    $NormalizedPlexTitle = Normalize-PlexTitle $plexMatchTitle
    $NormalizedDetectedTitle = Normalize-PlexTitle $scoreTitle

    if ($NormalizedPlexTitle -eq $NormalizedDetectedTitle) {
        $Score += 50
    }
    elseif ($NormalizedPlexTitle.Contains($NormalizedDetectedTitle) -or $NormalizedDetectedTitle.Contains($NormalizedPlexTitle)) {
        $Score += 30
    }
    else {
        $detectedRoot = ($scoreTitle -split '[,:]')[0].Trim().ToLower()
        $plexRoot = ($plexMatchTitle -split '[,:]')[0].Trim().ToLower()
        if (-not [string]::IsNullOrWhiteSpace($detectedRoot) -and $detectedRoot -eq $plexRoot) {
            $Score += 35
        }

        $fuzzyScore = Get-FuzzyMatchScore (Normalize-CacheKey $scoreTitle) (Normalize-CacheKey $plexMatchTitle)
        if ($fuzzyScore -ge 85) {
            $Score += 25
        }
        elseif ($fuzzyScore -ge 60) {
            $Score += 15
        }
    }

    if ($DetectedMetadata.Type -eq "PELICULA" -and $PlexItem.year -eq $DetectedMetadata.Year) {
        $Score += 40
    }

    if ($DetectedMetadata.Type -eq "PELICULA") {
        $detectedNorm = Normalize-PlexTitle $scoreTitle
        $plexNorm = Normalize-PlexTitle $plexMatchTitle

        if ($plexNorm.StartsWith($detectedNorm) -and $plexNorm.Length -gt $detectedNorm.Length) {
            $suffix = $plexMatchTitle.Substring($scoreTitle.Length).Trim()
            if ($suffix -match '^\d') {
                $Score += 45
            }
        }

        $detectedNum = [regex]::Match($scoreTitle, '(\d+)\s*$').Groups[1].Value
        $plexNum = [regex]::Match($plexMatchTitle, '(\d+)\s*$').Groups[1].Value
        if ($detectedNum -and $plexNum -and $detectedNum -eq $plexNum) {
            $Score += 35
        }
    }

    if ($ContentPath -match 'STAR_WARS_REBELS') {
        if ($plexMatchTitle -match '(?i)rebel') {
            $Score += 45
        }
        elseif ($plexMatchTitle -match '(?i)clone|andor|mandalorian|resistance|skeleton|underworld|visions') {
            $Score -= 40
        }
    }

    if ($DetectedMetadata.Type -eq "EPISODIO") {
        if ($itemType -eq "episode" -and $PlexItem.parentIndex -eq $DetectedMetadata.Season -and $PlexItem.index -eq $DetectedMetadata.Episode) {
            $Score += 60
        }
        if ($itemType -eq "season" -and $PlexItem.index -eq $DetectedMetadata.Season) {
            $Score += 35
        }
        if ($itemType -eq "show") {
            $Score += 25
        }
    }

    if ($DetectedMetadata.Type -eq "TEMPORADA") {
        if ($itemType -eq "season" -and $PlexItem.index -eq $DetectedMetadata.Season) {
            $Score += 50
        }
        if ($itemType -eq "show") {
            $Score += 40
        }
        if ($itemType -eq "episode") {
            $Score -= 35
        }
    }

    return $Score
}

function Test-PlexItemAcceptable {
    param(
        [int]$Score,
        $PlexItem,
        [hashtable]$DetectedMetadata,
        [string]$ContentPath = ""
    )

    if ($ContentPath -and $PlexItem) {
        $plexPath = Get-PlexItemFilePath $PlexItem
        $normalizedContent = Normalize-FilePath $ContentPath
        if ($plexPath -and $normalizedContent -eq $plexPath) {
            return $true
        }
    }

    if ($Score -ge 100) { return $true }
    if ($Score -ge 90) { return $true }
    if ($Score -ge 70) { return $true }

    if ($Score -ge 40 -and $DetectedMetadata.Year -and $PlexItem.year -eq $DetectedMetadata.Year) {
        $scoreTitle = Get-SearchTitle -Title $DetectedMetadata.Title -Type $DetectedMetadata.Type
        $plexMatchTitle = Get-PlexMatchTitle -PlexItem $PlexItem -DetectedMetadata $DetectedMetadata
        $fuzzyScore = Get-FuzzyMatchScore (Normalize-CacheKey $scoreTitle) (Normalize-CacheKey $plexMatchTitle)
        if (($Score + $fuzzyScore) -ge 60) {
            return $true
        }
    }

    return $false
}

function Get-PlexSearchQueries {
    param([string]$Title)

    $queries = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    function Add-Query {
        param([string]$Value)
        $Value = $Value.Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        $key = $Value.ToLower()
        if (-not $seen[$key]) {
            $seen[$key] = $true
            $queries.Add($Value) | Out-Null
        }
    }

    foreach ($variant in (Split-TitleVariants -Title $Title)) {
        Add-Query $variant
    }

    foreach ($alias in (Get-PlexTitleSearchAliases -Title $Title)) {
        Add-Query $alias
    }

    return @($queries)
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
        Write-Log "Error en partial scan Plex: $($_.Exception.Message)" -Level "WARNING"
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

function Get-PlexMetadataItem {
    param([string]$RatingKey)

    if ([string]::IsNullOrWhiteSpace($RatingKey)) {
        return $null
    }

    try {
        $url = "$PlexUrl/library/metadata/$RatingKey?X-Plex-Token=$PlexToken"
        [xml]$result = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        return (Get-PlexItemsFromContainer -Result $result | Select-Object -First 1)
    }
    catch {
        Write-Log "Error obteniendo metadata Plex $RatingKey : $($_.Exception.Message)" -Level "WARNING"
        return $null
    }
}

function Get-PlexSeasonItemFromShow {
    param(
        [string]$ShowRatingKey,
        [int]$SeasonNumber
    )

    if ([string]::IsNullOrWhiteSpace($ShowRatingKey) -or $SeasonNumber -le 0) {
        return $null
    }

    try {
        $url = "$PlexUrl/library/metadata/$ShowRatingKey/children?X-Plex-Token=$PlexToken"
        [xml]$result = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop

        foreach ($item in (Get-PlexItemsFromContainer -Result $result)) {
            if ((Get-PlexItemTypeName $item) -eq "season" -and [int]$item.index -eq $SeasonNumber) {
                return $item
            }
        }
    }
    catch {
        Write-Log "Error obteniendo temporadas de show $ShowRatingKey : $($_.Exception.Message)" -Level "WARNING"
    }

    return $null
}

function Resolve-PlexSeriesPoster {
    param(
        [string]$ShowRatingKey,
        [hashtable]$DetectedMetadata,
        $SourceItem = $null
    )

    if ($SourceItem) {
        $poster = Get-PlexPosterFromItem -Item $SourceItem -DetectedMetadata $DetectedMetadata
        if ($poster) {
            return $poster
        }
    }

    $seasonNumber = 0
    if ($DetectedMetadata.Season) {
        [void][int]::TryParse([string]$DetectedMetadata.Season, [ref]$seasonNumber)
    }

    if ($seasonNumber -gt 0 -and $DetectedMetadata.Type -in @("TEMPORADA", "EPISODIO")) {
        $seasonItem = Get-PlexSeasonItemFromShow -ShowRatingKey $ShowRatingKey -SeasonNumber $seasonNumber
        if ($seasonItem) {
            $poster = Get-PlexPosterFromItem -Item $seasonItem -DetectedMetadata $DetectedMetadata
            if ($poster) {
                Write-Log "Poster resuelto desde temporada S$('{0:D2}' -f $seasonNumber) del show $ShowRatingKey"
                return $poster
            }
        }
    }

    $showItem = Get-PlexMetadataItem -RatingKey $ShowRatingKey
    if ($showItem) {
        $poster = Get-PlexPosterFromItem -Item $showItem -DetectedMetadata $DetectedMetadata
        if ($poster) {
            Write-Log "Poster resuelto desde show $ShowRatingKey"
            return $poster
        }
    }

    return $null
}

function Get-PlexCacheEntryFromItem {
    param(
        $Item,
        [hashtable]$DetectedMetadata = $null
    )

    $entry = @{
        RatingKey = [string]$Item.ratingKey
        Title     = [string]$Item.title
        Type      = "PELICULA"
        Year      = 0
    }

    if ($Item.year) {
        [void][int]::TryParse([string]$Item.year, [ref]$entry.Year)
    }

    $itemType = Get-PlexItemTypeName $Item

    if ($Item.grandparentRatingKey) {
        $entry.RatingKey = [string]$Item.grandparentRatingKey
        $entry.Title = [string]$Item.grandparentTitle
        $entry.Type = "SERIE"
        return $entry
    }

    if ($itemType -eq "show") {
        $entry.Type = "SERIE"
        return $entry
    }

    if ($itemType -eq "season" -and $Item.parentRatingKey) {
        $entry.RatingKey = [string]$Item.parentRatingKey
        if ($Item.parentTitle) {
            $entry.Title = [string]$Item.parentTitle
        }
        $entry.Type = "SERIE"
        return $entry
    }

    if ($DetectedMetadata -and $DetectedMetadata.Type -in @("EPISODIO", "TEMPORADA", "SERIE")) {
        $entry.Type = "SERIE"
    }

    return $entry
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

        if ($bestItem -and (Test-PlexItemAcceptable -Score $bestScore -PlexItem $bestItem -DetectedMetadata $DetectedMetadata -ContentPath $ContentPath)) {
            return @{
                item  = $bestItem
                score = $bestScore
            }
        }
        elseif ($bestItem) {
            Write-Log "Path lookup: mejor candidato descartado (score $bestScore, umbral 70): [$(Get-PlexItemTypeName $bestItem)] $($bestItem.title)" -Level "WARNING"
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
            Write-Log "Item found by path (attempt $attempt, score $($match.score)): $($match.item.title)"
            return $match
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Log "Path lookup attempt $attempt/$MaxAttempts sin resultado, esperando ${PollSeconds}s..."
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
                    $matchTitle = Get-PlexMatchTitle -PlexItem $item -DetectedMetadata $DetectedMetadata
                    $itemLabel = "[$(Get-PlexItemTypeName $item)] $matchTitle"

                    if ((Test-PlexItemAcceptable -Score $currentScore -PlexItem $item -DetectedMetadata $DetectedMetadata -ContentPath $ContentPath) -and $currentScore -gt $bestScore) {
                        $poster = Get-PlexPosterFromItem -Item $item -DetectedMetadata $DetectedMetadata
                        if (-not $poster -and (Get-PlexItemTypeName $item) -eq "show") {
                            $cacheEntry = Get-PlexCacheEntryFromItem -Item $item -DetectedMetadata $DetectedMetadata
                            $poster = Resolve-PlexSeriesPoster -ShowRatingKey $cacheEntry.RatingKey -DetectedMetadata $DetectedMetadata -SourceItem $item
                        }

                        if ($poster) {
                            $bestScore = $currentScore
                            $bestPosterUrl = $poster
                            $bestItem = $item
                            $matchMethod = "$($searchType.Description):$query"
                            Write-Log "  Match aceptable (score $currentScore): $itemLabel"
                        }
                    }
                    elseif ($currentScore -gt 0) {
                        Write-Log "  Descartado (score $currentScore, umbral 70): $itemLabel"
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
        [string]$ProjectRoot,
        [hashtable]$DetectedMetadata = $null
    )

    if (-not $BestItem -or -not $BestItem.ratingKey) {
        return
    }

    $cacheEntry = Get-PlexCacheEntryFromItem -Item $BestItem -DetectedMetadata $DetectedMetadata
    if ([string]::IsNullOrWhiteSpace($cacheEntry.RatingKey)) {
        return
    }

    $aliases = @()
    if ($SearchTitle -and (Normalize-CacheKey $cacheEntry.Title) -ne (Normalize-CacheKey $SearchTitle)) {
        $aliases += $SearchTitle
    }

    Add-ToCache -Title $cacheEntry.Title `
                -RatingKey $cacheEntry.RatingKey `
                -Type $cacheEntry.Type `
                -PosterUrl $PosterUrl `
                -Year $cacheEntry.Year `
                -Aliases $aliases `
                -BasePath $BasePath `
                -ProjectRoot $ProjectRoot
}

function Set-LastPosterDisplayTitle {
    param(
        $Item,
        [hashtable]$DetectedMetadata
    )

    elseif ($DetectedMetadata -and $DetectedMetadata.Type -in @("EPISODIO", "TEMPORADA", "SERIE")) {
        return
    }

    if (-not $DetectedMetadata) {
        return
    }

    if ($Item -and $Item.title) {
        if (Test-PosterTitleRefinement -ParsedTitle $DetectedMetadata.Title -PosterTitle ([string]$Item.title)) {
            $script:LastPosterDisplayTitle = [string]$Item.title
        }
    }
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
        $resolvedPosterUrl = $cacheResult.url

        if ($DetectedMetadata.Type -in @("EPISODIO", "TEMPORADA") -and $cacheResult.ratingKey) {
            $runtimePoster = Resolve-PlexSeriesPoster -ShowRatingKey $cacheResult.ratingKey -DetectedMetadata $DetectedMetadata
            if ($runtimePoster) {
                $resolvedPosterUrl = $runtimePoster
                Write-Log "Poster de caché re-resuelto en runtime (serie $($cacheResult.ratingKey))"
            }
        }

        Write-Log "Poster encontrado en caché (método: $($cacheResult.method), score: $($cacheResult.score)%)"
        if ($cacheResult.title -and $DetectedMetadata.Type -eq "PELICULA" -and (Test-PosterTitleRefinement -ParsedTitle $DetectedMetadata.Title -PosterTitle $cacheResult.title)) {
            $script:LastPosterDisplayTitle = $cacheResult.title
        }
        if (Get-Variable -Name PlexSearchLog -Scope Script -ErrorAction SilentlyContinue) {
            $script:PlexSearchLog += @{
                method    = $cacheResult.method
                title     = $DetectedMetadata.Title
                score     = $cacheResult.score
                ratingKey = $cacheResult.ratingKey
            }
        }
        return $resolvedPosterUrl
    }

    Write-Log "Poster NO encontrado en caché. Intentando API..."

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
                $cacheEntry = Get-PlexCacheEntryFromItem -Item $pathMatch.item -DetectedMetadata $DetectedMetadata
                $posterUrl = Resolve-PlexSeriesPoster -ShowRatingKey $cacheEntry.RatingKey `
                                                      -DetectedMetadata $DetectedMetadata `
                                                      -SourceItem $pathMatch.item

                if (-not $posterUrl) {
                    $posterUrl = Get-PlexPosterFromItem -Item $pathMatch.item -DetectedMetadata $DetectedMetadata
                }

                if ($posterUrl) {
                    Write-Log "Poster final seleccionado (Score: $($pathMatch.score), Metodo: path_lookup): $posterUrl"
                    Set-LastPosterDisplayTitle -Item $pathMatch.item -DetectedMetadata $DetectedMetadata
                    Save-PlexPosterResult -BestItem $pathMatch.item `
                                          -PosterUrl $posterUrl `
                                          -SearchTitle $searchTitle `
                                          -BasePath $BasePath `
                                          -ProjectRoot $script:ProjectRoot `
                                          -DetectedMetadata $DetectedMetadata
                    if (Get-Variable -Name PlexSearchLog -Scope Script -ErrorAction SilentlyContinue) {
                        $script:PlexSearchLog += @{
                            method    = "path_lookup"
                            title     = $DetectedMetadata.Title
                            score     = $pathMatch.score
                            ratingKey = $cacheEntry.RatingKey
                        }
                    }
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

    $queries = Get-PlexSearchQueries -Title $searchTitle
    Write-Log "Queries progresivas: $($queries -join ' | ')"

    $searchResult = Search-PlexWithQueries -Queries $queries `
                                           -DetectedMetadata $DetectedMetadata `
                                           -ContentPath $ContentPath `
                                           -SearchTitle $searchTitle

    if ($searchResult) {
        Write-Log "Poster final seleccionado (Score: $($searchResult.score), Metodo: $($searchResult.matchMethod)): $($searchResult.posterUrl)"
        Set-LastPosterDisplayTitle -Item $searchResult.item -DetectedMetadata $DetectedMetadata
        Save-PlexPosterResult -BestItem $searchResult.item `
                              -PosterUrl $searchResult.posterUrl `
                              -SearchTitle $searchTitle `
                              -BasePath $BasePath `
                              -ProjectRoot $script:ProjectRoot `
                              -DetectedMetadata $DetectedMetadata
        if (Get-Variable -Name PlexSearchLog -Scope Script -ErrorAction SilentlyContinue) {
            $cacheEntry = Get-PlexCacheEntryFromItem -Item $searchResult.item -DetectedMetadata $DetectedMetadata
            $script:PlexSearchLog += @{
                method    = $searchResult.matchMethod
                title     = $DetectedMetadata.Title
                score     = $searchResult.score
                ratingKey = $cacheEntry.RatingKey
            }
        }
        return $searchResult.posterUrl
    }

    Write-Log "No se encontro ningun poster adecuado en Plex."
    return $null
}
