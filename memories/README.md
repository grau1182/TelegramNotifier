# 🚀 TelegramNotifier - Sistema Completo

> **Nota (2026-07-06):** Documentación canónica actualizada en [`../README.md`](../README.md), [`../core/README.md`](../core/README.md) y [`../test/README_TEST.md`](../test/README_TEST.md). Este archivo es copia archivada; puede contener referencias obsoletas (`title_overrides.json`, `core/config/plex_cache.json`).

Suite completa para notificación de torrents con integración Plex y caché persistente.

---

## ðŸŽ¯ RESUMEN EJECUTIVO (Elevator Pitch)

**Â¿QuÃ© es?**  
Sistema automatizado que **monitorea torrents completados en qBittorrent**, busca posters en tu servidor Plex, y **envÃ­a notificaciones a Telegram** con la portada del contenido.

**Â¿CÃ³mo funciona?**
```
Torrent completado en qBittorrent
       â†“
TelegramNotifier analiza el nombre
       â†“
Detecta tipo: EPISODIO / PELÃCULA / TEMPORADA
       â†“
Busca poster en cachÃ© (0ms) o Plex API (500ms-2s)
       â†“
EnvÃ­a a Telegram con imagen + detalles
       â†“
Todo queda registrado en logs
```

**Funcionalidades Clave**
- âœ… **BÃºsqueda inteligente**: Fuzzy matching + cachÃ© persistente
- âœ… **Notificaciones Telegram**: Con posters en tiempo real
- âœ… **SincronizaciÃ³n Plex**: IntegraciÃ³n nativa con API REST
- âœ… **CachÃ© persistente**: 100+ tÃ­tulos precargados, 0ms de latencia
- âœ… **Logging automÃ¡tico**: RotaciÃ³n diaria, niveles de severidad
- âœ… **Modular**: 4 librerÃ­as independientes, fÃ¡cil de extender

**EstadÃ­sticas**
- **Cobertura**: 88.61% (210/237 torrents encontrados)
- **Velocidad**: 0ms cachÃ© local, 500ms-2s API fallback
- **Uptime**: ProducciÃ³n 24/7 con logs por dÃ­a

---

## ðŸ”„ FLUJO DE EJECUCIÃ“N EN TIEMPO REAL

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                    QBITTORRENT                              â”‚
â”‚             (Torrent completado)                            â”‚
â”‚          Ejecuta: TelegramNotifier.ps1                      â”‚
â”‚          ParÃ¡metros: %N (nombre) %F (ruta)                â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                         â”‚
                         â†“
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚               CORE/TELEGRAMNOTIFIER.PS1                      â”‚
â”‚                                                              â”‚
â”‚  1. Carga 4 librerÃ­as (logger, utilities, cache, plex)     â”‚
â”‚  2. Inicializa logging en core/logs/                       â”‚
â”‚  3. Procesa nombre del torrent                             â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                         â”‚
                         â†“
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                 PARSING & DETECCIÃ“N                          â”‚
â”‚  - Normaliza nombre (minÃºscula, separadores, extensiones)  â”‚
â”‚  - Detecta patrÃ³n: S##E## (episodio) / S## (temporada)    â”‚
â”‚  - Extrae aÃ±o (pelÃ­cula) o marca como desconocido          â”‚
â”‚  - Obtiene: resoluciÃ³n, tamaÃ±o, # episodios                â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                         â”‚
                         â†“
        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
        â”‚   Â¿EstÃ¡ en cachÃ©?              â”‚
        â”‚   (108 tÃ­tulos precargados)    â”‚
        â””â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”˜
                 â”‚               â”‚
            âœ… SÃ (0ms)      âŒ NO (API)
                 â”‚               â”‚
        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
        â”‚ Cache Hit      â”‚   â”‚ Llamada API Plex        â”‚
        â”‚ Score: 100%    â”‚   â”‚ BÃºsqueda inteligente    â”‚
        â”‚ Devuelve URL   â”‚   â”‚ Scoring de resultados   â”‚
        â””â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚ Auto-actualiza cachÃ©    â”‚
                 â”‚           â””â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                 â”‚               â”‚
        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”
        â”‚  OBTIENE URL DEL POSTER         â”‚
        â”‚  (O NULL si no encuentra)       â”‚
        â””â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                 â”‚
                 â†“
        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
        â”‚  Â¿SendTelegram = true?         â”‚
        â”‚  (Por defecto en producciÃ³n)   â”‚
        â””â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”˜
             â”‚                  â”‚
        âœ… SÃ              âŒ NO
             â”‚                  â”‚
             â†“                  â”‚
        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”     â”‚
        â”‚ Telegram        â”‚     â”‚
        â”‚ + Poster (JPG)  â”‚     â”‚
        â”‚ + Detalles      â”‚     â”‚
        â”‚ - EnvÃ­o via Bot â”‚     â”‚
        â””â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”˜     â”‚
                 â”‚              â”‚
                 â””â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”˜
                        â”‚
                        â†“
                â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
                â”‚ Registra en logs  â”‚
                â”‚ core/logs/...log  â”‚
                â”‚ [SUCCESS/WARNING] â”‚
                â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

## ðŸ“‹ TABLA DE REFERENCIA: Â¿QUÃ‰ ARCHIVO HACE QUÃ‰?

