# ==================================================
# UTILITIES.PS1 - Funciones Generales de Utilidad
# ==================================================

function Load-Overrides {
    param([string]$OverrideFile = "")
    
    # Si no se pasa parámetro, usar variable global si existe
    if ([string]::IsNullOrEmpty($OverrideFile) -and $script:OverrideFile) {
        $OverrideFile = $script:OverrideFile
    }
    
    if (-not [string]::IsNullOrEmpty($OverrideFile) -and (Test-Path $OverrideFile)) {
        return (Get-Content $OverrideFile -Raw -Encoding UTF8) | ConvertFrom-Json
    }
    
    return $null
}

function Normalize-Name {
    param([string]$Name)

    $Name = $Name.ToLower()
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

    $Title = $Output -join ' '

    $Overrides = Load-Overrides

    if ($Overrides) {
        foreach ($Property in $Overrides.PSObject.Properties) {
            if ($Title.ToLower() -eq $Property.Name) {
                return $Property.Value
            }
        }
    }

    return $Title
}

function Get-CleanName {
    param([string]$Name)

    $Name = Normalize-Name $Name
    $Name = $Name -replace '^pack-', ''
    $Name = $Name -replace '(2160p|1080p|720p|480p).*', ''
    $Name = $Name.Trim('-')

    return $Name
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
