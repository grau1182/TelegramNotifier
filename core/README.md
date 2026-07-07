# TelegramNotifier - Versión Producción

Versión de producción del sistema de notificación de torrents con integración Plex.

Documentación del entorno de test: [`../test/README_TEST.md`](../test/README_TEST.md)

## Contenido

```
core/
├── run.ps1                          # Ejecutable principal
├── TelegramNotifier.ps1             # Script principal (importa librerías)
├── lib/
│   ├── logger.ps1                   # Sistema de logging con rotación
│   ├── utilities.ps1                # Parseo, normalización, Split-TitleVariants
│   ├── cache-manager.ps1            # Caché Plex + aliases automáticos
│   └── plex-functions.ps1           # Scan Plex, path lookup, búsqueda progresiva
├── logs/                            # Logs de ejecución
└── README.md                        # Este archivo

recursos/plex_cache.json             # Caché compartida (producción + test)
```

## Características

- **Caché persistente** en `recursos/plex_cache.json` (112 títulos, aliases automáticos)
- **Normalización de claves** con transliteración (`Remove-Accents`: `28 años después` → `28anosdespues`)
- **Partial scan Plex** al completar descarga (indexa el archivo antes de buscar)
- **Lookup por ruta** (`ContentPath`) en items recientes de Plex
- **Búsqueda progresiva** por variantes de título (completo → pre-coma → primera palabra)
- **Scoring inteligente** con año y raíz de título (resuelve ES/EN sin `title_overrides.json`)
- **Logging** con rotación automática

## Uso

### Torrent de prueba (sin Telegram)

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\core

.\TelegramNotifier.ps1 `
  -TorrentName "Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -ContentPath "G:\PELIS\Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -SendTelegram:$false
```

### Con Telegram

```powershell
.\TelegramNotifier.ps1 `
  -TorrentName "minority-report-(2002).mkv" `
  -ContentPath "G:\PELIS\Minority Report (2002).mkv" `
  -SendTelegram
```

### Vía run.ps1

```powershell
.\run.ps1 -TorrentName "the-boys-s05e01.mkv" -ContentPath "G:\SERIES\The Boys"
```

## Parámetros Plex

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `-PlexScanPollSeconds` | `5` | Intervalo entre reintentos tras partial scan |
| `-PlexScanPollMaxAttempts` | `12` | Máximo de intentos (≈60 s) |
| `-SkipPlexScan` | `$false` | Omitir scan y lookup por ruta |

```powershell
# Más tiempo de espera para bibliotecas lentas
.\TelegramNotifier.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." `
  -PlexScanPollSeconds 10 -PlexScanPollMaxAttempts 18 -SendTelegram:$false
```

## Configuración

### Credenciales (TelegramNotifier.ps1)

```powershell
$PlexUrl   = "http://127.0.0.1:32400"
$PlexToken = "Tu-Token-Plex"
$BotToken  = "Tu-Bot-Token"
$ChatID    = "Tu-Chat-ID"

# Prefijos de rutas Plex (fallback si auto-detect falla)
$script:PlexMoviePathPrefix  = "G:\PELIS"
$script:PlexSeriesPathPrefix = "G:\SERIES"
```

## Arquitectura — flujo de búsqueda de poster

```
Process-Torrent()
  └─ Get-PlexPoster()
       │
       ├─ FASE 0: Caché (recursos/plex_cache.json)
       │    └─ Hit → return poster URL
       │
       ├─ FASE 1: Partial scan + path lookup (si SkipPlexScan=$false)
       │    ├─ Resolve-PlexSectionForPath(ContentPath)
       │    ├─ Invoke-PlexPartialScan → GET /library/sections/{id}/refresh?path=...
       │    └─ Wait-ForPlexItem → polling Find-PlexItemByPath
       │
       ├─ FASE 2: Búsqueda progresiva (Search-PlexWithQueries)
       │    ├─ Queries: título completo | pre-coma | primera palabra
       │    └─ Scoring: ruta, título, raíz, año, fuzzy
       │
       └─ Save-PlexPosterResult → Add-ToCache + Add-CacheAliases
