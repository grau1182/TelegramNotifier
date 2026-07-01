# ==================================================
# PLEX-FUNCTIONS.PS1 - Funciones de Búsqueda Plex
# ==================================================

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
    elseif ($PlexFilePath -and $PlexFilePath.StartsWith($NormalizedContentPath + "\")) {
        $Score += 70
    }

    $NormalizedPlexTitle = Normalize-PlexTitle $PlexItem.title
    $NormalizedDetectedTitle = Normalize-PlexTitle $DetectedMetadata.Title

    # Coincidencia de título
    if ($NormalizedPlexTitle -eq $NormalizedDetectedTitle) {
        $Score += 50
    }
    elseif ($NormalizedPlexTitle.Contains($NormalizedDetectedTitle)) {
        $Score += 30
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

function Get-PlexPoster {
    param(
        [string]$Title,
        [string]$ContentPath,
        [hashtable]$DetectedMetadata,
        [string]$BasePath = "."
    )

    Write-Log "Iniciando busqueda de poster para '$($DetectedMetadata.Title)' (Tipo: $($DetectedMetadata.Type))"

    $BestPosterUrl = $null
    $HighestScore = 0
    $MatchMethod = "none"
    $BestItem = $null

    # FASE 0: Búsqueda en caché
    if (-not $script:PlexCacheLoaded) {
        Initialize-PlexCache -SkipDelay $true -BasePath $BasePath
    }
    
    # Si tenemos ratingKey en metadata, pasarlo para búsqueda rápida
    $ratingKeyToSearch = if ($DetectedMetadata -and $DetectedMetadata.ratingKey) { $DetectedMetadata.ratingKey } else { "" }
    $cacheResult = Get-PosterByCache $Title -RatingKey $ratingKeyToSearch
    if ($cacheResult.found) {
        Write-Log "Poster encontrado en caché (método: $($cacheResult.method), score: $($cacheResult.score)%)"
        return $cacheResult.url
    }

    Write-Log "Poster NO encontrado en caché. Intentando API..."
    
    $SearchTypes = @()
    switch ($DetectedMetadata.Type) {
        "PELICULA"  { $SearchTypes += @{ Type = 1; Description = "pelicula" } }
        "EPISODIO"  { $SearchTypes += @{ Type = 8; Description = "episodio" }; $SearchTypes += @{ Type = 2; Description = "serie" } }
        "TEMPORADA" { $SearchTypes += @{ Type = 2; Description = "serie" } }
        default     { $SearchTypes += @{ Type = 1; Description = "pelicula" }; $SearchTypes += @{ Type = 2; Description = "serie" } }
    }
    $SearchTypes += @{ Type = $null; Description = "generica" }

    foreach ($SearchType in $SearchTypes) {
        $Query = $Title
        $PlexSearchUrl = "$PlexUrl/search?query=$([System.Uri]::EscapeDataString($Query))&X-Plex-Token=$PlexToken"
        if ($SearchType.Type) {
            $PlexSearchUrl += "&type=$($SearchType.Type)"
        }

        Write-Log "Intentando busqueda Plex ($($SearchType.Description)): $PlexSearchUrl"

        try {
            [xml]$Result = Invoke-RestMethod -Uri $PlexSearchUrl -Method Get -ErrorAction Stop
            $PlexItems = @()

            if ($Result.MediaContainer.Video) {
                $PlexItems += $Result.MediaContainer.Video
            }
            if ($Result.MediaContainer.Directory) {
                $PlexItems += $Result.MediaContainer.Directory
            }
            if ($Result.MediaContainer.Metadata) {
                $PlexItems += $Result.MediaContainer.Metadata
            }
            if ($Result.MediaContainer.SearchResult) {
                $PlexItems += $Result.MediaContainer.SearchResult
            }

            Write-Log "Plex devolvio $($PlexItems.Count) items para la busqueda $($SearchType.Description)"

            foreach ($Item in $PlexItems) {
                $CurrentScore = Get-PlexMatchScore -PlexItem $Item -DetectedMetadata $DetectedMetadata -ContentPath $ContentPath

                if ($CurrentScore -gt $HighestScore) {
                    $Poster = Get-PlexPosterFromItem $Item
                    if ($Poster) {
                        $HighestScore = $CurrentScore
                        $BestPosterUrl = $Poster
                        $BestItem = $Item
                        $MatchMethod = $SearchType.Description
                        Write-Log "  Nuevo mejor poster encontrado con score $($HighestScore): $($BestPosterUrl)"
                    }
                }
            }
        }
        catch {
            Write-Log "Error durante la busqueda Plex ($($SearchType.Description)): $($_.Exception.Message)" -Level "WARNING"
        }
    }

    if ($BestPosterUrl) {
        Write-Log "Poster final seleccionado (Score: $HighestScore, Metodo: $MatchMethod): $BestPosterUrl"
        
        # Actualizar caché si es nuevo
        if ($BestItem -and $BestItem.ratingKey -and $BestItem.title) {
            $itemType = if ($BestItem.type -eq "show") { "SERIE" } else { "PELICULA" }
            Add-ToCache -Title $BestItem.title `
                        -RatingKey $BestItem.ratingKey `
                        -Type $itemType `
                        -PosterUrl $BestPosterUrl `
                        -Year $BestItem.year `
                        -BasePath $BasePath
        }
        
        return $BestPosterUrl
    }

    Write-Log "No se encontro ningun poster adecuado en Plex."
    return $null
}
