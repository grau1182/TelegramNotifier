# ==================================================
# BACKUP-PRODUCTION.PS1
# ==================================================
# Script para generar backups de producción
# Incluye: Snapshot completo + Compresión

param(
    [switch]$FullBackup = $true,
    [switch]$TestBackup = $false
)

$BasePath = Split-Path -Parent $PSScriptRoot
$BackupPath = $PSScriptRoot
$Date = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n╔════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   BACKUP PRODUCTION TELEGRAMNOTIFIER║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════╝`n" -ForegroundColor Cyan

# ==================================================
# BACKUP COMPLETO
# ==================================================

if ($FullBackup) {
    Write-Host "📦 Creando backup completo..." -ForegroundColor Yellow
    
    $fullBackupName = "TelegramNotifier_FULL_$Date.zip"
    $fullBackupPath = Join-Path $BackupPath $fullBackupName
    
    # Rutas a incluir
    $itemsToBackup = @(
        (Join-Path $BasePath "core"),
        (Join-Path $BasePath "recursos"),
        (Join-Path $BasePath "test"),
        (Join-Path $BasePath ".gitignore"),
        (Join-Path $BasePath "README.md")
    )
    
    # Filtrar solo existentes
    $validItems = @()
    foreach ($item in $itemsToBackup) {
        if (Test-Path $item) {
            $validItems += $item
        }
    }
    
    try {
        Compress-Archive -Path $validItems -DestinationPath $fullBackupPath -Force
        $fileSize = [math]::Round((Get-Item $fullBackupPath).Length / 1MB, 2)
        Write-Host "✅ Backup completo creado:" -ForegroundColor Green
        Write-Host "   📄 $fullBackupName ($fileSize MB)" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Error creando backup: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ==================================================
# BACKUP PRODUCCIÓN (solo core + recursos)
# ==================================================

Write-Host "`n📦 Creando snapshot producción..." -ForegroundColor Yellow

$prodBackupName = "TelegramNotifier_PRODUCTION_$Date.zip"
$prodBackupPath = Join-Path $BackupPath $prodBackupName

$prodItems = @(
    (Join-Path $BasePath "core"),
    (Join-Path $BasePath "recursos")
)

try {
    Compress-Archive -Path $prodItems -DestinationPath $prodBackupPath -Force
    $fileSize = [math]::Round((Get-Item $prodBackupPath).Length / 1MB, 2)
    Write-Host "✅ Snapshot producción creado:" -ForegroundColor Green
    Write-Host "   📄 $prodBackupName ($fileSize MB)" -ForegroundColor Green
}
catch {
    Write-Host "❌ Error creando snapshot: $($_.Exception.Message)" -ForegroundColor Red
}

# ==================================================
# BACKUP TEST (solo test/)
# ==================================================

if ($TestBackup) {
    Write-Host "`n📦 Creando backup test..." -ForegroundColor Yellow
    
    $testBackupName = "TelegramNotifier_TEST_$Date.zip"
    $testBackupPath = Join-Path $BackupPath $testBackupName
    
    try {
        Compress-Archive -Path (Join-Path $BasePath "test") -DestinationPath $testBackupPath -Force
        $fileSize = [math]::Round((Get-Item $testBackupPath).Length / 1MB, 2)
        Write-Host "✅ Backup test creado:" -ForegroundColor Green
        Write-Host "   📄 $testBackupName ($fileSize MB)" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Error creando backup test: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ==================================================
# RESUMEN
# ==================================================

Write-Host "`n📊 Resumen de backups en: $BackupPath" -ForegroundColor Cyan
Get-ChildItem $BackupPath -Filter "TelegramNotifier_*.zip" -ErrorAction SilentlyContinue | 
    ForEach-Object {
        $size = [math]::Round($_.Length / 1MB, 2)
        $date = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        Write-Host "  📄 $($_.Name) - $size MB - $date" -ForegroundColor Green
    }

Write-Host "`n✅ Backup completado" -ForegroundColor Green
Write-Host ""