```

### Funciones clave (plex-functions.ps1)

| Función | Responsabilidad |
|---------|-----------------|
| `Get-PlexLibrarySections` | Lista secciones Plex y rutas |
| `Resolve-PlexSectionForPath` | Resuelve sectionId desde ContentPath |
| `Invoke-PlexPartialScan` | Fuerza scan parcial del archivo |
| `Find-PlexItemByPath` | Busca en items recientes por ruta |
| `Wait-ForPlexItem` | Polling post-scan |
| `Get-PlexSearchQueries` / `Split-TitleVariants` | Variantes de búsqueda |
| `Search-PlexWithQueries` | Búsqueda API progresiva |
| `Test-PlexItemAcceptable` | Umbrales de score |
| `Save-PlexPosterResult` | Persiste en caché con aliases |

### Funciones clave (cache-manager.ps1)

| Función | Responsabilidad |
|---------|-----------------|
| `Normalize-CacheKey` | Translitera acentos/ñ y genera clave de búsqueda |
| `Add-ToCache` | Crea entrada completa o delega aliases si ya existe |
| `Add-CacheAlias` / `Add-CacheAliases` | Añade sinónimos de título (batch) |
| `Get-CacheFileData` / `Save-CacheToFile` | Lectura/escritura centralizada de JSON |
| `Get-PosterByCache` | Búsqueda exacta, alias o fuzzy en caché |

## Caché persistente

**Ubicación:** `recursos/plex_cache.json` (compartida con test)

```json
{
  "titulo_original": "Kingsman: El círculo de oro",
  "titulo_normalizado": "kingsmanelcirculodeoro",
  "ratingKey": "8149",
  "tipo": "PELICULA",
  "poster_url": "http://127.0.0.1:32400/library/metadata/8149/thumb/...",
  "year": 2017,
  "aliases": ["Kingsman, El Circulo De Oro"]
}
```

Los aliases se crean automáticamente cuando el título del torrent difiere del título Plex.

## Logging

```
[INFO] Escaneo parcial activado: section=1 path=G:\PELIS\...
[INFO] Intento de búsqueda por ruta 1/12 sin resultado, esperando 5s...
[INFO] Item encontrado por ruta (intento 2, puntuación 100): Kingsman: Servicio secreto
[INFO] Queries progresivas: Kingsman, El Servicio Secreto | Kingsman
[INFO]   Match aceptable (score 75): Kingsman: Servicio secreto
[SUCCESS] Poster encontrado: http://127.0.0.1:32400/...
```

## Diagnóstico Plex

```powershell
# Ver secciones
Invoke-RestMethod "http://127.0.0.1:32400/library/sections?X-Plex-Token=$PlexToken"

# Scan parcial manual
$path = [uri]::EscapeDataString("G:\PELIS\archivo.mkv")
Invoke-RestMethod "http://127.0.0.1:32400/library/sections/SECTION_ID/refresh?path=$path&X-Plex-Token=$PlexToken"
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| Poster no encontrado en descarga reciente | Plex aún no indexó; el partial scan + polling debería resolverlo. Revisar log `Escaneo parcial activado` |
| Título español vs inglés en Plex | Búsqueda progresiva prueba `"Kingsman"` + score por año |
| `ContentPath` vacío | qBittorrent no pasó ruta; solo funciona búsqueda por título |
| Timeout 60s | Aumentar `-PlexScanPollMaxAttempts` |
| Error conexión Plex | Verificar `$PlexUrl` y `$PlexToken` |

## Entornos

| Entorno | Documentación |
|---------|---------------|
| Producción | Este archivo |
| Test | [`../test/README_TEST.md`](../test/README_TEST.md) |

---

**Última actualización:** 2026-07-07  
**Versión búsqueda poster:** 2.1
