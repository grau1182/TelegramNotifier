param (
    [string]$TorrentName,
    [string]$ContentPath,
    [switch]$TestMode = $true,
    [string]$TorrentType = "Desconocido",
    [string]$ResultsFolder = ""
)

# ==================================================
# CONFIGURACION
# ==================================================

$BotToken = "8755898341:AAFSxCy9zjYS_rLl-kFpVPCmJ3V2XLjKjYg"
$ChatID   = "-1004350117652"

$BasePath = "C:\Users\grau_\Downloads\TelegramNotifier"

$OverrideFile = Join-Path $BasePath "title_overrides.json"

$LogFolder = Join-Path $BasePath ".\test\logs"
$LogFile   = Join-Path $LogFolder "TelegramNotifier_Test.log"

# ========================================
# PLEX
# ========================================

$PlexUrl   = "http://127.0.0.1:32400"
$PlexToken = "Yt-aqViZD-ydpysRvGyP"

# ========================================
# TEST CAPTURE (GLOBAL VARIABLES)
# ========================================

if ($TestMode) {
    $script:TestResults = @{
        torrents = @()
    }
    $script:PlexSearchLog = @()
    $script:SizeError = $null
    $script:PlexCacheLoaded = $false
    $script:PlexCache = @()
    
    # Usar ResultsFolder parametro si se proporciona, sino usar default
    if ([string]::IsNullOrEmpty($ResultsFolder)) {
        $script:ResultsFolder = Join-Path $BasePath "test\results"
    } else {
        $script:ResultsFolder = $ResultsFolder
    }
    
    if (-not (Test-Path $script:ResultsFolder)) {
        New-Item -ItemType Directory -Path $script:ResultsFolder -Force | Out-Null
    }
}

# ==================================================
# LOG
# ==================================================

function Rotate-Log {

    if(Test-Path $LogFile){

        $SizeMB = (Get-Item $LogFile).Length / 1MB

        if($SizeMB -ge 5){

            $Date = Get-Date -Format "yyyyMMdd_HHmmss"
            
            Rename-Item `
                -Path $LogFile `
                -NewName "TelegramNotifier_$Date.log"
        }
    }
}

