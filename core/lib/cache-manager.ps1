# ==================================================
# CACHE-MANAGER.PS1 - Gestión de Caché Plex
# ==================================================

$script:PlexCacheLoaded = $false
$script:PlexCache = @()

function Initialize-PlexCache {
    param([bool]$SkipDelay = $false, [string]$BasePath = ".")
    
    if ($script:PlexCacheLoaded) {
        return
    }
    
    Write-Log "Inicializando caché..."
    
    # PASO 1: Intentar cargar desde config/plex_cache.json
    $cacheFilePath = Join-Path $BasePath "config\plex_cache.json"
    $allItems = @()
    $cacheLoaded = $false
    
    if (Test-Path $cacheFilePath) {
        try {
            Write-Log "Leyendo caché persistente desde: $cacheFilePath"
            $cacheData = Get-Content $cacheFilePath -Encoding UTF8 | ConvertFrom-Json
            
            if ($cacheData.cache -and $cacheData.cache.Count -gt 0) {
                foreach ($item in $cacheData.cache) {
                    $allItems += @{
                        titulo_normalizado = $item.titulo_normalizado
                        titulo_original    = $item.titulo_original
                        ratingKey          = $item.ratingKey
                        tipo               = $item.tipo
                        poster_url         = $item.poster_url
                        year               = $item.year
                    }
                }
                $cacheLoaded = $true
                Write-Log "Caché cargado desde archivo: $($cacheData.cache.Count) títulos"
            }
        }
        catch {
            Write-Log "Advertencia: Error leyendo caché: $($_.Exception.Message)" -Level "WARNING"
        }
    }
    
    # Asignar caché global
    $script:PlexCache = $allItems
    $script:PlexCacheLoaded = $true
}

function Add-ToCache {
    param(
        [string]$Title,
        [string]$RatingKey,
        [string]$Type,
        [string]$PosterUrl,
        [int]$Year,
        [string]$BasePath = "."
    )
    
    $normalizedTitle = $Title.ToLower() -replace '[^a-z0-9]', ''
    
    $exists = $script:PlexCache | Where-Object { 
        $_.titulo_normalizado -eq $normalizedTitle -and $_.ratingKey -eq $RatingKey 
    }
    
    if ($exists) {
        return
    }
    
    $newItem = @{
        titulo_normalizado = $normalizedTitle
        titulo_original    = $Title
        ratingKey          = $RatingKey
        tipo               = $Type
        poster_url         = $PosterUrl
        year               = $Year
    }
    
    $script:PlexCache += $newItem
    
    try {
        $cacheFilePath = Join-Path $BasePath "config\plex_cache.json"
        
        if (Test-Path $cacheFilePath) {
            $cacheData = Get-Content $cacheFilePath -Encoding UTF8 | ConvertFrom-Json
            $cacheData.cache += $newItem
            $cacheData.totalItems = $cacheData.cache.Count
            $cacheData.lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            
            $cacheJson = $cacheData | ConvertTo-Json -Depth 5
            $cacheJson | Set-Content -Path $cacheFilePath -Encoding UTF8 -Force
            
            Write-Log "Caché actualizado: Nuevo título '$Title' agregado"
        }
    }
    catch {
        Write-Log "No se pudo actualizar caché: $($_.Exception.Message)" -Level "WARNING"
    }
}