| Archivo | UbicaciÃ³n | Responsabilidad | Entrada | Salida | CrÃ­tico |
|---------|-----------|-----------------|---------|--------|---------|
| **TelegramNotifier.ps1** | `core/` | Script principal, orquesta todo | Nombre torrent, ruta | Logs, aviso Telegram | â­â­â­ |
| **logger.ps1** | `core/lib/` | Logging con rotaciÃ³n automÃ¡tica | Texto, nivel | Archivo log | â­â­ |
| **utilities.ps1** | `core/lib/` | Parsing, normalizaciÃ³n, anÃ¡lisis | Nombre archivo | Metadatos detectados | â­â­â­ |
| **cache-manager.ps1** | `core/lib/` | GestiÃ³n cachÃ© (memoria + JSON) | TÃ­tulo, bÃºsqueda | URL poster o null | â­â­â­ |
| **plex-functions.ps1** | `core/lib/` | BÃºsqueda Plex API, scoring | Metadatos, ruta | URL poster + metadata | â­â­â­ |
| **plex_cache.json** | `core/config/` | Base de datos local de 108 tÃ­tulos | (archivo) | JSON con cachÃ© | â­â­â­ |
| **title_overrides.json** | `core/config/` | Mapeo tÃ­tulos especiales | TÃ­tulo normalizado | TÃ­tulo formateado | â­ |
| **backup-production.ps1** | `backups/` | Crear snapshots ZIP | (ejecuciÃ³n) | TelegramNotifier_*.zip | â­â­ |
| **TelegramTorrent_Test.ps1** | `test/` | Suite completa de 237 torrents | lista de torrents | JSON resultados | â­â­ (desarrollo) |
| **test_v4_wrapper.ps1** | `test/` | Wrapper de testing flexible | parÃ¡metros | logs + resultados | â­â­ (desarrollo) |
| **run_test_pipeline.ps1** | `test/` | Orquesta test + reporte HTML | (ejecuciÃ³n) | test + HTML report | â­â­ (desarrollo) |

### Leyenda CrÃ­tica
- **â­â­â­** = ProducciÃ³n, si falla todo falla
- **â­â­** = Importante, afecta funcionalidad
- **â­** = Opcional, mejora UX

---

## ðŸ“ Estructura del Proyecto (OpciÃ³n C)

```
TelegramNotifier/
â”‚
â”œâ”€â”€ ðŸŽ¯ core/                          â­ PRODUCCIÃ“N (simplificado)
â”‚   â”œâ”€â”€ TelegramNotifier.ps1          # â­â­â­ SCRIPT PRINCIPAL
â”‚   â”œâ”€â”€ run.ps1                       # Wrapper ejecutable
â”‚   â”œâ”€â”€ lib/                          # 4 LIBRERÃAS MODULARES
â”‚   â”‚   â”œâ”€â”€ logger.ps1                # [55 lÃ­neas] Logging con rotaciÃ³n
â”‚   â”‚   â”œâ”€â”€ utilities.ps1             # [201 lÃ­neas] Parsing y anÃ¡lisis
â”‚   â”‚   â”œâ”€â”€ cache-manager.ps1         # [190 lÃ­neas] CachÃ© persistente
â”‚   â”‚   â””â”€â”€ plex-functions.ps1        # [179 lÃ­neas] BÃºsqueda Plex API
â”‚   â”œâ”€â”€ config/                       # CONFIGURACIÃ“N PRODUCCIÃ“N
â”‚   â”‚   â”œâ”€â”€ plex_cache.json           # 108 tÃ­tulos precargados
â”‚   â”‚   â”œâ”€â”€ title_overrides.json      # Mapeo titles especiales
â”‚   â”‚   â”œâ”€â”€ legacy_series_fallback.json
â”‚   â”‚   â””â”€â”€ titles_mapping.json
â”‚   â”œâ”€â”€ logs/                         # LOGS PRODUCCIÃ“N (auto-generado)
â”‚   â”‚   â””â”€â”€ TelegramNotifier_YYYYMMDD.log
â”‚   â””â”€â”€ README.md                     # DocumentaciÃ³n del core
â”‚
â”œâ”€â”€ ðŸ§ª test/                          # DESARROLLO Y TESTING (separado)
â”‚   â”œâ”€â”€ TelegramTorrent_Test.ps1      # Suite 237 torrents (88.61% cobertura)
â”‚   â”œâ”€â”€ test_v4_wrapper.ps1           # Generador flexible de tests
â”‚   â”œâ”€â”€ run_test_pipeline.ps1         # Orquesta test + reporte
â”‚   â”œâ”€â”€ validation/
â”‚   â”‚   â”œâ”€â”€ AnalyzeResults.ps1        # Generador HTML reports
â”‚   â”‚   â”œâ”€â”€ ValidateTest.ps1
â”‚   â”‚   â””â”€â”€ [otros validadores]
â”‚   â”œâ”€â”€ results/
â”‚   â”‚   â”œâ”€â”€ json/                     # Resultados JSON por test
â”‚   â”‚   â””â”€â”€ analisis/                 # HTML reports con imÃ¡genes
â”‚   â”œâ”€â”€ fixtures/
â”‚   â”‚   â””â”€â”€ plex/                     # 50+ XML de respuestas Plex
â”‚   â”œâ”€â”€ logs/                         # Logs de testing
â”‚   â””â”€â”€ config/                       # Config test (distinta de core)
â”‚
â”œâ”€â”€ ðŸ“¦ recursos/                      # DATOS COMPARTIDOS
â”‚   â”œâ”€â”€ plex_cache.json               # CachÃ© principal (respaldo)
â”‚   â”œâ”€â”€ torrents.csv                  # Lista 237 torrents
â”‚   â”œâ”€â”€ README_CACHE.md               # DocumentaciÃ³n cachÃ©
â”‚   â”œâ”€â”€ title_overrides.json          # Sobrescrituras globales
â”‚   â””â”€â”€ estructura_bibliotecas/
â”‚
â”œâ”€â”€ ðŸ’¾ backups/                       # SISTEMA DE BACKUPS
â”‚   â”œâ”€â”€ backup-production.ps1         # â­ Script backup automatizado
â”‚   â”œâ”€â”€ RESTORE.md                    # GuÃ­a restauraciÃ³n
â”‚   â””â”€â”€ TelegramNotifier_*.zip        # Archivos snapshot
â”‚
â”œâ”€â”€ ðŸ“„ README.md                      # â­ Este archivo (raÃ­z)
â”œâ”€â”€ TELEGRAM_CONFIG.md                # GuÃ­a Telegram
â”œâ”€â”€ .gitignore                        # Control de versiÃ³n
â””â”€â”€ [archivos antiguos legacy - ignorar]
```

