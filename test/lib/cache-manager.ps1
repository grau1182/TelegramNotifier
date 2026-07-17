# ==================================================
# CACHE-MANAGER.PS1 - Gestión de Caché Plex
# ==================================================

$script:PlexCacheLoaded = $false
$script:PlexCache = @()
$script:ProjectRoot = ""
$script:UseTestCache = $false

function Get-PlexCacheFilePath {
    param([string]$ProjectRoot = "")

    if ([string]::IsNullOrEmpty($ProjectRoot) -and $script:ProjectRoot) {
        $ProjectRoot = $script:ProjectRoot
    }

    if ($script:UseTestCache) {
        $testBase = Split-Path $PSScriptRoot -Parent
        return Join-Path $testBase "recursos\plex_cache_test.json"
    }

    if ([string]::IsNullOrEmpty($ProjectRoot)) {
        $ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    }

    return Join-Path $ProjectRoot "recursos\plex_cache.json"
}

function Reset-PlexCache {
    $script:PlexCache = @()
    $script:PlexCacheLoaded = $false
}

function Initialize-EmptyTestCacheFile {
    param([string]$ProjectRoot = "")

    $cacheFilePath = Get-PlexCacheFilePath -ProjectRoot $ProjectRoot
    $cacheDir = Split-Path $cacheFilePath -Parent

    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    $emptyCache = @{
        totalItems  = 0
        lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        cache       = @()
    }

    $emptyCache | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFilePath -Encoding UTF8 -Force
    Write-Log "Caché test vacía creada: $cacheFilePath"
}

function Normalize-CacheKey {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $Text = $Text.ToLower().Trim()
    $Text = Remove-Accents $Text
    return $Text -replace '[^a-z0-9]', ''
}

function Test-CacheItemKeyMatch {
    param(
        $Item,
        [string]$SearchKey
    )

    if ($Item.titulo_normalizado -eq $SearchKey) {
        return $true
    }

    if ($Item.aliases) {
        foreach ($alias in @($Item.aliases)) {
            if ((Normalize-CacheKey $alias) -eq $SearchKey) {
                return $true
            }
        }
    }

    return $false
}

function Find-CacheItemByKey {
    param([string]$SearchKey)

    foreach ($item in $script:PlexCache) {
        if (Test-CacheItemKeyMatch -Item $item -SearchKey $SearchKey) {
            return $item
        }
    }

    return $null
}

function Initialize-PlexCache {
    param(
        [bool]$SkipDelay = $false,
        [string]$BasePath = ".",
        [string]$ProjectRoot = "",
        [switch]$ForceReload
    )

    if ($script:PlexCacheLoaded -and -not $ForceReload) {
        return
    }

    if ($ForceReload) {
        $script:PlexCache = @()
        $script:PlexCacheLoaded = $false
    }

    if (-not [string]::IsNullOrEmpty($ProjectRoot)) {
        $script:ProjectRoot = $ProjectRoot
    }
    elseif ([string]::IsNullOrEmpty($script:ProjectRoot) -and -not [string]::IsNullOrWhiteSpace($BasePath) -and $BasePath -ne ".") {
        $script:ProjectRoot = Split-Path $BasePath -Parent
    }

    Write-Log "Inicializando caché..."

    $cacheRoot = if (-not [string]::IsNullOrEmpty($ProjectRoot)) { $ProjectRoot } else { $script:ProjectRoot }
    $cacheFilePath = Get-PlexCacheFilePath -ProjectRoot $cacheRoot
    $allItems = @()

    if (Test-Path $cacheFilePath) {
        try {
            Write-Log "Leyendo caché persistente desde: $cacheFilePath"
            $cacheData = Get-Content $cacheFilePath -Encoding UTF8 | ConvertFrom-Json

            if ($cacheData.cache -and $cacheData.cache.Count -gt 0) {
                foreach ($item in $cacheData.cache) {
                    $entry = @{
                        titulo_normalizado = $item.titulo_normalizado
                        titulo_original    = $item.titulo_original
                        ratingKey          = $item.ratingKey
                        tipo               = $item.tipo
                        poster_url         = $item.poster_url
                        year               = $item.year
                    }
                    if ($item.aliases) {
                        $entry.aliases = @($item.aliases)
                    }
                    $allItems += $entry
                }
                Write-Log "Caché cargado desde archivo: $($cacheData.cache.Count) títulos"
            }
        }
        catch {
            Write-Log "Advertencia: Error leyendo caché: $($_.Exception.Message)" -Level "WARNING"
        }
    }
    elseif ($script:UseTestCache) {
        Write-Log "Caché test vacía en memoria (0 entradas)"
    }
    else {
        Write-Log "Advertencia: Caché no encontrado en $cacheFilePath" -Level "WARNING"
    }

    $script:PlexCache = $allItems
    $script:PlexCacheLoaded = $true
}

