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

    $encodedHash = [System.Uri]::EscapeDataString($Hash)
    $url = "$HostUrl/api/v2/torrents/files?hash=$encodedHash"

    return @(Invoke-RestMethod -Uri $url -Method Get -WebSession $WebSession)
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

    if ($Torrent.PSObject.Properties.Name -contains 'content_path' -and -not [string]::IsNullOrWhiteSpace([string]$Torrent.content_path)) {
        return Normalize-WindowsPath ([string]$Torrent.content_path)
    }

    $savePath = Normalize-WindowsPath ([string]$Torrent.save_path)
    if ($Files.Count -eq 0) {
        return $savePath
    }

    $relativePaths = @($Files | ForEach-Object {
        [string]$_.name
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($relativePaths.Count -eq 0) {
        return $savePath
    }

    if ($relativePaths.Count -eq 1) {
        return Normalize-WindowsPath (Join-WindowsPath $savePath $relativePaths[0])
    }

    $absolutePaths = @($relativePaths | ForEach-Object {
        Join-WindowsPath $savePath $_
    })

    $commonPrefix = Get-CommonPathPrefix -Paths $absolutePaths
    if (-not [string]::IsNullOrWhiteSpace($commonPrefix)) {
        return Normalize-WindowsPath $commonPrefix
    }

    $topLevelFolders = @($relativePaths | ForEach-Object {
        if ($_ -match '^([^\\/]+)[\\/]') { return $Matches[1] }
        return $null
    } | Where-Object { $_ } | Select-Object -Unique)

    if ($topLevelFolders.Count -eq 1) {
        return Normalize-WindowsPath (Join-WindowsPath $savePath $topLevelFolders[0])
    }

    $torrentFolder = Join-WindowsPath $savePath ([string]$Torrent.name)
    if (Test-Path -LiteralPath $torrentFolder) {
        return Normalize-WindowsPath $torrentFolder
    }

    return $savePath
}

function Test-ContentPathExists {
    param([string]$ContentPath)

    if ([string]::IsNullOrWhiteSpace($ContentPath)) {
        return $false
    }

    try {
        return Test-Path -LiteralPath $ContentPath
    }
    catch {
        return $false
    }
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

$torrents = @(Invoke-RestMethod `
    -Uri "$QBHost/api/v2/torrents/info" `
    -WebSession $session)

if ($OnlyCompleted) {
    $torrents = @($torrents | Where-Object { [string]$_.state -eq "uploading" -or [string]$_.state -eq "stalledUP" -or [double]$_.progress -ge 1.0 })
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

    $files = Get-TorrentFileList -Hash $torrent.hash -WebSession $session -HostUrl $QBHost.TrimEnd('/')
    $contentPath = Resolve-QBittorrentContentPath -Torrent $torrent -Files $files
    $contentExists = $false

    if (-not $SkipContentCheck) {
        $contentExists = Test-ContentPathExists -ContentPath $contentPath
    }

    $exported += [PSCustomObject]@{
        torrent_name    = [string]$torrent.name
        content_path    = $contentPath
        save_path       = Normalize-WindowsPath ([string]$torrent.save_path)
        size_bytes      = [long]$torrent.size
        size_gb         = [math]::Round([double]$torrent.size / 1GB, 2)
        state           = [string]$torrent.state
        progress        = [double]$torrent.progress
        hash            = [string]$torrent.hash
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