function Write-Log {

    param([string]$Text)
	
	# En TestMode, solo registrar en memoria, no en archivo
	if ($TestMode) {
		return
	}
	
	Rotate-Log

    try {

        if (!(Test-Path $LogFolder)) {
            New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        Add-Content `
            -Path $LogFile `
            -Value "[$Timestamp] $Text"

    }
    catch {}
}

# ==================================================
# OVERRIDES
# ==================================================

function Load-Overrides {

    if(Test-Path $OverrideFile){

        return (
            Get-Content `
                $OverrideFile `
                -Raw `
                -Encoding UTF8
        ) | ConvertFrom-Json

    }

    return $null
}

# ==================================================
# NORMALIZACION
# ==================================================

function Normalize-Name {

    param([string]$Name)

    $Name = $Name.ToLower()

    $Name = $Name -replace '\.torrent$',''
    $Name = $Name -replace '\.mkv$',''
    $Name = $Name -replace '\.mp4$',''
    $Name = $Name -replace '\.avi$',''

    $Name = $Name -replace '[\._ ]+','-'

    $Name = $Name -replace '-+','-'

    $Name = $Name.Trim('-')

    return $Name
}

# ==================================================
# RESOLUCION
# ==================================================

function Get-Resolution {

    param([string]$Name)

    if($Name -match '2160p'){ return '2160p' }
    if($Name -match '1080p'){ return '1080p' }
    if($Name -match '720p'){ return '720p' }
    if($Name -match '480p'){ return '480p' }

    return 'Desconocida'
}

# ==================================================
# TAMAÑO
# ==================================================

function Get-SizeGB {

    param([string]$Path)
    $Path = $Path.Trim('"')

    try {

        $Exists = Test-Path -LiteralPath $Path

        if($Exists){

            $Item = Get-Item -LiteralPath $Path
			
            if($Item -is [System.IO.DirectoryInfo]){

                $Size =
                    (Get-ChildItem -LiteralPath $Path -Recurse -File |
                    Measure-Object Length -Sum).Sum

            }
            else {

                $Size = $Item.Length

            }

            return [math]::Round(($Size / 1GB),1)

        }

    }
    catch {

        Write-Log "Error calculando tamaño: $($_.Exception.Message)"

    }

    return 0
}

# ==================================================
# EPISODIOS
# ==================================================

function Count-Episodes {

    param([string]$Path)

    try {

        if(Test-Path $Path){

            return (
                Get-ChildItem $Path -Recurse -File |
                Where-Object {
                    $_.Extension.ToLower() -in @(
                        ".mkv",
                        ".mp4",
                        ".avi"
                    )
                }
            ).Count

        }

    }
    catch {}

    return 0
}

# ==================================================
# TITULOS
# ==================================================

function Convert-Title {

    param([string]$Title)

    $Title = $Title -replace '-',' '

    $Words = $Title.Split(' ')

    $Output = @()

    foreach($Word in $Words){

        if([string]::IsNullOrWhiteSpace($Word)){
            continue
        }

        if($Word -match '^[ivxlcdm]+$'){
            $Output += $Word.ToUpper()
            continue
        }

        $Output += (
            $Word.Substring(0,1).ToUpper() +
            $Word.Substring(1).ToLower()
        )
    }

    $Title = $Output -join ' '

    $Overrides = Load-Overrides

    if($Overrides){

        foreach($Property in $Overrides.PSObject.Properties){

            if($Title.ToLower() -eq $Property.Name){

                return $Property.Value

            }

        }

    }

    return $Title
}

# ==================================================
# LIMPIEZA
# ==================================================

function Get-CleanName {

    param([string]$Name)

    $Name = Normalize-Name $Name

    $Name = $Name -replace '^pack-',''

    $Name = $Name -replace '(2160p|1080p|720p|480p).*',''

    $Name = $Name.Trim('-')

    return $Name
}

# ==================================================
# PATTERN DETECTION & CONFIDENCE
# ==================================================

function Get-PatternDetected {
    param([string]$CleanName)
    
    if ($CleanName -match '^(.*?)-s(\d{1,2})e(\d{1,2})') {
        return "EPISODIO_SIMPLE"
    }
    elseif ($CleanName -match '^(.*?)-s(\d{1,2})(?:-|$)') {
        return "TEMPORADA"
    }
    elseif ($CleanName -match '^(.*?)[-\s\(](19\d{2}|20\d{2})') {
        return "PELICULA_CON_AÑO"
    }
    else {
        return "SIN_PATRON"
    }
}

function Get-TechnicalTags {
    param([string]$NormalizedName)
    
    $tags = @()
    
    if ($NormalizedName -match "(2160p|1080p|720p|480p)") {
        $tags += "RESOLUCION"
    }
    if ($NormalizedName -match "(web-dl|bdrip|bdremux|hevc|h264|x264|x265|hdrip)") {
        $tags += "CODEC"
    }
    if ($NormalizedName -match "(dual|dts|aac|dd5|true-hd|atmos|5\.1|7\.1)") {
        $tags += "AUDIO"
    }
    
    return $tags
}

function Get-ParseConfidence {
    param(
        [string]$DetectedType,
        [string]$CleanName,
        [string]$Pattern
    )
    
    if ($DetectedType -eq "EPISODIO") {
        if ($CleanName -match '^(.*?)-s(\d{1,2})e(\d{1,2})') {
            return 95
        }
        return 50
    }
    elseif ($DetectedType -eq "TEMPORADA") {
        if ($CleanName -match '^(.*?)-s(\d{1,2})(?:-|$)') {
            return 85
        }
        return 50
    }
    elseif ($DetectedType -eq "PELICULA") {
        if ($CleanName -match '^(.*?)[-\s\(](19\d{2}|20\d{2})') {
            return 80
        }
        return 60
    }
    else {
        return 0
    }
}

# ==================================================
# PLEX CACHE - FASE 0 OPTIMIZADA
# ==================================================

function Initialize-PlexCache {
    param([bool]$SkipDelay = $false)
    
    # Flag check: si ya está cargado, saltar
    if ($script:PlexCacheLoaded) {
        return
    }
    
    Write-Host "Inicializando caché..." -ForegroundColor Cyan
    
    # PASO 1: Intentar cargar desde recursos/plex_cache.json (PERSISTENTE)
    $cacheFilePath = Join-Path (Split-Path $PSScriptRoot -Parent) "recursos\plex_cache.json"
    $allItems = @()
    $cacheLoaded = $false
    
    if (Test-Path $cacheFilePath) {
        try {
            Write-Host "Leyendo caché persistente desde: $cacheFilePath" -ForegroundColor Gray
            $cacheData = Get-Content $cacheFilePath -Encoding UTF8 | ConvertFrom-Json
            
            if ($cacheData.cache -and $cacheData.cache.Count -gt 0) {
                # Usar caché existente
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
                Write-Host "Caché cargado desde archivo: $($cacheData.cache.Count) títulos" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Advertencia: Error leyendo caché local: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # PASO 2: Si no se cargó caché, obtener desde Plex API
    if (-not $cacheLoaded) {
        Write-Host "Caché no disponible. Cargando desde Plex API..." -ForegroundColor Cyan
        
        # Solo hacer Start-Sleep en producción (SkipDelay = $false = TestMode)
        if (-not $SkipDelay) {
            Write-Host "Esperando 5 segundos para que Plex se estabilice..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        } else {
            Write-Host "[TestMode] Saltando Start-Sleep" -ForegroundColor Yellow
        }
    }
    
    $loadedCount = $allItems.Count
    $timestamp = Get-Date
    
    # PASO 3: Cargar desde Plex API solo si no hay caché
    if (-not $cacheLoaded) {
        # Cargar Sección 1: Películas y Sección 2: Series
        foreach ($sectionId in @(1, 2)) {
            try {
                $url = "$PlexUrl/library/sections/$sectionId/all?X-Plex-Token=$PlexToken"
                Write-Host "Cargando sección $sectionId..." -ForegroundColor Gray
                
                $response = Invoke-RestMethod -Uri $url -TimeoutSec 30 -ErrorAction Stop
                
                # Plex retorna items en Video (películas) o en otra propiedad según tipo
                $items = $response.MediaContainer.Video
                if (-not $items -and $response.MediaContainer.Directory) {
                    $items = $response.MediaContainer.Directory
                }
                
                if ($items) {
                    # Convertir a array si es un objeto único
                    if ($items -isnot [array]) {
                        $items = @($items)
                    }
                    
                    foreach ($item in $items) {
                        $normalized = $item.title.ToLower() -replace '[^a-z0-9]', ''
                        
                        if ($normalized) {
                            $posterUrl = if ($item.thumb) { 
                                "$PlexUrl$($item.thumb)?X-Plex-Token=$PlexToken" 
                            } else { 
                                $null 
                            }
                            
                            $allItems += @{
                                titulo_normalizado = $normalized
                                titulo_original    = $item.title
                                ratingKey          = $item.ratingKey
                                tipo               = if ($item.type -eq "show") { "SERIE" } else { "PELICULA" }
                                poster_url         = $posterUrl
                                year               = $item.year
                            }
                            $loadedCount++
                        }
                    }
                }
            }
            catch {
                Write-Host "Advertencia: Error en sección $sectionId : $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        # PASO 4: Guardar caché en recursos/plex_cache.json
        $cacheObject = @{
            version = "1.0"
            lastUpdated = $timestamp.ToString("yyyy-MM-ddTHH:mm:ssZ")
            description = "Caché persistente de Plex - Actualizado automáticamente"
            totalItems = $allItems.Count
            cache = $allItems
        }
        
        try {
            $cacheJson = $cacheObject | ConvertTo-Json -Depth 5
            $cacheJson | Set-Content -Path $cacheFilePath -Encoding UTF8 -Force
            Write-Host "Caché guardado en: $cacheFilePath" -ForegroundColor Green
        }
        catch {
            Write-Host "Advertencia: No se pudo guardar caché: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # Asignar caché global
    $script:PlexCache = $allItems
    $script:PlexCacheLoaded = $true
    
    Write-Host "Caché inicializado: $loadedCount títulos cargados en $(((Get-Date) - $timestamp).TotalSeconds) segundos" -ForegroundColor Green
}

# ==================================================
# ACTUALIZAR CACHE CON NUEVOS TITULOS ENCONTRADOS
# ==================================================

function Add-ToCache {
    param(
        [string]$Title,
        [string]$RatingKey,
        [string]$Type,
        [string]$PosterUrl,
        [int]$Year
    )
    
    # Normalizar título igual que en Initialize-PlexCache
    $normalizedTitle = $Title.ToLower() -replace '[^a-z0-9]', ''
    
    # Verificar si ya existe en caché
    $exists = $script:PlexCache | Where-Object { $_.titulo_normalizado -eq $normalizedTitle -and $_.ratingKey -eq $RatingKey }
    if ($exists) {
        return  # Ya existe, no agregar duplicado
    }
    
    # Agregar a caché en memoria
    $newItem = @{
        titulo_normalizado = $normalizedTitle
        titulo_original    = $Title
        ratingKey          = $RatingKey
        tipo               = $Type
        poster_url         = $PosterUrl
        year               = $Year
    }
    
    $script:PlexCache += $newItem
    
    # Actualizar archivo de caché
    try {
        $cacheFilePath = Join-Path (Split-Path $PSScriptRoot -Parent) "recursos\plex_cache.json"
        
        if (Test-Path $cacheFilePath) {
            $cacheData = Get-Content $cacheFilePath -Encoding UTF8 | ConvertFrom-Json
            
            # Agregar nuevo item
            $cacheData.cache += $newItem
            $cacheData.totalItems = $cacheData.cache.Count
            $cacheData.lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            
            # Guardar
            $cacheJson = $cacheData | ConvertTo-Json -Depth 5
            $cacheJson | Set-Content -Path $cacheFilePath -Encoding UTF8 -Force
            
            Write-Log "✓ Caché actualizado: Nuevo título '$Title' agregado (ratingKey: $RatingKey)"
        }
    }
    catch {
        Write-Log "⚠ No se pudo actualizar caché: $($_.Exception.Message)"
    }
}

function Get-FuzzyMatchScore {
    param([string]$String1, [string]$String2)
    
    $String1 = $String1.ToLower().Trim()
    $String2 = $String2.ToLower().Trim()
    
    if ([string]::IsNullOrEmpty($String1) -or [string]::IsNullOrEmpty($String2)) { return 0 }
    if ($String1 -eq $String2) { return 100 }
    if ($String1.Contains($String2) -or $String2.Contains($String1)) { return 90 }
    
    # Algoritmo simple: contar subcadenas comunes
    $commonChars = 0
    $maxLen = [Math]::Max($String1.Length, $String2.Length)
    
    # Contar caracteres que aparecen en ambas cadenas
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

function Get-PosterByCache {
    param([string]$Title)
    
    if ($script:PlexCache.Count -eq 0) { 
        return @{ found = $false; method = "cache_empty"; score = 0 }
    }
    
    $searchKey = $Title.ToLower().Trim() -replace '[^a-z0-9]', ''
    
    # PASO 1: Búsqueda exacta
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
    
    # PASO 2: Búsqueda fuzzy (85%+)
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
    
    return @{ found = $false; method = "cache_no_match"; score = $bestScore }
}

function Normalize-PlexQuery {
    param([string]$Text)
    return $Text.ToLower().Replace(" ","-").Replace(".","").Replace("ñ","n").Replace("á","a").Replace("é","e").Replace("í","i").Replace("ó","o").Replace("ú","u").Trim('-')
}

function Normalize-PlexTitle {
    param([string]$Title)
    return $Title.ToLower().Replace(" ","-").Replace(".","").Replace("ñ","n").Replace("á","a").Replace("é","e").Replace("í","i").Replace("ó","o").Replace("ú","u").Trim('-')
}

function Normalize-FilePath {
    param([string]$Path)
    return $Path.ToLower().Trim().Replace("/","\")
}

function Get-PlexItemFilePath {
    param($Item)
    if ($Item.Media.Part.file) { return Normalize-FilePath $Item.Media.Part.file }
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
    } elseif ($PlexFilePath -and $PlexFilePath.StartsWith($NormalizedContentPath + "\")) {
        $Score += 70
    }

    $NormalizedPlexTitle = Normalize-PlexTitle $PlexItem.title
    $NormalizedDetectedTitle = Normalize-PlexTitle $DetectedMetadata.Title

    # Coincidencia de título
    if ($NormalizedPlexTitle -eq $NormalizedDetectedTitle) {
        $Score += 50
    } elseif ($NormalizedPlexTitle.Contains($NormalizedDetectedTitle)) {
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

function Get-PlexPoster {
    param(
        [string]$Title,
        [string]$ContentPath,
        [hashtable]$DetectedMetadata
    )

    Write-Log "Iniciando busqueda de poster para '$($DetectedMetadata.Title)' (Tipo: $($DetectedMetadata.Type))"

    $BestPosterUrl = $null
    $HighestScore = 0
    $MatchMethod = "none"
    $BestItem = $null  # Para guardar el item encontrado
    $script:PlexSearchLog = @()

    # FASE 0 OPTIMIZADA: Búsqueda en caché (1-5ms)
    if (-not $script:PlexCacheLoaded) {
        Initialize-PlexCache -SkipDelay $TestMode
    }
    
    $cacheResult = Get-PosterByCache $Title
    if ($cacheResult.found) {
        Write-Log "Poster encontrado en caché (método: $($cacheResult.method), score: $($cacheResult.score)%)"
        $script:PlexSearchLog += @{
            method = $cacheResult.method
            title = $cacheResult.title
            score = $cacheResult.score
            ratingKey = $cacheResult.ratingKey
        }
        return $cacheResult.url
    }

    # FALLBACK: Si no está en caché, hacer búsqueda API (solo si es necesario)
    Write-Log "Poster NO encontrado en caché (método: $($cacheResult.method)). Intentando API..."
    
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
            [xml]$Result = Invoke-RestMethod -Uri $PlexSearchUrl -Method Get
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

            $searchLogEntry = @{
                search_type = $SearchType.Description
                query       = $Query
                items_count = $PlexItems.Count
                items       = @()
                timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            }

            foreach ($Item in $PlexItems) {
                $CurrentScore = Get-PlexMatchScore -PlexItem $Item -DetectedMetadata $DetectedMetadata -ContentPath $ContentPath
                Write-Log "  - Item Plex '$($Item.title)' (Ruta: $(Get-PlexItemFilePath $Item)): Score $CurrentScore"

                $searchLogEntry.items += @{
                    title   = $Item.title
                    year    = $Item.year
                    score   = $CurrentScore
                    type    = if ($Item.Video) { "Video" } elseif ($Item.Directory) { "Directory" } else { "Metadata" }
                }

                if ($CurrentScore -gt $HighestScore) {
                    $Poster = Get-PlexPosterFromItem $Item
                    if ($Poster) {
                        $HighestScore = $CurrentScore
                        $BestPosterUrl = $Poster
                        $BestItem = $Item  # Guardar el item para Add-ToCache
                        $MatchMethod = $SearchType.Description
                        Write-Log "    Nuevo mejor poster encontrado con score $($HighestScore): $($BestPosterUrl)"
                    }
                }
            }

            $script:PlexSearchLog += $searchLogEntry

        }
        catch {
            Write-Log "Error durante la busqueda Plex ($($SearchType.Description)): $($_.Exception.Message)"
            $script:PlexSearchLog += @{
                search_type = $SearchType.Description
                error       = $_.Exception.Message
                timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            }
        }
    }

    if ($BestPosterUrl) {
        Write-Log "Poster final seleccionado (Score: $HighestScore, Método: $MatchMethod): $BestPosterUrl"
        
        # 🔄 ACTUALIZAR CACHÉ SI ES NUEVO
        if ($BestItem -and $BestItem.ratingKey -and $BestItem.title) {
            $itemType = if ($BestItem.type -eq "show") { "SERIE" } else { "PELICULA" }
            Add-ToCache -Title $BestItem.title `
                        -RatingKey $BestItem.ratingKey `
                        -Type $itemType `
                        -PosterUrl $BestPosterUrl `
                        -Year $BestItem.year
        }
        
        return $BestPosterUrl
    }

    Write-Log "No se encontro ningun poster adecuado en Plex."
    return $null
}

# ==================================================
# INICIO
# ==================================================

$TimestampInicio = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"

Write-Log "======================================="

Write-Log "Torrent recibido: $TorrentName"
Write-Log "Ruta recibida: $ContentPath"

$OriginalName =
    [System.IO.Path]::GetFileNameWithoutExtension($TorrentName)

$NormalizedName = Normalize-Name $OriginalName

$CleanName = Get-CleanName $OriginalName

$Resolution = Get-Resolution $NormalizedName

$SizeGB = Get-SizeGB $ContentPath

$SizeError = if ($SizeGB -eq 0 -and (Test-Path $ContentPath)) { "No se pudo calcular" } else { $null }

Write-Log "Nombre normalizado: $NormalizedName"
Write-Log "Nombre limpio: $CleanName"
Write-Log "Resolucion: $Resolution"
Write-Log "Tamaño: $SizeGB GB"

$PatternDetected = Get-PatternDetected $CleanName
$TechnicalTags = Get-TechnicalTags $NormalizedName
$ContentExists = Test-Path $ContentPath

Write-Log "Patron detectado: $PatternDetected"
Write-Log "Tags tecnicos: $($TechnicalTags -join ', ')"

$Message = ""
$DetectedMetadata = @{ Title = ""; Year = $null; Season = $null; Episode = $null; Type = "Desconocido" }

# ==================================================
# EPISODIO
# ==================================================

if($CleanName -match '^(.*?)-s(\d{1,2})e(\d{1,2})(?:-|$)'){

    $Title   = Convert-Title $Matches[1]
    $Season  = [int]$Matches[2]
    $Episode = [int]$Matches[3]

    $DetectedMetadata.Title = $Title
    $DetectedMetadata.Season = $Season
    $DetectedMetadata.Episode = $Episode
    $DetectedMetadata.Type = "EPISODIO"

    Write-Log "Tipo detectado: EPISODIO"

$Message = "EPISODIO DESCARGADO`n`n$Title`nT$($Season.ToString('D2')) - E$($Episode.ToString('D2'))`n`n$Resolution`n$SizeGB GB"
}

# ==================================================
# TEMPORADA
# ==================================================

elseif($CleanName -match '^(.*?)-s(\d{1,2})(?:-|$)'){

    $Title  = Convert-Title $Matches[1]
    $Season = [int]$Matches[2]

    $EpisodeCount = Count-Episodes $ContentPath

    $DetectedMetadata.Title = $Title
    $DetectedMetadata.Season = $Season
    $DetectedMetadata.Type = "TEMPORADA"

    Write-Log "Tipo detectado: TEMPORADA"
    Write-Log "Episodios detectados: $EpisodeCount"

$Message = @"
TEMPORADA DESCARGADA

$Title
Temporada $Season

$EpisodeCount episodios
$Resolution
$SizeGB GB
"@
}

# ==================================================
# PELICULA
# ==================================================

elseif(
    $CleanName -match '^(.*?)[-\s\(](19\d{2}|20\d{2})[\)\-]?'
){

    $Title = $Matches[1]

    $Title = $Title -replace '\[.*\]',''
    $Title = $Title.Trim()

    $Title = Convert-Title $Title

    $Year  = $Matches[2]

    $DetectedMetadata.Title = $Title
    $DetectedMetadata.Year = $Year
    $DetectedMetadata.Type = "PELICULA"

    Write-Log "Tipo detectado: PELICULA"

$Message = @"
PELICULA DESCARGADA

$Title ($Year)

$Resolution
$SizeGB GB
"@
}

# ==================================================
# DESCONOCIDO
# ==================================================

else {

    $Title = Convert-Title $CleanName

    $DetectedMetadata.Title = $Title
    $DetectedMetadata.Type = "DESCONOCIDO"

    Write-Log "Tipo detectado: DESCONOCIDO"

    $Message = @"
Torrent no clasificado

$Title

$Resolution
$SizeGB GB
"@
}

Write-Log "Mensaje generado:"
Write-Log $Message

$ParseConfidence = Get-ParseConfidence -DetectedType $DetectedMetadata.Type -CleanName $CleanName -Pattern $PatternDetected

$PosterUrl =
    Get-PlexPoster `
        $Title `
        $ContentPath `
        $DetectedMetadata

if($PosterUrl){
    Write-Log "Poster URL: $PosterUrl"
}

$PosterBytes = 0
if ($PosterUrl) {
    try {
        $TempPoster = Join-Path $env:TEMP "telegram_poster.jpg"
        Invoke-WebRequest -Uri $PosterUrl -OutFile $TempPoster -ErrorAction SilentlyContinue
        if (Test-Path $TempPoster) {
            $PosterBytes = (Get-Item $TempPoster).Length
        }
    }
    catch { }
}

$PlexNoEncontro = $false
if (-not $PosterUrl -and $ContentExists) {
    $PlexNoEncontro = $true
    Write-Log "FALSO NEGATIVO PLEX: Contenido existe en ruta pero no encontrado en Plex"
}

# ==================================================
# TEST MODE: Capturar datos
# ==================================================

if ($TestMode) {
    $TimestampFin = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    
    $testRecord = @{
        torrent_name         = $TorrentName
        original_name        = $OriginalName
        normalized_name      = $NormalizedName
        clean_name           = $CleanName
        detected_type        = $DetectedMetadata.Type
        detected_title       = $DetectedMetadata.Title
        detected_season      = $DetectedMetadata.Season
        detected_episode     = $DetectedMetadata.Episode
        detected_year        = $DetectedMetadata.Year
        parse_confidence     = $ParseConfidence
        pattern_detected     = $PatternDetected
        technical_tags       = $TechnicalTags
        resolution           = $Resolution
        size_gb              = $SizeGB
        size_error           = $SizeError
        content_exists       = $ContentExists
        episode_count        = if ($DetectedMetadata.Type -eq "TEMPORADA") { Count-Episodes $ContentPath } else { $null }
        poster_found         = if ($PosterUrl) { $true } else { $false }
        poster_url           = $PosterUrl
        poster_bytes         = $PosterBytes
        plex_no_encontro     = $PlexNoEncontro
        plex_search_log      = $script:PlexSearchLog
        timestamp_inicio     = $TimestampInicio
        timestamp_fin        = $TimestampFin
    }
    
    $script:TestResults.torrents += $testRecord
}

# ==================================================
# TELEGRAM (Production)
# ==================================================

if (-not $TestMode) {
    try {

        if($PosterUrl){

            $TempPoster = Join-Path $env:TEMP "telegram_poster.jpg"

            Invoke-WebRequest `
                -Uri $PosterUrl `
                -OutFile $TempPoster

            Write-Log "Poster descargado: $TempPoster"
            Write-Log "Tamaño poster: $((Get-Item $TempPoster).Length)"

            curl.exe `
                -s `
                -X POST `
                "https://api.telegram.org/bot$BotToken/sendPhoto" `
                -F "chat_id=$ChatID" `
                -F "photo=@$TempPoster" `
                -F "caption=$Message" `
                -F "parse_mode=HTML" | Out-Null

            Remove-Item $TempPoster -Force -ErrorAction SilentlyContinue

        }
        else {

            Invoke-RestMethod `
                -Uri "https://api.telegram.org/bot$BotToken/sendMessage" `
                -Method Post `
                -Body @{
                    chat_id    = $ChatID
                    text       = $Message
                    parse_mode = "HTML"
                }

        }

        Write-Log "Envio Telegram OK"

    }
    catch {

        Write-Log "ERROR TELEGRAM"
        Write-Log $_.Exception.Message

    }
}