function Get-CacheFileData {
    param([string]$ProjectRoot = "")

    $cacheFilePath = Get-PlexCacheFilePath -ProjectRoot $ProjectRoot
    if (-not (Test-Path $cacheFilePath)) {
        return $null
    }

    return @{
        Path = $cacheFilePath
        Data = Get-Content $cacheFilePath -Encoding UTF8 | ConvertFrom-Json
    }
}

function Save-CacheToFile {
    param(
        $CacheData,
        [string]$ProjectRoot = ""
    )

    $cacheFilePath = Get-PlexCacheFilePath -ProjectRoot $ProjectRoot
    $CacheData.totalItems = @($CacheData.cache).Count
    $CacheData.lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $CacheData | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFilePath -Encoding UTF8 -Force

    return $CacheData.totalItems
}

function Add-CacheAliases {
    param(
        [string]$RatingKey,
        [string[]]$Aliases,
        [string]$ProjectRoot = ""
    )

    if ([string]::IsNullOrWhiteSpace($RatingKey) -or -not $Aliases -or $Aliases.Count -eq 0) {
        return $false
    }

    $cacheItem = $script:PlexCache | Where-Object { [string]$_.ratingKey -eq [string]$RatingKey } | Select-Object -First 1
    if (-not $cacheItem) {
        return $false
    }

    if (-not $cacheItem.aliases) {
        $cacheItem.aliases = @()
    }

    $added = @()
    foreach ($Alias in @($Aliases)) {
        if ([string]::IsNullOrWhiteSpace($Alias)) {
            continue
        }

        $aliasKey = Normalize-CacheKey $Alias
        if ($cacheItem.titulo_normalizado -eq $aliasKey) {
            continue
        }

        $alreadyExists = $false
        foreach ($existingAlias in @($cacheItem.aliases)) {
            if ((Normalize-CacheKey $existingAlias) -eq $aliasKey) {
                $alreadyExists = $true
                break
            }
        }

        if ($alreadyExists) {
            continue
        }

        $cacheItem.aliases += $Alias
        $added += $Alias
    }

    if ($added.Count -eq 0) {
        return $false
    }

    try {
        $cacheFile = Get-CacheFileData -ProjectRoot $ProjectRoot
        if (-not $cacheFile) {
            return $true
        }

        $fileItem = $cacheFile.Data.cache | Where-Object { [string]$_.ratingKey -eq [string]$RatingKey } | Select-Object -First 1
        if (-not $fileItem) {
            return $true
        }

        $fileItem.aliases = @($cacheItem.aliases)
        $totalItems = Save-CacheToFile -CacheData $cacheFile.Data -ProjectRoot $ProjectRoot

        if ($added.Count -eq 1) {
            Write-Log "Caché actualizado: alias '$($added[0])' agregado a RatingKey $RatingKey, $totalItems títulos en total"
        }
        else {
            Write-Log "Caché actualizado: $($added.Count) aliases agregados a RatingKey $RatingKey, $totalItems títulos en total"
        }
    }
    catch {
        Write-Log "No se pudo actualizar alias en caché: $($_.Exception.Message)" -Level "WARNING"
    }

    return $true
}

function Add-CacheAlias {
    param(
        [string]$RatingKey,
        [string]$Alias,
        [string]$ProjectRoot = ""
    )

    return Add-CacheAliases -RatingKey $RatingKey -Aliases @($Alias) -ProjectRoot $ProjectRoot
}

