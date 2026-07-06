# 💾 Sistema de Backups - TelegramNotifier

> Documentación operativa actualizada: [`../README.md`](../README.md), [`../test/README_TEST.md`](../test/README_TEST.md)

Gestión automática de backups para producción y desarrollo.

## 📁 Estructura de Backups

```
backups/
├── backup-production.ps1          # Script automatizado
├── RESTORE.md                     # Este archivo
├── TelegramNotifier_FULL_*.zip
├── TelegramNotifier_PRODUCTION_*.zip
└── TelegramNotifier_TEST_*.zip
```

## 📦 Tipos de Backup

### 1. **FULL Backup** (Completo)
- Incluye: `core/` + `test/` + `recursos/` + archivos raíz
- Uso: Snapshot completo del proyecto
- Tamaño: ~100-200 MB
- Archivo: `TelegramNotifier_FULL_YYYYMMDD_HHMMSS.zip`

### 2. **PRODUCTION Snapshot** (Recomendado)
- Incluye: `core/` + `recursos/`
- Uso: Deploy a servidor / backup diario
- Tamaño: ~5-20 MB
- Archivo: `TelegramNotifier_PRODUCTION_YYYYMMDD_HHMMSS.zip`

### 3. **TEST Backup** (Opcional)
- Incluye: `test/` (framework de testing)
- Uso: Desarrollo y mejoras
- Tamaño: ~1-5 MB
- Archivo: `TelegramNotifier_TEST_YYYYMMDD_HHMMSS.zip`

## 🔄 Crear Backup

### Backup Automático (Recomendado)

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\backups

# Backup producción (default)
.\backup-production.ps1

# Backup completo
.\backup-production.ps1 -FullBackup

# Incluir backup test
.\backup-production.ps1 -TestBackup
```

### Backup Manual

```powershell
# Comprimir core + recursos
Compress-Archive -Path @("core", "recursos") `
    -DestinationPath "TelegramNotifier_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
```

## 📥 Restaurar Backup

### Restaurar Versión Completa

```powershell
# 1. Extraer backup
Expand-Archive "TelegramNotifier_PRODUCTION_20260701_132309.zip" -DestinationPath "C:\Restore\"

# 2. Copiar a ubicación de producción
Copy-Item "C:\Restore\core" "C:\ServidorProduccion\" -Recurse -Force
Copy-Item "C:\Restore\recursos" "C:\ServidorProduccion\" -Recurse -Force

# 3. Verificar
Get-ChildItem "C:\ServidorProduccion\core"
```

### Restaurar Solo Caché

```powershell
# Si solo necesitas actualizar plex_cache.json
Expand-Archive "TelegramNotifier_PRODUCTION_*.zip" -DestinationPath $env:TEMP

Copy-Item "$env:TEMP\recursos\plex_cache.json" "C:\TuRuta\recursos\" -Force
```

## 🔍 Verificar Integridad

```powershell
# Ver contenido sin extraer
Expand-Archive "TelegramNotifier_PRODUCTION_*.zip" -DestinationPath $env:TEMP -PassThru | 
    Get-ChildItem -Recurse | Select-Object FullName, Length

# Comparar tamaño
$original = Get-ChildItem "core", "recursos" -Recurse | 
    Measure-Object Length -Sum | Select-Object -ExpandProperty Sum

$backup = (Get-ChildItem "TelegramNotifier_PRODUCTION_*.zip" | 
    Select-Object -First 1).Length

"Original: $($original/1MB) MB | Backup: $($backup/1MB) MB"
```

## 🗑️ Limpiar Backups Antiguos

```powershell
# Eliminar backups más antiguos que 30 días
Get-ChildItem "TelegramNotifier_*.zip" | 
    Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | 
    Remove-Item -Force

# Ver backups que se van a eliminar
Get-ChildItem "TelegramNotifier_*.zip" | 
    Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | 
    Select-Object Name, LastWriteTime
```

## 📋 Checklist de Restauración

- [ ] Verificar backup no corrupto
- [ ] Extraer a ubicación temporal
- [ ] Verificar estructura: `core/` + `lib/` + `config/`
- [ ] Copiar archivos a destino
- [ ] Probar: `.\run.ps1 -TorrentName "test.mkv"`
- [ ] Verificar logs: `core\logs\`
- [ ] Verificar caché: `core\config\plex_cache.json`

## 🔐 Protección de Datos Sensibles

### ⚠️ IMPORTANTE

El backup incluye:
- ✅ Caché Plex (puede ser regenerado)
- ✅ Configuración general
- ❌ **NO** incluye: Tokens/Passwords

**Antes de compartir backup:**
1. Revisar `core/config/` → No contiene secrets
2. Tokens están en scripts (editar antes)
3. Considerar excluir `core/logs/` (datos personales)

## 📊 Estadísticas Típicas

| Componente | Tamaño | Conteo |
|-----------|--------|--------|
| core/ | 2-5 MB | 10+ archivos |
| recursos/ | 1-3 MB | torrents.csv + configs |
| test/ | 0.5-2 MB | Scripts de testing |
| Backup PRODUCTION | 5-20 MB | Comprimido |
| Backup FULL | 100-200 MB | Comprimido |

## 🚨 Problemas Comunes

### "Error: Ruta no encontrada"
```powershell
# Verificar rutas existen
Test-Path "core"
Test-Path "recursos"

# Ejecutar desde directorio correcto
cd C:\Users\grau_\Downloads\TelegramNotifier
```

### "Archivo en uso"
```powershell
# Esperar a que se cierre
Start-Sleep -Seconds 5

# O usar PID para encontrar proceso
Get-Process | Where-Object {$_.Handles -gt 0}
```

### "ZIP corrupto"
```powershell
# Reintentar compresión
Remove-Item "TelegramNotifier_*.zip" -Confirm

.\backup-production.ps1 -FullBackup
```

## 🤖 Automatizar Backups Diarios

### Tarea Programada Windows

```powershell
# Crear tarea (ejecutar como Admin)
$taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\...\backup-production.ps1"

$taskTrigger = New-ScheduledTaskTrigger -Daily -At 02:00AM

Register-ScheduledTask -TaskName "TelegramNotifier_Backup_Daily" `
    -Action $taskAction -Trigger $taskTrigger -RunLevel Highest
```

### Script Batch Alternativo

```batch
@echo off
REM backup-daily.bat
cd /d C:\Users\grau_\Downloads\TelegramNotifier\backups
powershell.exe -ExecutionPolicy Bypass -File "backup-production.ps1" -FullBackup
```

## 📞 Referencia Rápida

```powershell
# Crear backup ahora
.\backup-production.ps1

# Listar backups recientes
Get-ChildItem "TelegramNotifier_*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# Extraer backup
Expand-Archive "TelegramNotifier_PRODUCTION_*.zip" -DestinationPath "C:\Restore"

# Limpiar backups 30+ días
Get-ChildItem "TelegramNotifier_*.zip" | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | Remove-Item
```

---

**Versión**: 1.0  
**Última actualización**: 2026-07-01
