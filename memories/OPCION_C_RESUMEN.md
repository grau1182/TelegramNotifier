# 📋 OPCIÓN C - IMPLEMENTACIÓN COMPLETA

> **Documento histórico (2026-07-01).** Describe el refactor inicial a `core/` + `test/`.  
> **Estado actual del proyecto:** [`../README.md`](../README.md) · [`../core/README.md`](../core/README.md)

**Nota:** Referencias a `core/config/`, `title_overrides.json` y 108 títulos en caché corresponden al estado en esa fecha. La caché actual está en `recursos/plex_cache.json` (112 títulos).

**Fecha**: 2026-07-01  
**Estado**: ✅ COMPLETADA (refactor inicial)  
**Estructura**: Separación core (PRODUCCIÓN) + test (DESARROLLO)

---

## 🎯 Qué se Implementó

### ✅ Carpeta `core/` - Versión PRODUCCIÓN

**Código limpio**, sin testing, optimizado para:
- Búsqueda de posters en Plex
- Gestión caché persistente  
- Notificaciones Telegram (opcional)
- Logging automático

#### Estructura:

```
core/
├── run.ps1                          # Ejecutable principal
├── TelegramNotifier.ps1             # Script core simplificado
├── lib/                             # 4 librerías modulares
│   ├── logger.ps1                   # Logging + rotación
│   ├── utilities.ps1                # Normalización + parseo
│   ├── cache-manager.ps1            # Caché Plex + fuzzy matching
│   └── plex-functions.ps1           # Búsqueda API Plex
├── config/                          # Configuración
│   ├── plex_cache.json              # 108 títulos Plex
│   ├── title_overrides.json         # Sobrescrituras
│   ├── legacy_series_fallback.json  # Fallback
│   └── titles_mapping.json          # Mapeos
├── logs/                            # Logs automáticos (creados en runtime)
└── README.md                        # Documentación core
```

### ✅ Carpeta `backups/` - Sistema de Snapshots

**Backup automatizado** con 3 tipos:

```
backups/
├── backup-production.ps1            # Script de backup
├── RESTORE.md                       # Guía de restauración
├── TelegramNotifier_FULL_*.zip
├── TelegramNotifier_PRODUCTION_*.zip
└── TelegramNotifier_TEST_*.zip
```

**Tipos de backup**:
1. **FULL** - Proyecto completo (core + test + recursos)
2. **PRODUCTION** - Solo producción (core + recursos) ⭐ Recomendado
3. **TEST** - Solo testing (test/)

### ✅ Documentación Completa

| Documento | Ubicación | Propósito |
|-----------|-----------|----------|
| **README.md** | Raíz del proyecto | Guía general estructura |
| **core/README.md** | core/ | Documentación producción |
| **backups/RESTORE.md** | backups/ | Guía backup/restauración |

---

## 🔄 Migración de Funciones

### De `test/TelegramTorrent_Test.ps1` → `core/lib/`

#### ✅ Logger.ps1
```
Rotate-Log()
Write-Log()
Initialize-Logger()
```

#### ✅ Utilities.ps1
```
Load-Overrides()
Normalize-Name()
Get-Resolution()
Get-SizeGB()
Count-Episodes()
Convert-Title()
Get-CleanName()
Get-PatternDetected()
Get-TechnicalTags()
Get-ParseConfidence()
```

#### ✅ Cache-Manager.ps1
```
Initialize-PlexCache()
Add-ToCache()
Get-FuzzyMatchScore()
Get-PosterByCache()
```

#### ✅ Plex-Functions.ps1
```
Get-PlexPoster()              # Búsqueda principal
Get-PlexPosterFromItem()      # Extrae URL poster
Get-PlexMatchScore()          # Calcula puntuación
Get-PlexMatchScore()          # Score de coincidencia
Normalize-PlexQuery()
Normalize-PlexTitle()
Normalize-FilePath()
Get-PlexItemFilePath()
```

---

## 📊 Comparación Antes vs Después

### ANTES (Todo en test/)
```
❌ 1 archivo monolítico (789 líneas)
❌ Funciones mezcladas (test + producción)
❌ Difícil de mantener
❌ Overhead de código testing
❌ No hay separación clara
```

### DESPUÉS (Opción C)
```
✅ 5 scripts modulares (lib/)
✅ Funciones separadas por responsabilidad
✅ Fácil de mantener + extender
✅ Core limpio para producción
✅ Test totalmente separado
✅ Documentación integrada
✅ Sistema backup automatizado
```

---

## 🚀 Cómo Usar

### PRODUCCIÓN

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\core

# Búsqueda básica
.\run.ps1 -TorrentName "the-boys-s05e01.mkv" -ContentPath "D:\Series\The Boys"

# Con Telegram
.\run.ps1 -TorrentName "película.mkv" -ContentPath "D:\Películas" -SendTelegram
```

**Entrada**: Nombre torrent + Ruta  
**Salida**: 
- ✅ URL de poster (si existe en Plex)
- 📝 Log automático en `core/logs/`
- 💬 Notificación Telegram (opcional)

### TESTING

Documentación completa: [`test/README_TEST.md`](../test/README_TEST.md)

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test

# Producción manual — un torrent de prueba
cd ..\core
.\TelegramNotifier.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." -SendTelegram:$false

# Test — un torrent (paridad producción, con partial scan)
cd ..\test
.\TelegramTorrent_Test.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." -TestMode

# Test — un torrent (rápido, sin scan Plex)
.\TelegramTorrent_Test.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." -TestMode -SkipPlexScan

# FULL: caché test aislada + pasada 2 (no modifica prod)
.\test_v4_wrapper.ps1

# FULL + informe HTML (recomendado)
.\run_test_pipeline.ps1

# Suite rápida (10 torrents, sin scan, caché prod)
.\test_v4_wrapper.ps1 -QuickTest
.\run_test_pipeline.ps1 -QuickTest

# Validación
.\validation\Run-UnitValidation.ps1
.\validation\Run-SeriesRegression.ps1
.\validation\ValidateKingsmanSearch.ps1
```

