param(
    [string]$QBHost = "http://localhost:8080",
    [string]$User = "grau1182",
    [string]$Password = "118291",
	[string]$Output = "$PSScriptRoot\qBittorrent_listado.json"
)


# Pedir contraseña si no se pasa por parámetro
if ([string]::IsNullOrWhiteSpace($Password)) {
    $Password = Read-Host "Contraseña"
}

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# =========================
# LOGIN
# =========================
$response = Invoke-RestMethod `
    -Uri "$QBHost/api/v2/auth/login" `
    -Method POST `
    -Body @{
        username = $User
        password = $Password
    } `
    -WebSession $session

if ($response -ne "Ok.") {
    Write-Error "Error de autenticación"
    exit
}

# =========================
# OBTENER TORRENTS
# =========================
$torrents = Invoke-RestMethod `
    -Uri "$QBHost/api/v2/torrents/info" `
    -WebSession $session

# =========================
# TRANSFORMAR DATOS
# =========================
$result = foreach ($t in $torrents) {

    [PSCustomObject]@{
        Torrent     = $t.name
        Ruta        = $t.save_path
        TamanoBytes = $t.size
        TamanoGB    = [math]::Round($t.size / 1GB, 2)
    }
}

# =========================
# EXPORT JSON CON BOM
# =========================
$json = $result | ConvertTo-Json -Depth 3

$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($Output, $json, $utf8Bom)

# =========================
# SALIDA
# =========================

Write-Host "Exportados $($result.Count) torrents."
Write-Host "JSON guardado en: $Output"