function Get-FuzzyMatchScore {
    param([string]$String1, [string]$String2)
    
    $String1 = $String1.ToLower().Trim()
    $String2 = $String2.ToLower().Trim()
    
    if ([string]::IsNullOrEmpty($String1) -or [string]::IsNullOrEmpty($String2)) { return 0 }
    if ($String1 -eq $String2) { return 100 }
    if ($String1.Contains($String2) -or $String2.Contains($String1)) { return 90 }
    
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
        [string]$BasePath = "."
    )

    if ($DetectedMetadata -and $DetectedMetadata.ratingKey) {
        return [string]$DetectedMetadata.ratingKey
    }

    $searchTitle = Get-SearchTitle -Title $Title -Type $DetectedMetadata.Type
    $searchKey = $searchTitle.ToLower().Trim() -replace '[^a-z0-9]', ''

    $fallbackFile = Join-Path $BasePath "config\legacy_series_fallback.json"
    if (Test-Path $fallbackFile) {
        try {
            $fallback = Get-Content $fallbackFile -Encoding UTF8 | ConvertFrom-Json
            foreach ($serie in $fallback.series) {
                $fbClean = $serie.title.ToLower() -replace '[^a-z0-9]', ''
                if ($searchKey -eq $fbClean -or $searchKey.Contains($fbClean) -or $fbClean.Contains($searchKey)) {
                    return [string]$serie.ratingKey
                }
                if ($serie.localTitle) {
                    $localClean = $serie.localTitle.ToLower() -replace '[^a-z0-9]', ''
                    if ($searchKey -eq $localClean -or $searchKey.Contains($localClean)) {
                        return [string]$serie.ratingKey
                    }
                }
            }
        }
        catch {
            Write-Log "Advertencia: Error leyendo legacy fallback: $($_.Exception.Message)" -Level "WARNING"
        }
    }

    if ($script:PlexCache.Count -eq 0) {
        return ""
    }

    $exactMatch = $script:PlexCache | Where-Object { $_.titulo_normalizado -eq $searchKey } | Select-Object -First 1
    if ($exactMatch) {
        return [string]$exactMatch.ratingKey
    }

    $bestMatch = $null
    $bestScore = 0
    foreach ($item in $script:PlexCache) {
        $score = Get-FuzzyMatchScore $searchKey $item.titulo_normalizado
        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestMatch = $item
        }
    }

    if ($bestScore -ge 85 -and $bestMatch) {
        return [string]$bestMatch.ratingKey
    }

    return ""
}

function Get-PosterByCache {
    param(
        [string]$Title,
        [string]$RatingKey = ""
    )
    
    if ($script:PlexCache.Count -eq 0) { 
        return @{ found = $false; method = "cache_empty"; score = 0; ratingKey = "" }
    }
    
    # ESTRATEGIA 1: Búsqueda por RatingKey (0ms, identificador único)
    if (-not [string]::IsNullOrEmpty($RatingKey)) {
        $ratingKeyMatch = $script:PlexCache | Where-Object { [string]$_.ratingKey -eq [string]$RatingKey } | Select-Object -First 1
        if ($ratingKeyMatch -and $ratingKeyMatch.poster_url) {
            Write-Log "Poster encontrado en caché (método: cache_ratingkey_exact, score: 100%)"
            return @{
                found = $true
                method = "cache_ratingkey_exact"
                url = $ratingKeyMatch.poster_url
                title = $ratingKeyMatch.titulo_original
                score = 100
                ratingKey = $ratingKeyMatch.ratingKey
            }
        }
    }
    
    $searchKey = $Title.ToLower().Trim() -replace '[^a-z0-9]', ''
    
    # ESTRATEGIA 2: Búsqueda exacta por título normalizado
    $exactMatch = $script:PlexCache | Where-Object { $_.titulo_normalizado -eq $searchKey } | Select-Object -First 1
    if ($exactMatch -and $exactMatch.poster_url) {
        return @{ 
            found = $true
            method = "cache_exact"
            url = $exactMatch.poster_url
            title = $exactMatch.titulo_original
            score = 100
            ratingKey = $exactMatch.ratingKey
        }
    }
    
    # ESTRATEGIA 3: Búsqueda fuzzy por título
    $bestMatch = $null
    $bestScore = 0
    
    foreach ($item in $script:PlexCache) {
        $score = Get-FuzzyMatchScore $searchKey $item.titulo_normalizado
        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestMatch = $item
        }
    }
    
    if ($bestScore -ge 85 -and $bestMatch -and $bestMatch.poster_url) {
        return @{
            found = $true
            method = "cache_fuzzy"
            url = $bestMatch.poster_url
            title = $bestMatch.titulo_original
            score = $bestScore
            ratingKey = $bestMatch.ratingKey
        }
    }
    
    return @{ found = $false; method = "cache_no_match"; score = $bestScore; ratingKey = "" }
}
