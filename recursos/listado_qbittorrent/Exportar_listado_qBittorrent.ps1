param(
    [string]$QBHost = "http://localhost:8080",
    [string]$User = "grau1182",
    [string]$Password = "118291",
    [string]$Output = "$PSScriptRoot\qBittorrent_listado.json",
    [switch]$OnlyCompleted,
    [switch]$SkipContentCheck
)

$ErrorActionPreference = "Stop"

function Normalize-WindowsPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    return ($Path.Trim().Replace('/', '\').TrimEnd('\'))
}

function Join-WindowsPath {
    param(
        [string]$Base,
        [string]$Relative
    )

    $basePath = Normalize-WindowsPath $Base
    $relativePath = $Relative.Replace('/', '\').TrimStart('\')

    if ([string]::IsNullOrWhiteSpace($basePath)) {
        return $relativePath
    }

    return [System.IO.Path]::Combine($basePath, $relativePath)
}

function Get-TorrentFileList {
    param(
        [string]$Hash,
        $WebSession,
        [string]$HostUrl
    )

    $Hash = [string](Get-QBSingleValue $Hash).ToLower()
    $encodedHash = [System.Uri]::EscapeDataString($Hash)
    $url = "$HostUrl/api/v2/torrents/files?hash=$encodedHash"

    try {
        return @(Invoke-RestMethod -Uri $url -Method Get -WebSession $WebSession -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

function Get-CommonPathPrefix {
    param([string[]]$Paths)

    if (-not $Paths -or $Paths.Count -eq 0) {
        return ""
    }

    if ($Paths.Count -eq 1) {
        $single = $Paths[0]
        $lastSlash = $single.LastIndexOf('\')
        if ($lastSlash -gt 0) {
            return $single.Substring(0, $lastSlash)
        }
        return ""
    }

    $splitPaths = $Paths | ForEach-Object { $_.Split('\') }
    $prefixParts = @()

    for ($i = 0; $i -lt $splitPaths[0].Count; $i++) {
        $segment = $splitPaths[0][$i]
        $allMatch = $true

        foreach ($pathParts in $splitPaths) {
            if ($pathParts.Count -le $i -or $pathParts[$i] -ne $segment) {
                $allMatch = $false
                break
            }
        }

        if (-not $allMatch) {
            break
        }

        $prefixParts += $segment
    }

    return ($prefixParts -join '\')
}

function Resolve-QBittorrentContentPath {
    param(
        $Torrent,
        [array]$Files
    )

    $savePath = Normalize-WindowsPath ([string](Get-QBSingleValue $Torrent.save_path))

    $apiPath = Get-ApiContentPath -Torrent $Torrent
    if ($apiPath) {
        return $apiPath
    }

    if ($Files.Count -eq 0) {
        return $savePath
    }

    $relativePaths = @($Files | ForEach-Object {
        [string](Get-QBSingleValue $_.name)
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($relativePaths.Count -eq 0) {
        return $savePath
    }

    if ($relativePaths.Count -eq 1) {
        $singlePath = Normalize-WindowsPath (Join-WindowsPath $savePath $relativePaths[0])
        if (Test-ValidWindowsContentPath $singlePath) {
            return $singlePath
        }
        return $savePath
    }

    $absolutePaths = @($relativePaths | ForEach-Object {
        Join-WindowsPath $savePath $_
    })

    $commonPrefix = Get-CommonPathPrefix -Paths $absolutePaths
    if (Test-ValidWindowsContentPath $commonPrefix) {
        return Normalize-WindowsPath $commonPrefix
    }

    $topLevelFolders = @($relativePaths | ForEach-Object {
        if ($_ -match '^([^\\/]+)[\\/]') { return $Matches[1] }
        return $null
    } | Where-Object { $_ } | Select-Object -Unique)

    if ($topLevelFolders.Count -eq 1) {
        return Normalize-WindowsPath (Join-WindowsPath $savePath $topLevelFolders[0])
    }

    $torrentFolder = Join-WindowsPath $savePath ([string](Get-QBSingleValue $Torrent.name))
    if (Test-Path -LiteralPath $torrentFolder) {
        return Normalize-WindowsPath $torrentFolder
    }

    return $savePath
}

function Test-ContentPathExists {
    param(
        [string]$ContentPath,
        [string]$SavePath = ""
    )

    foreach ($candidate in @($ContentPath, $SavePath)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            if (Test-Path -LiteralPath $candidate) {
                return $true
            }
        }
        catch {
        }
    }

    return $false
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Object
    )

    $json = $Object | ConvertTo-Json -Depth 6
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $json, $utf8Bom)
}

function Get-QBSingleValue {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Array]) {
        return ($Value | Select-Object -First 1)
    }

    return $Value
}

function Expand-QBittorrentTorrentRows {
    param($Torrents)

    if ($null -eq $Torrents) {
        return @()
    }

    if ($Torrents -isnot [System.Array]) {
        $Torrents = @($Torrents)
    }

    if ($Torrents.Count -eq 0) {
        return @()
    }

    if ($Torrents.Count -gt 1) {
        return @($Torrents)
    }

    $first = $Torrents[0]
    if ($null -eq $first -or $null -eq $first.name -or $first.name -isnot [System.Array]) {
        return @($first)
    }

    $count = @($first.name).Count
    $rows = @()

    for ($i = 0; $i -lt $count; $i++) {
        $row = [ordered]@{}
        foreach ($prop in $first.PSObject.Properties) {
            $val = $prop.Value
            if ($val -is [System.Array] -and @($val).Count -eq $count) {
                $row[$prop.Name] = $val[$i]
            }
            else {
                $row[$prop.Name] = $val
            }
        }
        $rows += [PSCustomObject]$row
    }

    return $rows
}

function Test-ValidWindowsContentPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if ($Path -match '\s[A-Za-z]:\\') {
        return $false
    }

    return $Path -match '^[A-Za-z]:\\'
}

function Get-ApiContentPath {
    param($Torrent)

    if ($Torrent.PSObject.Properties.Name -notcontains 'content_path') {
        return $null
    }

    $apiPath = Normalize-WindowsPath ([string](Get-QBSingleValue $Torrent.content_path))
    if (Test-ValidWindowsContentPath $apiPath) {
        return $apiPath
    }

    return $null
}

function Get-QBDoubleValue {
    param(
        $Value,
        [double]$Default = 0
    )

    $single = Get-QBSingleValue $Value
    if ($null -eq $single) {
        return $Default
    }

    $parsed = 0.0
    if ([double]::TryParse([string]$single, [ref]$parsed)) {
        return $parsed
    }

    return $Default
}

function Get-QBLongValue {
    param(
        $Value,
        [long]$Default = 0
    )

    $single = Get-QBSingleValue $Value
    if ($null -eq $single) {
        return $Default
    }

    $parsed = [long]0
    if ([long]::TryParse([string]$single, [ref]$parsed)) {
        return $parsed
    }

    return $Default
}

function Test-QBittorrentCompleted {
    param($Torrent)

    $state = [string](Get-QBSingleValue $Torrent.state)
    if ($state -in @('uploading', 'stalledUP', 'pausedUP', 'forcedUP', 'queuedUP', 'stoppedUP')) {
        return $true
    }

    return (Get-QBDoubleValue $Torrent.progress) -ge 0.999
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    $Password = Read-Host "Contraseña qBittorrent"
}

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

Write-Host "Conectando a qBittorrent: $QBHost" -ForegroundColor Cyan

$response = Invoke-RestMethod `
    -Uri "$QBHost/api/v2/auth/login" `
    -Method POST `
    -Body @{
        username = $User
        password = $Password
    } `
    -WebSession $session

if ($response -ne "Ok.") {
    Write-Error "Error de autenticacion en qBittorrent"
    exit 1
}

$torrents = Expand-QBittorrentTorrentRows (Invoke-RestMethod `
    -Uri "$QBHost/api/v2/torrents/info" `
    -WebSession $session)

Write-Host "Torrents recibidos de qBittorrent: $($torrents.Count)" -ForegroundColor DarkGray

if ($OnlyCompleted) {
    $torrents = @($torrents | Where-Object { Test-QBittorrentCompleted -Torrent $_ })
    Write-Host "Filtro OnlyCompleted: $($torrents.Count) torrents" -ForegroundColor Yellow
}

Write-Host "Procesando $($torrents.Count) torrents..." -ForegroundColor Cyan

$exported = @()
$index = 0

foreach ($torrent in $torrents) {
    $index++
    if ($index % 25 -eq 0) {
        Write-Host "  $index / $($torrents.Count)..." -ForegroundColor DarkGray
    }

    $torrentHash = [string](Get-QBSingleValue $torrent.hash)
    $files = @(Get-TorrentFileList -Hash $torrentHash -WebSession $session -HostUrl $QBHost.TrimEnd('/'))
    $savePath = Normalize-WindowsPath ([string](Get-QBSingleValue $torrent.save_path))
    $contentPath = Resolve-QBittorrentContentPath -Torrent $torrent -Files $files
    $contentExists = $false

    if (-not $SkipContentCheck) {
        $contentExists = Test-ContentPathExists -ContentPath $contentPath -SavePath $savePath
    }

    $sizeBytes = Get-QBLongValue $torrent.size
    $progressValue = Get-QBDoubleValue $torrent.progress

    $exported += [PSCustomObject]@{
        torrent_name    = [string](Get-QBSingleValue $torrent.name)
        content_path    = $contentPath
        save_path       = $savePath
        size_bytes      = $sizeBytes
        size_gb         = [math]::Round($sizeBytes / 1GB, 2)
        state           = [string](Get-QBSingleValue $torrent.state)
        progress        = $progressValue
        hash            = $torrentHash
        file_count      = $files.Count
        content_exists  = $contentExists
        test_tier       = if ($contentExists) { "full" } else { "parse_only" }
    }
}

$payload = [PSCustomObject]@{
    version    = 2
    exportedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    qbHost     = $QBHost
    filters    = @{
        onlyCompleted   = [bool]$OnlyCompleted.IsPresent
        skipContentCheck = [bool]$SkipContentCheck.IsPresent
    }
    summary    = [PSCustomObject]@{
        total           = $exported.Count
        content_exists  = @($exported | Where-Object { $_.content_exists }).Count
        parse_only      = @($exported | Where-Object { -not $_.content_exists }).Count
    }
    torrents   = $exported
}

Write-JsonFile -Path $Output -Object $payload

Write-Host ""
Write-Host "Exportados $($exported.Count) torrents." -ForegroundColor Green
Write-Host "  Con contenido en disco: $($payload.summary.content_exists)" -ForegroundColor Green
Write-Host "  Solo parseo (sin ruta local): $($payload.summary.parse_only)" -ForegroundColor Yellow
Write-Host "JSON guardado en: $Output" -ForegroundColor Cyan
Write-Host ""
Write-Host "Siguiente paso (CSV para tests):" -ForegroundColor DarkGray
Write-Host "  cd test" -ForegroundColor DarkGray
Write-Host "  .\regenerate_csv.ps1" -ForegroundColor DarkGray