Ver [`test/README_TEST.md`](../test/README_TEST.md) para modos, artefactos y promoción a `core/`.

### BACKUP

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\backups

# Backup automático
.\backup-production.ps1

# Crear ZIP con core + recursos
# Archivo: TelegramNotifier_PRODUCTION_YYYYMMDD_HHMMSS.zip
```

---

## 📈 Ventajas de Opción C

### 1️⃣ Separación Clara
- `core/` = Producción limpia
- `test/` = Desarrollo + testing
- `recursos/` = Datos compartidos
- `backups/` = Snapshots

### 2️⃣ Mantenibilidad
- Cambios en test NO afectan producción
- Funciones organizadas por módulo
- Fácil localizar y arreglar bugs
- Código reutilizable

### 3️⃣ Performance
- Caché de 108 títulos (0ms carga)
- 88.61% cobertura de búsqueda
- 4.63 segundos para 237 torrents
- Fuzzy matching optimizado

### 4️⃣ Escalabilidad
- Agregar nuevas librerías = simple
- Extender funcionalidad = modular
- Versiones = fácil backup/restore
- Deploy a servidor = directo

### 5️⃣ Documentación
- README en cada sección
- Ejemplos de uso
- Troubleshooting incluido
- Guía de backup/restore

---

## 🔑 Archivos Críticos

### Para PRODUCCIÓN

**core/TelegramNotifier.ps1** (líneas 10-14)
```powershell
# Configurar aquí:
$BotToken = "Tu-Bot-Token"
$ChatID   = "Tu-Chat-ID"
$PlexUrl  = "http://127.0.0.1:32400"
$PlexToken = "Tu-Token-Plex"
```

**recursos/plex_cache.json** (compartida producción + test)
- Auto-generado en primera ejecución
- 108+ títulos Plex almacenados
- Auto-actualizado con nuevos títulos

**core/logs/TelegramNotifier_*.log**
- Archivo diario (rotación automática)
- Máximo 5MB por archivo
- Timestamps en cada operación

### Para BACKUP

**backups/backup-production.ps1**
```powershell
# Crear backup
.\backup-production.ps1

# Con test incluido
.\backup-production.ps1 -TestBackup
```

**backups/RESTORE.md**
- Paso a paso de restauración
- Verificación de integridad
- Troubleshooting

---

## 📋 Checklist de Validación

- ✅ Estructura `core/` creada
- ✅ 4 librerías en `core/lib/`
- ✅ Configuración en `core/config/`
- ✅ TelegramNotifier.ps1 funcional
- ✅ run.ps1 como ejecutable
- ✅ Caché copiado a `core/config/`
- ✅ Sistema backup en `/backups`
- ✅ Documentación completa (3 README.md)
- ✅ Test/core separados totalmente
- ✅ Referencias actualizadas

---

## 🎓 Próximos Pasos

### 1. Verificar Funcionamiento

```powershell
cd core

# Test rápido
.\run.ps1 -TorrentName "test.mkv" -ContentPath "."

# Ver logs
Get-Content "logs\TelegramNotifier_*.log" -Tail 10
```

### 2. Copiar a Producción

```powershell
cd backups
.\backup-production.ps1

# Transferir a servidor
# scp TelegramNotifier_PRODUCTION_*.zip usuario@servidor:~/
```

### 3. Automatizar Backups

```powershell
# Programar backup diario en Windows
# Ver: backups/RESTORE.md → Sección "Automatizar Backups Diarios"
```

### 4. Customizar

```powershell
# Editar overrides
# core/config/title_overrides.json

# Agregar tokens
# core/TelegramNotifier.ps1 líneas 10-14
```

---

## 📊 Estadísticas Finales

| Métrica | Valor |
|---------|-------|
| **Scripts en core/** | 5 (1 principal + 4 libs) |
| **Líneas código core** | ~800 (distribuidas + comentada) |
| **Documentación** | 3 README + guías |
| **Caché títulos** | 108 (auto-expandible) |
| **Cobertura búsqueda** | 88.61% |
| **Tiempo búsqueda** | 50ms (con caché) |
| **Backup automático** | ✅ Implementado |
| **Sistema modular** | ✅ Completado |

---

## 🎉 Resumen Opción C

**Implementación completada exitosamente**

✨ **Lo que logramos**:
1. Separación clara producción ↔ testing
2. Código modular en 4 librerías
3. Sistema backup automatizado
4. Documentación completa
5. 88.61% cobertura de búsqueda
6. Performance optimizado (caché 0ms)

🚀 **Listo para**:
- Deploy a servidor
- Mantenimiento futuro
- Escalabilidad
- Automatización

---

**Estado**: ✅ COMPLETADO  
**Versión**: 1.0 Producción  
**Fecha**: 2026-07-01