---

## ðŸ”Œ CONFIGURACIÃ“N qBITTORRENT (GuÃ­a Visual)

### Paso 1: Abre qBittorrent y ve a Preferencias

```
[qBittorrent] â†’ MenÃº â†’ Preferencias (o Ctrl+Shift+P)
```

### Paso 2: Busca "Acciones personalizadas" (Custom actions)

```
Preferencias â†’ Ejecutar acciones personalizadas
             (o "Behaviour â†’ Run custom action on torrent completion")
```

### Paso 3: Crea nueva acciÃ³n (+Agregar)

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ NUEVA ACCIÃ“N PERSONALIZADA                  â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                             â”‚
â”‚ Nombre de la acciÃ³n:                        â”‚
â”‚ â”œâ”€ [TelegramNotifier]                       â”‚
â”‚                                             â”‚
â”‚ Programa:                                   â”‚
â”‚ â”œâ”€ [powershell.exe]                         â”‚
â”‚                                             â”‚
â”‚ Argumentos:                                 â”‚
â”‚ â”œâ”€ [-ExecutionPolicy Bypass -File          â”‚
â”‚ â”‚   "C:\Users\grau_\Downloads\             â”‚
â”‚ â”‚    TelegramNotifier\core\                 â”‚
â”‚ â”‚    TelegramNotifier.ps1" "%N" "%F"]       â”‚
â”‚                                             â”‚
â”‚ [âœ“] Ejecutar en sistema                     â”‚
â”‚                                             â”‚
â”‚ Evento:                                     â”‚
â”‚ â”œâ”€ [âœ“] Torrent completado                  â”‚
â”‚                                             â”‚
â”‚ [Aplicar] [Aceptar]                         â”‚
â”‚                                             â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### Paso 4: ExplicaciÃ³n de Variables qBittorrent

```
%N  = Nombre del torrent (ej: "Serie S01E01 2160p.mkv")
%F  = Ruta del archivo/carpeta descargado
%D  = Ruta del directorio de descarga
%I  = ID del torrent
```

### Paso 5: Prueba

```
1. AÃ±ade un torrent pequeÃ±o a qBittorrent
2. Espera a que termine
3. Verifica:
   - Log en: C:\Users\grau_\Downloads\TelegramNotifier\core\logs\
   - Telegram: DeberÃ­a recibir notificaciÃ³n con poster
```

### Paso 6: Verificar que funciona

```powershell
# En PowerShell, ver Ãºltimas lÃ­neas del log
Get-Content "C:\Users\grau_\Downloads\TelegramNotifier\core\logs\TelegramNotifier_*.log" -Tail 20

# Buscar lÃ­neas de Ã©xito:
# [SUCCESS] NotificaciÃ³n Telegram enviada (con poster)
# [SUCCESS] NotificaciÃ³n Telegram enviada (texto)
```

---

## ðŸ“š ANÃLISIS EXHAUSTIVO: CÃ“MO FUNCIONA TODO (100%)

### NIVEL 1: ARQUITECTURA GENERAL

**Modelo de Capas**

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚          INTERFAZ: qBittorrent                    â”‚
â”‚    (Externo, dispara el script)                   â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                      â”‚
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚      ORQUESTADOR: TelegramNotifier.ps1             â”‚
â”‚  â€¢ Carga las 4 librerÃ­as                          â”‚
â”‚  â€¢ Coordina flujo principal                       â”‚
â”‚  â€¢ Maneja parÃ¡metros                             â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                      â”‚
    â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
    â”‚                 â”‚                 â”‚
â”Œâ”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”  â”Œâ”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”  â”Œâ”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ LOGGER   â”‚  â”‚  UTILITIES    â”‚  â”‚ CACHE-MGR   â”‚
â”‚          â”‚  â”‚               â”‚  â”‚             â”‚
â”‚ Logging  â”‚  â”‚ â€¢ Parsing     â”‚  â”‚ â€¢ BÃºsqueda  â”‚
â”‚ RotaciÃ³n â”‚  â”‚ â€¢ AnÃ¡lisis    â”‚  â”‚ â€¢ Fuzzy     â”‚
â”‚ Niveles  â”‚  â”‚ â€¢ DetecciÃ³n   â”‚  â”‚ â€¢ Sync JSON â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â”‚ â€¢ MÃ©tricas    â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
              â””â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                     â”‚
                â”Œâ”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
                â”‚ PLEX-FUNCTIONSâ”‚
                â”‚                â”‚
                â”‚ â€¢ API REST     â”‚
                â”‚ â€¢ Scoring      â”‚
                â”‚ â€¢ Auto-cache   â”‚
                â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
    â”‚
    â””â”€â–¶ Base de datos local
    â””â”€â–¶ API Plex (HTTP)
    â””â”€â–¶ Telegram Bot API
```

### NIVEL 2: FLUJO DETALLADO DE UNA EJECUCIÃ“N

**Ejemplo Real: "The Mandalorian S02E08 2160p AMZN WEB-DL.mkv"**

**FASE 1: INICIALIZACIÃ“N (10-20ms)**

```
1. qBittorrent ejecuta: 
   powershell.exe -ExecutionPolicy Bypass -File "...\TelegramNotifier.ps1" \
     "The Mandalorian S02E08 2160p AMZN WEB-DL.mkv" \
     "G:\SERIES\THE_MANDALORIAN"

2. TelegramNotifier.ps1 inicia
   - Lee parÃ¡metros: $TorrentName, $ContentPath
   - Calcula $BasePath usando $PSScriptRoot (garantiza rutas correctas)
   - Carga librerÃ­as via dot-source:
     . logger.ps1       â† Inicializa logs
     . utilities.ps1    â† Funciones helper
     . cache-manager.ps1â† Gestor cachÃ©
     . plex-functions.ps1â† BÃºsqueda Plex
   
3. Initialize-Logger (de logger.ps1)
   - Crea carpeta: core/logs/
   - Abre archivo: TelegramNotifier_20260701.log
   - Escribe primer timestamp
```

**FASE 2: PARSING (5-10ms)**

```
Entrada: "The Mandalorian S02E08 2160p AMZN WEB-DL.mkv"

FunciÃ³n: Normalize-Name (utilities.ps1)
  "the mandalorian s02e08 2160p amzn web-dl.mkv"
  â†’ "the-mandalorian-s02e08-2160p-amzn-web-dl"

FunciÃ³n: Get-CleanName (utilities.ps1)
  "the-mandalorian-s02e08-2160p-amzn-web-dl"
  â†’ "the-mandalorian-s02e08"
  (quita resoluciÃ³n y todo lo posterior)

FunciÃ³n: Get-PatternDetected (utilities.ps1)
  Input: "the-mandalorian-s02e08"
  Regex: ^(.*?)-s(\d{1,2})e(\d{1,2})(?:-|$)
  Match âœ…
  Extrae: 
    - Title: "the-mandalorian" â†’ Matches[1]
    - Season: 2
    - Episode: 8
  Retorna: "EPISODIO"

Funciones adicionales de utilities.ps1:
  â€¢ Get-Resolution("the-mandalorian-s02e08-2160p...")
    â†’ "2160p"
  
  â€¢ Get-SizeGB("G:\SERIES\THE_MANDALORIAN")
    â†’ [calcula todos los .mkv/.mp4/.avi recursivamente]
    â†’ 45.3 GB
  
  â€¢ Count-Episodes("G:\SERIES\THE_MANDALORIAN")
    â†’ 16 archivos de video encontrados
  
  â€¢ Get-TechnicalTags("the-mandalorian-s02e08-2160p-amzn-web-dl")
    â†’ { RESOLUCION: "2160p", CODEC: [detecta si hay HEVC/H264], AUDIO: [detecta idiomas] }

Salida de Fase 2:
  DetectedMetadata = @{
    Title = "The Mandalorian"  (despuÃ©s Convert-Title)
    Type = "EPISODIO"
    Season = 2
    Episode = 8
    Year = $null
  }
```

**FASE 3: BÃšSQUEDA DE POSTER (0-2000ms)**

**Ruta A: CACHÃ‰ HIT (0ms - 99% de casos despuÃ©s de primera ejecuciÃ³n)**

```
FunciÃ³n: Initialize-PlexCache (cache-manager.ps1)
  - Verifica $script:PlexCacheLoaded
  - SI estÃ¡ ya cargado â†’ Skip (usa array en memoria)
  - NO â†’ Lee core/config/plex_cache.json
  - Parsea 108 tÃ­tulos en $script:PlexCache array
  - Marca $script:PlexCacheLoaded = $true

FunciÃ³n: Get-PosterByCache (cache-manager.ps1)
  Input: "The Mandalorian"
  
  Intento 1: Exact Match (100%)
    Busca en cachÃ©: titulo_normalizado == "themandalorian"
    âœ… ENCONTRADO en posiciÃ³n 45
    Retorna: {
      found = $true
      method = "cache_exact"
      url = "http://127.0.0.1:32400/library/metadata/8030/thumb/1782873896?X-Plex-Token=..."
      score = 100
      title = "The Mandalorian"
      ratingKey = "8030"
    }

Salida Fase 3A: PosterUrl = "http://127.0.0.1:32400/..."
Tiempo total: 0ms (ya estÃ¡ en memoria)
```

**Ruta B: API FALLBACK (500ms-2s - Si no en cachÃ©)**

```
FunciÃ³n: Get-PlexPoster (plex-functions.ps1)
  Input: Title="Test Series", Type="EPISODIO"
  
  Paso 1: Llamada HTTP a Plex API
    URL: http://127.0.0.1:32400/search?query=Test+Series&X-Plex-Token=...&type=8
    Tipo=8 significa buscar solo episodios
    HTTP GET â†’ Respuesta XML
  
  Paso 2: Parse XML response
    <MediaContainer>
      <Video ratingKey="5001" title="Test Series S02E08">
        <thumb>/library/metadata/5001/thumb/...</thumb>
      </Video>
    </MediaContainer>
  
  Paso 3: Score resultados
    FunciÃ³n: Get-PlexMatchScore (plex-functions.ps1)
      Calcula:
        - File path match: 0-100
        - Title fuzzy match: 0-50
        - Year match: 0-40
        - Season/Episode match: 0-60
        Total score: suma ponderada
  
  Paso 4: Si mejor score > threshold (70%)
    â€¢ Extrae URL poster
    â€¢ Actualiza cachÃ© (Add-ToCache)
      - Agrega a $script:PlexCache array
      - Escribe en core/config/plex_cache.json
      - Actualiza metadata (lastUpdated, totalItems)

Salida Fase 3B: PosterUrl o $null
Tiempo total: 500-2000ms
```

**FASE 4: ENVÃO TELEGRAM (1000-3000ms)**

```
FunciÃ³n: Send-TelegramNotification (TelegramNotifier.ps1)
  Input: $Message, $PosterUrl, $BotToken, $ChatID
  
  ParÃ¡metros globales (de lÃ­nea 20-21):
    $BotToken = "8755898341:AAFSxCy9zjYS_rLl-kFpVPCmJ3V2XLjKjYg"
    $ChatID = "-1004350117652"
  
  Rama A: CON POSTER
    1. Descarga JPG desde Plex a $env:TEMP
    2. Construye multipart form:
       - chat_id = "-1004350117652"
       - photo = @"C:\Users\...\telegram_poster_20260701141525.jpg"
       - caption = "EPISODIO DESCARGADO\n\nThe Mandalorian\nT02 - E08\n\n2160p\n45.3 GB"
       - parse_mode = "HTML"
    3. Ejecuta curl.exe:
       curl.exe -X POST "https://api.telegram.org/bot{TOKEN}/sendPhoto" \
         -F "chat_id=-1004350117652" \
         -F "photo=@{file}" \
         -F "caption={message}" \
         -F "parse_mode=HTML"
    4. Telegram API responde con JSON (OK/ERROR)
    5. Elimina archivo temporal JPG
    6. Write-Log "NotificaciÃ³n Telegram enviada (con poster)" -Level "SUCCESS"

  Rama B: SIN POSTER
    1. Construye JSON:
       {
         "chat_id": "-1004350117652",
         "text": "EPISODIO DESCARGADO\n\nThe Mandalorian\nT02 - E08\n\n2160p\n45.3 GB",
         "parse_mode": "HTML"
       }
    2. Invoke-RestMethod POST a Telegram API /sendMessage
    3. Write-Log "NotificaciÃ³n Telegram enviada (texto)" -Level "SUCCESS"
```

**FASE 5: REGISTRO EN LOGS (5ms)**

```
FunciÃ³n: Write-Log (logger.ps1)
  Se ejecuta mÃºltiples veces durante todo el flujo
  
  Cada llamada:
    â€¢ Construye timestamp: [2026-07-01 14:15:25]
    â€¢ Construye nivel: [INFO], [WARNING], [ERROR], [SUCCESS]
    â€¢ Coloca color en consola: Verde=SUCCESS, Rojo=ERROR, etc.
    â€¢ Escribe en archivo: core/logs/TelegramNotifier_20260701.log
    â€¢ Verifica si archivo > 5MB
      SI â†’ Rotate-Log crea nuevo con timestamp
  
  Ejemplo de log generado:
    [2026-07-01 14:15:25] [INFO] ========================================
    [2026-07-01 14:15:25] [INFO] Procesando torrent: The Mandalorian S02E08...
    [2026-07-01 14:15:25] [INFO] Ruta: G:\SERIES\THE_MANDALORIAN
    [2026-07-01 14:15:25] [INFO] Tipo: EPISODIO (S02E08)
    [2026-07-01 14:15:25] [INFO] TÃ­tulo detectado: The Mandalorian
    [2026-07-01 14:15:25] [INFO] Iniciando bÃºsqueda de poster...
    [2026-07-01 14:15:25] [INFO] Inicializando cachÃ©...
    [2026-07-01 14:15:25] [INFO] CachÃ© cargado: 108 tÃ­tulos
    [2026-07-01 14:15:25] [INFO] Poster encontrado en cachÃ© (mÃ©todo: cache_exact, score: 100%)
    [2026-07-01 14:15:25] [SUCCESS] Poster encontrado: http://127.0.0.1:32400/...
    [2026-07-01 14:15:26] [SUCCESS] NotificaciÃ³n Telegram enviada (con poster)
    [2026-07-01 14:15:26] [INFO] ========================================
```

**TOTAL TIEMPO DE EJECUCIÃ“N**
```
CachÃ© hit:     15-50ms (parsing + logging)
API fallback:  600-2100ms (API + Telegram)
Promedio:      100-200ms
```

### NIVEL 3: SISTEMA DE TESTING

**Archivo: test/TelegramTorrent_Test.ps1**

```
Â¿QuÃ© es?
  Suite completa de pruebas automatizadas con 237 torrents reales

Â¿CÃ³mo funciona?
  1. Lee lista de torrents desde recursos/torrents.csv
  2. Para cada torrent:
     â€¢ Ejecuta bÃºsqueda (igual que producciÃ³n)
     â€¢ Captura resultado: {found, method, url, score}
     â€¢ Guarda en JSON
  3. Genera estadÃ­sticas: % encontrados, tiempos, mÃ©todos
  4. Produce reporte HTML con imÃ¡genes de posters

Resultados actuales:
  â€¢ 237 torrents totales
  â€¢ 210 encontrados (88.61%)
  â€¢ 27 no encontrados (11.39%)
  â€¢ Tiempo total: 4.63 segundos
  â€¢ MÃ©todos: cache_exact (>90%), cache_fuzzy (~5%), api (~5%)

CÃ³mo ejecutar:
  cd test
  .\test_v4_wrapper.ps1                # Test completo (237 torrents)
  .\test_v4_wrapper.ps1 -QuickTest     # Test rÃ¡pido (10 torrents)
  .\run_test_pipeline.ps1              # Test + reporte HTML
```

**Archivo: test/validation/AnalyzeResults.ps1**

```
Â¿QuÃ© es?
  Generador de reportes HTML con visualizaciÃ³n de posters

Â¿QuÃ© genera?
  â€¢ test/results/analisis/report_YYYYMMDD.html
  â€¢ Tablas con: tÃ­tulo, mÃ©todo, score, imagen
  â€¢ GrÃ¡ficos de distribuciÃ³n
  â€¢ MÃ©tricas de cobertura

Ejemplo de tabla HTML:
  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
  â”‚ The Mandalorian   â”‚ cache_exact â”‚ 100% â”‚ [IMG] â”‚
  â”‚ Breaking Bad S03  â”‚ cache_fuzzy â”‚  89% â”‚ [IMG] â”‚
  â”‚ Desconocida       â”‚ no_match    â”‚  0%  â”‚ [X]   â”‚
  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### NIVEL 4: SISTEMA DE CACHÃ‰

**Archivo: core/config/plex_cache.json**

```json
Estructura completa:
{
  "version": "1.0",
  "lastUpdated": "2026-07-01T14:15:25Z",
  "totalItems": 108,
  "cache": [
    {
      "titulo_normalizado": "themandalorian",
      "titulo_original": "The Mandalorian",
      "ratingKey": "8030",
      "tipo": "SERIE",
      "poster_url": "http://127.0.0.1:32400/library/metadata/8030/thumb/...",
      "year": null
    },
    {
      "titulo_normalizado": "breakingbad",
      "titulo_original": "Breaking Bad",
      "ratingKey": "5102",
      "tipo": "SERIE",
      "poster_url": "...",
      "year": null
    },
    ...108 items total
  ]
}

Algoritmo de bÃºsqueda:
  1. Normalizar bÃºsqueda: "ThE mAnDaLoRiAn" â†’ "themandalorian"
  2. Exact match: Â¿titulo_normalizado == bÃºsqueda?
     âœ… â†’ Retorna con score 100%
  3. Fuzzy match: Character-counting algorithm
     âœ… Si score >= 85% â†’ Retorna
  4. No encontrado â†’ API fallback

CaracterÃ­sticas:
  â€¢ Auto-actualizado: Cuando encuentra algo nuevo
  â€¢ DeduplicaciÃ³n: No duplica por ratingKey
  â€¢ Versionado: metadata para control de cambios
```

### NIVEL 5: SISTEMA DE LOGS

**Archivo: core/logs/TelegramNotifier_YYYYMMDD.log**

```
Niveles disponibles:
  [INFO]    â†’ InformaciÃ³n general (blanco)
  [SUCCESS] â†’ OperaciÃ³n exitosa (verde)
  [WARNING] â†’ Posible problema (amarillo)
  [ERROR]   â†’ Error crÃ­tico (rojo)

RotaciÃ³n automÃ¡tica:
  â€¢ Cada dÃ­a nuevo â†’ nuevo archivo
  â€¢ Si excede 5MB â†’ Renombra con timestamp
  
  Ejemplo:
    TelegramNotifier_20260701.log (450KB)
    TelegramNotifier_20260702.log (320KB)
    TelegramNotifier_20260701_141525_rotated.log (5.2MB)

Cada entrada incluye:
  Timestamp (ms precision)
  Nivel de severidad
  Mensaje descriptivo

Ejemplo log completo:
  [2026-07-01 14:15:25] [INFO] ========================================
  [2026-07-01 14:15:25] [INFO] Procesando torrent: The Mandalorian S02E08 2160p...
  [2026-07-01 14:15:25] [INFO] Ruta: G:\SERIES\THE_MANDALORIAN
  [2026-07-01 14:15:25] [INFO] Tipo: EPISODIO (S02E08)
  [2026-07-01 14:15:25] [INFO] TÃ­tulo detectado: The Mandalorian
  [2026-07-01 14:15:25] [INFO] Iniciando bÃºsqueda de poster para 'The Mandalorian' (Tipo: EPISODIO)
  [2026-07-01 14:15:25] [INFO] Inicializando cachÃ©...
  [2026-07-01 14:15:25] [INFO] Leyendo cachÃ© persistente desde: C:\Users\grau_\Downloads\TelegramNotifier\core\config\plex_cache.json
  [2026-07-01 14:15:25] [INFO] CachÃ© cargado desde archivo: 108 tÃ­tulos
  [2026-07-01 14:15:25] [INFO] Poster encontrado en cachÃ© (mÃ©todo: cache_exact, score: 100%)
  [2026-07-01 14:15:25] [SUCCESS] Poster encontrado: http://127.0.0.1:32400/library/metadata/8030/thumb/1782873896?X-Plex-Token=...
  [2026-07-01 14:15:26] [SUCCESS] NotificaciÃ³n Telegram enviada (con poster)
  [2026-07-01 14:15:26] [INFO] ========================================
```

### NIVEL 6: INTEGRACIÃ“N PLEX

**API Endpoint: http://127.0.0.1:32400**

```
AutenticaciÃ³n: Token en query parameter
  http://127.0.0.1:32400/search?X-Plex-Token=Yt-aqViZD-ydpysRvGyP

Tipos de bÃºsqueda:
  type=1   â†’ Movies
  type=2   â†’ Shows (series)
  type=8   â†’ Episodes (episodios)
  (vacÃ­o)  â†’ Todo

Respuesta XML:
  <MediaContainer>
    <Video ratingKey="8030" title="The Mandalorian" type="show">
      <thumb>/library/metadata/8030/thumb/1782873896</thumb>
      <art>/library/metadata/8030/art/1782873896</art>
    </Video>
  </MediaContainer>

ObtenciÃ³n de poster:
  URL base: http://127.0.0.1:32400
  + thumb: /library/metadata/{ratingKey}/thumb/{timestamp}
  + Token: ?X-Plex-Token={token}
  
  Resultado: http://127.0.0.1:32400/library/metadata/8030/thumb/1782873896?X-Plex-Token=...
```

---

## âœ¨ CaracterÃ­sticas Principales

### ðŸš€ Rendimiento Optimizado
- **0ms**: Carga cachÃ© desde archivo (array en memoria)
- **5-20ms**: BÃºsqueda en cachÃ© local (fuzzy matching)
- **500ms-2s**: BÃºsqueda en Plex API (HTTP + parsing)
- **Telegram**: 1-3s (descarga + envÃ­o)

### ðŸ”’ CachÃ© Persistente
- **108 tÃ­tulos** precargados
- **Auto-actualizaciÃ³n**: Nuevos tÃ­tulos agregados automÃ¡ticamente
- **BÃºsqueda exacta + fuzzy** (85%+ threshold)
- **DeduplicaciÃ³n**: No duplica por ratingKey

### ðŸ“Š Testing Integrado
- **237 torrents** en dataset de prueba
- **88.61% cobertura** de bÃºsqueda
- **Reportes HTML** con imÃ¡genes de posters
- **MÃ©tricas detalladas** por mÃ©todo

### ðŸ“ Sistema de Logging
- **RotaciÃ³n automÃ¡tica** (diaria + 5MB)
- **4 niveles**: INFO, WARNING, ERROR, SUCCESS
- **Timestamps** con precisiÃ³n de milisegundos
- **Colores en consola** para fÃ¡cil identificaciÃ³n

### ðŸ”„ Modular y Escalable
- **4 librerÃ­as independientes** (logger, utilities, cache, plex)
- **SeparaciÃ³n clara** de responsabilidades
- **FÃ¡cil de extender** sin afectar producciÃ³n
- **Test aislado** de core/ para desarrollo seguro

---

## ðŸŽ¯ GuÃ­a RÃ¡pida de Uso

### Usar en PRODUCCIÃ“N

```powershell
# Desde qBittorrent (automÃ¡tico)
powershell.exe -ExecutionPolicy Bypass -File "C:\Users\grau_\Downloads\TelegramNotifier\core\TelegramNotifier.ps1" "%N" "%F"

# O manualmente
cd C:\Users\grau_\Downloads\TelegramNotifier\core
.\TelegramNotifier.ps1 -TorrentName "Serie S01E01.mkv" -ContentPath "D:\SERIES"
```

### Desarrollar / Testing

```powershell
cd test

# Test rÃ¡pido (10 torrents)
.\test_v4_wrapper.ps1 -QuickTest

# Test completo (237 torrents)
.\test_v4_wrapper.ps1

# Pipeline: test + reporte HTML
.\run_test_pipeline.ps1
```

### Hacer Backup

```powershell
cd backups

# Backup producciÃ³n
.\backup-production.ps1

# Backup completo
.\backup-production.ps1 -FullBackup

# Ver backups
Get-ChildItem *.zip | Sort-Object LastWriteTime -Descending
```

---

## ðŸ“Š EstadÃ­sticas Proyecto

| MÃ©trica | Valor |
|---------|-------|
| Scripts de producciÃ³n | 1 principal + 4 libs |
| LÃ­neas de cÃ³digo producciÃ³n | 625+ |
| Scripts de testing | 5+ |
| Funciones totales | 30+ |
| CachÃ© tÃ­tulos precargados | 108 |
| Dataset de test | 237 torrents |
| Cobertura bÃºsqueda | 88.61% (210/237) |
| Tiempo test completo | 4.63 segundos |
| CodificaciÃ³n archivos | UTF-8 BOM |
| Uptime diseÃ±o | 24/7 con rotaciÃ³n logs |

---

## ðŸ”§ ConfiguraciÃ³n Inicial

### 1. Verificar Plex

```powershell
# Test conexiÃ³n a Plex
$PlexUrl = "http://127.0.0.1:32400"
$Token = "Yt-aqViZD-ydpysRvGyP"

Invoke-RestMethod -Uri "$PlexUrl/identity?X-Plex-Token=$Token"
# Si funciona, devuelve: <Version>1.28.0.5999</Version> (o similar)
```

### 2. Verificar Token Telegram

```powershell
# Test bot Telegram
$BotToken = "8755898341:AAFSxCy9zjYS_rLl-kFpVPCmJ3V2XLjKjYg"
$ChatID = "-1004350117652"

curl.exe -s "https://api.telegram.org/bot$BotToken/getMe" | ConvertFrom-Json
# Si funciona, devuelve informaciÃ³n del bot
```

### 3. Actualizar Overrides (opcional)

```json
// core/config/title_overrides.json
{
  "the-boys": "The Boys",
  "breaking-bad": "Breaking Bad",
  "game-of-thrones": "Game of Thrones"
}
```

---

## ðŸ“š DocumentaciÃ³n Completa

- **[core/README.md](core/README.md)** - Detalles tÃ©cnicos del core
- **[backups/RESTORE.md](backups/RESTORE.md)** - GuÃ­a completa de backups
- **[TELEGRAM_CONFIG.md](TELEGRAM_CONFIG.md)** - ConfiguraciÃ³n Telegram
- **[recursos/README_CACHE.md](recursos/README_CACHE.md)** - Sistema cachÃ© en profundidad

---

## ðŸ› Troubleshooting

| Problema | SÃ­ntoma | SoluciÃ³n |
|----------|---------|----------|
| **No encuentra Plex** | `Plex devolvio 0 items` en log | Verificar IP/puerto/token en TelegramNotifier.ps1 (lÃ­nea 25-26) |
| **CachÃ© vacÃ­o** | Primer uso toma 2s+ | Normal, se genera automÃ¡ticamente |
| **Logs ausentes** | Carpeta logs/ no existe | Crear: `mkdir core\logs` |
| **Telegram no envÃ­a** | `Error enviando Telegram` en log | Verificar token y chat_id (lÃ­nea 20-21) |
| **Acceso denegado** | `Cannot execute script` | Usar `-ExecutionPolicy Bypass` |
| **Rutas incorrectas** | Logs en lugar equivocado | Usar comando completo desde qBittorrent |

---

## ðŸ“ž Soporte RÃ¡pido

```powershell
# Ver los 20 Ãºltimos logs
Get-Content "core\logs\TelegramNotifier_*.log" -Tail 20

# Resetear cachÃ© (regenera automÃ¡ticamente)
Remove-Item "core\config\plex_cache.json"

# Limpiar logs antiguos
Get-ChildItem "core\logs\*.log" | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | Remove-Item

# Hacer backup ahora
cd backups
.\backup-production.ps1
```

---

## ðŸŽ“ Estructura de Aprendizaje

1. **Comenzar**: Lee este README (ðŸŽ¯ Resumen ejecutivo)
2. **Configurar**: Sigue "ConfiguraciÃ³n qBittorrent"
3. **Probar**: Ejecuta un torrent de prueba
4. **Entender**: Lee "AnÃ¡lisis exhaustivo" (NIVEL 1-6)
5. **Desarrollar**: Explora test/ para extensiones
6. **Deploy**: Usa backups/ para sincronizar

---

## ðŸ“ˆ VersiÃ³n

- **VersiÃ³n**: 1.1
- **Fecha**: 2026-07-01
- **Status**: âœ… ProducciÃ³n
- **Cobertura**: 88.61% (237 torrents)
- **Ãšltima actualizaciÃ³n**: 2026-07-01
  - âœ… Telegram automÃ¡tico en producciÃ³n (-SendTelegram = $true)
  - âœ… Todos los .ps1 en UTF-8 BOM
  - âœ… Logs con $PSScriptRoot para rutas correctas
  - âœ… 4 librerÃ­as modulares probadas

---

**Para empezar**: Configura qBittorrent siguiendo la "GuÃ­a Visual", luego aÃ±ade un torrent de prueba.  
**Para debug**: Revisa `core\logs\TelegramNotifier_*.log`  
**Para soporte**: Lee la secciÃ³n "Troubleshooting" o "AnÃ¡lisis exhaustivo"