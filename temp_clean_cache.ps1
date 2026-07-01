# Script para limpiar los archivos plex_cache.json
$cleanCache = @{
    version = "1.0"
    lastUpdated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    totalItems = 0
    description = "Cache persistente de Plex"
    cache = @()
}

# Convertir a JSON y guardar
$jsonContent = $cleanCache | ConvertTo-Json -Depth 10
$jsonContent | Set-Content -Path "C:\Users\grau_\Downloads\TelegramNotifier\core\config\plex_cache.json" -Encoding UTF8

# Copiar a test
Copy-Item -Path "C:\Users\grau_\Downloads\TelegramNotifier\core\config\plex_cache.json" `
          -Destination "C:\Users\grau_\Downloads\TelegramNotifier\test\config\plex_cache.json" -Force

Write-Host "Cache files cleaned" -ForegroundColor Green