function Add-ToCache {
    param(
        [string]$Title,
        [string]$RatingKey,
        [string]$Type,
        [string]$PosterUrl,
        [int]$Year = 0,
        [string[]]$Aliases = @(),
        [string]$BasePath = ".",
        [string]$ProjectRoot = ""
    )

    $normalizedTitle = Normalize-CacheKey $Title

    $existingByKey = $script:PlexCache | Where-Object {
        [string]$_.ratingKey -eq [string]$RatingKey
    } | Select-Object -First 1

    if ($existingByKey) {
        if ($Aliases -and $Aliases.Count -gt 0) {
            Add-CacheAliases -RatingKey $RatingKey -Aliases $Aliases -ProjectRoot $ProjectRoot
        }
        return
    }

    $exists = $script:PlexCache | Where-Object {
        $_.titulo_normalizado -eq $normalizedTitle -and [string]$_.ratingKey -eq [string]$RatingKey
    }

    if ($exists) {
        if ($Aliases -and $Aliases.Count -gt 0) {
            Add-CacheAliases -RatingKey $RatingKey -Aliases $Aliases -ProjectRoot $ProjectRoot
        }
        return
    }

    $duplicate = $script:PlexCache | Where-Object {
        $_.titulo_normalizado -eq $normalizedTitle -and
        [string]$_.ratingKey -ne [string]$RatingKey
    } | Select-Object -First 1

    if ($duplicate) {
        Write-Log "Caché: colisión de clave '$normalizedTitle' entre '$Title' y '$($duplicate.titulo_original)'" -Level "WARNING"
    }

    $newItem = @{
        titulo_normalizado = $normalizedTitle
        titulo_original    = $Title
        ratingKey          = $RatingKey
        tipo               = $Type
        poster_url         = $PosterUrl
        year               = $Year
    }

    if ($Aliases -and $Aliases.Count -gt 0) {
        $newItem.aliases = @($Aliases)
    }

    $script:PlexCache += $newItem

    try {
        $cacheFile = Get-CacheFileData -ProjectRoot $ProjectRoot
        if (-not $cacheFile) {
            if ($script:UseTestCache) {
                Initialize-EmptyTestCacheFile -ProjectRoot $ProjectRoot
                $cacheFile = Get-CacheFileData -ProjectRoot $ProjectRoot
            }
            if (-not $cacheFile) {
                return
            }
        }

        $cacheFile.Data.cache += $newItem
        $totalItems = Save-CacheToFile -CacheData $cacheFile.Data -ProjectRoot $ProjectRoot
        Write-Log "Caché actualizado: Nuevo título '$Title' agregado con RatingKey $RatingKey, $totalItems títulos en total"
    }
    catch {
        Write-Log "No se pudo actualizar caché: $($_.Exception.Message)" -Level "WARNING"
    }
}

function Test-CacheItemYearMatch {
    param(
        $CacheItem,
        [hashtable]$DetectedMetadata
    )

    if (-not $DetectedMetadata -or $DetectedMetadata.Type -ne "PELICULA") {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace([string]$DetectedMetadata.Year)) {
        return $true
    }

    $cacheYear = [string]$CacheItem.year
    if ([string]::IsNullOrWhiteSpace($cacheYear) -or $cacheYear -eq "0") {
        return $true
    }

    return $cacheYear -eq [string]$DetectedMetadata.Year
}

function Get-FuzzyMatchScore {
    param([string]$String1, [string]$String2)

    $String1 = $String1.ToLower().Trim()
    $String2 = $String2.ToLower().Trim()

    if ([string]::IsNullOrEmpty($String1) -or [string]::IsNullOrEmpty($String2)) { return 0 }
    if ($String1 -eq $String2) { return 100 }

    if ($String1.Contains($String2) -or $String2.Contains($String1)) {
        $minLen = [Math]::Min($String1.Length, $String2.Length)
        $maxLen = [Math]::Max($String1.Length, $String2.Length)
        if ($maxLen -gt 0 -and ($minLen / $maxLen) -ge 0.75) {
            return 90
        }
    }

    $commonChars = 0
    $maxLen = [Math]::Max($String1.Length, $String2.Length)

    $chars1 = @{}
    $chars2 = @{}

    foreach ($char in $String1.ToCharArray()) {
        if ($chars1[$char]) { $chars1[$char]++ } else { $chars1[$char] = 1 }
    }
    foreach ($char in $String2.ToCharArray()) {
        if ($chars2[$char]) { $chars2[$char]++ } else { $chars2[$char] = 1 }
    }

    foreach ($char in $chars1.Keys) {
        if ($chars2[$char]) {
            $commonChars += [Math]::Min($chars1[$char], $chars2[$char])
        }
    }

    $similarity = ($commonChars / $maxLen) * 100
    return [Math]::Round($similarity, 0)
}

