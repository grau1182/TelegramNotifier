# ==================================================
# UTILITIES.PS1 - Funciones Generales de Utilidad
# ==================================================

function Remove-Accents {
    param([string]$Text)
    
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    
    $accents = @{
        'á' = 'a'; 'à' = 'a'; 'ä' = 'a'; 'â' = 'a'; 'ã' = 'a'; 'å' = 'a'
        'é' = 'e'; 'è' = 'e'; 'ë' = 'e'; 'ê' = 'e'
        'í' = 'i'; 'ì' = 'i'; 'ï' = 'i'; 'î' = 'i'
        'ó' = 'o'; 'ò' = 'o'; 'ö' = 'o'; 'ô' = 'o'; 'õ' = 'o'
        'ú' = 'u'; 'ù' = 'u'; 'ü' = 'u'; 'û' = 'u'
        'ñ' = 'n'; 'ç' = 'c'; '×' = 'x'
    }
    
    foreach ($accentChar in $accents.Keys) {
        $Text = $Text -replace [regex]::Escape($accentChar), $accents[$accentChar]
    }
    
    return $Text
}

function Normalize-Name {
    param([string]$Name)

    $Name = $Name.ToLower()
    $Name = Remove-Accents $Name
    $Name = $Name -replace '\.torrent$', ''
    $Name = $Name -replace '\.mkv$', ''
    $Name = $Name -replace '\.mp4$', ''
    $Name = $Name -replace '\.avi$', ''
    $Name = $Name -replace '[\._ ]+', '-'
    $Name = $Name -replace '-+', '-'
    $Name = $Name.Trim('-')

    return $Name
}

function Get-Resolution {
    param([string]$Name)

    if ($Name -match '2160p') { return '2160p' }
    if ($Name -match '1080p') { return '1080p' }
    if ($Name -match '720p') { return '720p' }
    if ($Name -match '480p') { return '480p' }

    return 'Desconocida'
}

function Get-SizeGB {
    param([string]$Path)
    
    $Path = $Path.Trim('"')

    try {
        $Exists = Test-Path -LiteralPath $Path

        if ($Exists) {
            $Item = Get-Item -LiteralPath $Path

            if ($Item -is [System.IO.DirectoryInfo]) {
                $Size = (Get-ChildItem -LiteralPath $Path -Recurse -File | Measure-Object Length -Sum).Sum
            }
            else {
                $Size = $Item.Length
            }

            return [math]::Round(($Size / 1GB), 1)
        }
    }
    catch {
        Write-Log "Error calculando tamaño: $($_.Exception.Message)" -Level "WARNING"
    }

    return 0
}

function Count-Episodes {
    param([string]$Path)

    try {
        if (Test-Path $Path) {
            return (
                Get-ChildItem $Path -Recurse -File |
                Where-Object {
                    $_.Extension.ToLower() -in @(".mkv", ".mp4", ".avi")
                }
            ).Count
        }
    }
    catch { }

    return 0
}

function Convert-Title {
    param([string]$Title)

    $Title = $Title -replace '-', ' '

    $Words = $Title.Split(' ')

    $Output = @()

    foreach ($Word in $Words) {
        if ([string]::IsNullOrWhiteSpace($Word)) {
            continue
        }

        if ($Word -match '^[ivxlcdm]+$') {
            $Output += $Word.ToUpper()
            continue
        }

        $Output += (
            $Word.Substring(0, 1).ToUpper() +
            $Word.Substring(1).ToLower()
        )
    }

    return ($Output -join ' ')
}

function Get-CleanName {
    param([string]$Name)

    $Name = Normalize-Name $Name
    $Name = $Name -replace '^pack-', ''
    $Name = $Name -replace '(2160p|1080p|720p|480p).*', ''
    $Name = $Name.Trim('-')

    return $Name
}

function Get-MovieTitleAndYear {
    param([string]$OriginalName)

    $result = @{
        Title = ""
        Year  = $null
        Found = $false
    }

    if ([string]::IsNullOrWhiteSpace($OriginalName)) {
        return $result
    }

    $work = $OriginalName

    if ($work -match '\((19\d{2}|20\d{2})\)') {
        $result.Year = $Matches[1]
        $work = $work -replace '\((19\d{2}|20\d{2})\)', ' '
        $result.Found = $true
    }

    if ($work -match '^([^\[]+)') {
        $work = $Matches[1]
    }

    $work = $work.Trim()
    $work = $work -replace '\s+', ' '
    $work = $work.Trim(' -')

    if ($result.Found -and -not [string]::IsNullOrWhiteSpace($work)) {
        $result.Title = Convert-Title ($work -replace '-', ' ')
        return $result
    }

    $cleanName = Get-CleanName $OriginalName
    if ($cleanName -match '^(.*?)[-\s\(](19\d{2}|20\d{2})[\)\-]?') {
        $titlePart = $Matches[1].Trim('-')
        if (-not [string]::IsNullOrWhiteSpace($titlePart)) {
            $result.Title = Convert-Title ($titlePart -replace '-', ' ')
            $result.Year = $Matches[2]
            $result.Found = $true
        }
    }

    return $result
}

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

function Get-SearchTitle {
    param(
        [string]$Title,
        [string]$Type
    )

    if ($Type -in @("EPISODIO", "TEMPORADA")) {
        $Title = $Title -replace '\(\d{4}\)', ''
        $Title = $Title -replace '\[\d{4}\]', ''
        $Title = $Title -replace '\s+S\d{1,2}E\d{1,2}.*$', ''
        $Title = $Title.Trim()
    }

    return $Title
}

function Split-TitleVariants {
    param([string]$Title)

    $variants = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    function Add-Variant {
        param([string]$Value)
        $Value = $Value.Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        $key = $Value.ToLower()
        if (-not $seen[$key]) {
            $seen[$key] = $true
            $variants.Add($Value) | Out-Null
        }
    }

    Add-Variant $Title

    if ($Title -match '^([^,]+),') {
        Add-Variant $Matches[1].Trim()
    }

    $hasNumberInTitle = $Title -match '\b(19\d{2}|20\d{2})\b'
    $stopWords = @('el', 'la', 'los', 'las', 'de', 'del', 'the', 'a', 'an')
    $words = $Title -split '\s+' | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and ($stopWords -notcontains $_.ToLower())
    }
    if ($words.Count -gt 0 -and -not $hasNumberInTitle) {
        Add-Variant $words[0]
    }

    return @($variants)
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

function Format-TelegramMessage {
    param(
        [string]$Type,
        [string]$Title,
        [string]$Resolution,
        [double]$SizeGB,
        [int]$Season = 0,
        [int]$Episode = 0,
        [string]$Year = "",
        [int]$EpisodeCount = 0
    )

    switch ($Type) {
        "EPISODIO" {
            return @"
📺 EPISODIO DESCARGADO

$Title
T$($Season.ToString('D2')) · E$($Episode.ToString('D2'))

🎞️ $Resolution
💾 $SizeGB GB
"@
        }
        "TEMPORADA" {
            return @"
📦 TEMPORADA DESCARGADA

$Title
Temporada $Season

📺 $EpisodeCount episodios
🎞️ $Resolution
💾 $SizeGB GB
"@
        }
        "PELICULA" {
            return @"
🎬 PELÍCULA DESCARGADA

$Title ($Year)

🎞️ $Resolution
💾 $SizeGB GB
"@
        }
        default {
            return @"
Torrent no clasificado

$Title

🎞️ $Resolution
💾 $SizeGB GB
"@
        }
    }
}