function Resolve-RatingKey {
    param(
        [string]$Title,
        [hashtable]$DetectedMetadata,
        [string]$BasePath = ".",
        [string]$ProjectRoot = ""
    )

    if ($DetectedMetadata -and $DetectedMetadata.ratingKey) {
        return [string]$DetectedMetadata.ratingKey
    }

    if ($script:PlexCache.Count -eq 0) {
        return ""
    }

    $searchTitle = Get-SearchTitle -Title $Title -Type $DetectedMetadata.Type
    $searchKey = Normalize-CacheKey $searchTitle

    $aliasMatch = Find-CacheItemByKey -SearchKey $searchKey
    if ($aliasMatch) {
        return [string]$aliasMatch.ratingKey
    }

    return ""
}

function Get-PosterByCache {
    param(
        [string]$Title,
        [string]$RatingKey = "",
        [hashtable]$DetectedMetadata = $null
    )

    if ($script:PlexCache.Count -eq 0) {
        return @{ found = $false; method = "cache_empty"; score = 0; ratingKey = ""; title = "" }
    }

    if (-not [string]::IsNullOrEmpty($RatingKey)) {
        $ratingKeyMatch = $script:PlexCache | Where-Object { [string]$_.ratingKey -eq [string]$RatingKey } | Select-Object -First 1
        if ($ratingKeyMatch -and $ratingKeyMatch.poster_url) {
            $searchKeyForRating = Normalize-CacheKey $Title
            $titleMatches = ($ratingKeyMatch.titulo_normalizado -eq $searchKeyForRating) -or
                (Test-CacheItemKeyMatch -Item $ratingKeyMatch -SearchKey $searchKeyForRating)
            if ($titleMatches -and (Test-CacheItemYearMatch -CacheItem $ratingKeyMatch -DetectedMetadata $DetectedMetadata)) {
                return @{
                    found     = $true
                    method    = "cache_ratingkey_exact"
                    url       = $ratingKeyMatch.poster_url
                    title     = $ratingKeyMatch.titulo_original
                    score     = 100
                    ratingKey = $ratingKeyMatch.ratingKey
                }
            }
        }
    }

    $searchKey = Normalize-CacheKey $Title

    $aliasMatch = Find-CacheItemByKey -SearchKey $searchKey
    if ($aliasMatch -and $aliasMatch.poster_url -and (Test-CacheItemYearMatch -CacheItem $aliasMatch -DetectedMetadata $DetectedMetadata)) {
        $method = if ($aliasMatch.titulo_normalizado -eq $searchKey) { "cache_exact" } else { "cache_alias" }
        return @{
            found     = $true
            method    = $method
            url       = $aliasMatch.poster_url
            title     = $aliasMatch.titulo_original
            score     = 100
            ratingKey = $aliasMatch.ratingKey
        }
    }

    $bestMatch = $null
    $bestScore = 0

    foreach ($item in $script:PlexCache) {
        if (-not (Test-CacheItemYearMatch -CacheItem $item -DetectedMetadata $DetectedMetadata)) {
            continue
        }

        $score = Get-FuzzyMatchScore $searchKey $item.titulo_normalizado
        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestMatch = $item
        }
    }

    if ($bestScore -ge 85 -and $bestMatch -and $bestMatch.poster_url) {
        return @{
            found     = $true
            method    = "cache_fuzzy"
            url       = $bestMatch.poster_url
            title     = $bestMatch.titulo_original
            score     = $bestScore
            ratingKey = $bestMatch.ratingKey
        }
    }

    return @{ found = $false; method = "cache_no_match"; score = $bestScore; ratingKey = ""; title = "" }
}
