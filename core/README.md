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
│   ├── utilities.ps1                # Parseo, Get-MovieTitleAndYear, Split-TitleVariants
│   ├── cache-manager.ps1            # Caché Plex + aliases + fuzzy con filtro de año
│   └── plex-functions.ps1           # Scan Plex, path lookup, búsqueda progresiva
├── logs/                            # Logs de ejecución
└── README.md                        # Este archivo

recursos/plex_cache.json             # Caché compartida (producción + test)
```

## Características

- **Caché persistente** en `recursos/plex_cache.json` (115+ títulos, aliases automáticos)
- **Parseo de películas** con `Get-MovieTitleAndYear`: prioriza `(año)` entre paréntesis sobre números en el título
- **Normalización de claves** con transliteración (`Remove-Accents`: `28 años después` → `28anosdespues`)
- **Partial scan Plex** al completar descarga (indexa el archivo antes de buscar)
- **Lookup por ruta** (`ContentPath`) en items recientes de Plex
- **Búsqueda progresiva** por variantes de título (completo → pre-coma → primera palabra*)
- **Variantes seguras**: no acorta a la primera palabra si el título contiene un año (`Blade Runner 2049`)
- **Caché estricta**: `Resolve-RatingKey` solo exacto/alias; fuzzy solo en `Get-PosterByCache` con filtro de año
- **Scoring inteligente** con año y raíz de título (resuelve ES/EN sin `title_overrides.json`)
- **Logging** con rotación automática

## Uso

### Torrent de prueba (sin Telegram)

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\core

# Caso validado: Blade Runner 2049
.\TelegramNotifier.ps1 `
  -TorrentName "Blade Runner 2049 (2017) [2160p UHD BluRay REMUX HEVC TrueHD 7.1].mkv" `
  -ContentPath "G:\PELIS\Blade Runner 2049 (2017) [2160p UHD BluRay REMUX HEVC TrueHD 7.1].mkv" `
  -SendTelegram:$false

# Caso Kingsman (ES/EN)
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
  ├─ Get-MovieTitleAndYear (películas: año entre paréntesis)
  └─ Get-PlexPoster()
       │
       ├─ FASE 0: Caché (recursos/plex_cache.json)
       │    ├─ Resolve-RatingKey → solo exacto / alias
       │    └─ Get-PosterByCache → exacto, alias, fuzzy ≥85% (+ filtro año)
       │    └─ Hit → return poster URL
       │
       ├─ FASE 1: Partial scan + path lookup (si SkipPlexScan=$false)
       │    ├─ Resolve-PlexSectionForPath(ContentPath)
       │    ├─ Invoke-PlexPartialScan → GET /library/sections/{id}/refresh?path=...
       │    └─ Wait-ForPlexItem → polling Find-PlexItemByPath
       │
       ├─ FASE 2: Búsqueda progresiva (Search-PlexWithQueries)
       │    ├─ Queries: título completo | pre-coma | primera palabra*
       │    └─ Scoring: ruta, título, raíz, año, fuzzy
       │
       └─ Save-PlexPosterResult → Add-ToCache + Add-CacheAliases
```

### Funciones clave (utilities.ps1)

| Función | Responsabilidad |
|---------|-----------------|
| `Get-MovieTitleAndYear` | Parsea título y año de película; prioriza `(YYYY)` sobre `20XX` en el nombre |
| `Get-CleanName` | Elimina resolución y etiquetas técnicas del nombre normalizado |
| `Split-TitleVariants` | Genera variantes de búsqueda; omite primera palabra si hay año en título |
| `Normalize-CacheKey` / `Remove-Accents` | Claves de caché sin acentos ni caracteres especiales |
| `Convert-Title` | Capitalización legible del título detectado |

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
| `Resolve-RatingKey` | Resuelve ratingKey solo por match exacto o alias (sin fuzzy) |
| `Get-PosterByCache` | Búsqueda exacta, alias o fuzzy en caché; recibe `DetectedMetadata` |
| `Test-CacheItemYearMatch` | Filtra entradas de caché por año en películas |
| `Get-FuzzyMatchScore` | Similitud 0-100; bonus Contains solo si `minLen/maxLen ≥ 0.75` |
| `Add-ToCache` | Crea entrada completa o delega aliases si ya existe |
| `Add-CacheAlias` / `Add-CacheAliases` | Añade sinónimos de título (batch) |
| `Get-CacheFileData` / `Save-CacheToFile` | Lectura/escritura centralizada de JSON |

## Parseo de películas

`Get-MovieTitleAndYear` evita confundir números del título con el año de estreno:

| Torrent | Antes (incorrecto) | Ahora (correcto) |
|---------|-------------------|------------------|
| `Blade Runner 2049 (2017) [...].mkv` | Title `Blade Runner`, Year `2049` | Title `Blade Runner 2049`, Year `2017` |
| `Minority Report (2002) [...].mkv` | Title `Minority Report`, Year `2002` | Igual (sin regresión) |
| `2010 The Year We Make Contact (1984)` | — | Title completo, Year `1984` |

## Caché persistente

**Ubicación:** `recursos/plex_cache.json` (compartida con test)

```json
{
  "titulo_original": "Blade Runner 2049",
  "titulo_normalizado": "bladerunner2049",
  "ratingKey": "8190",
  "tipo": "PELICULA",
  "poster_url": "http://127.0.0.1:32400/library/metadata/8190/thumb/...",
  "year": "2017"
}
```

**Reglas de resolución en caché:**

| Operación | Exacto/alias | Fuzzy | Filtro año (películas) |
|-----------|--------------|-------|------------------------|
| `Resolve-RatingKey` | Sí | No | N/A |
| `Get-PosterByCache` | Sí | Sí (≥85%) | Sí |

Los aliases se crean automáticamente cuando el título del torrent difiere del título Plex.

## Logging

```
[INFO] Tipo: PELICULA (2017)
[INFO] Título detectado: Blade Runner 2049
[INFO] Búsqueda poster: título='Blade Runner 2049', RatingKey=''
[INFO] Poster NO encontrado en caché. Intentando API...
[INFO] Escaneo parcial activado: section=1 path=G:\PELIS\...
[INFO] Item encontrado por ruta (intento 1, puntuación 90): Blade Runner 2049
[INFO] Caché actualizado: Nuevo título 'Blade Runner 2049' agregado con RatingKey 8190
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
| Poster de película incorrecta (ej. Blade vs Blade Runner 2049) | Verificar log: título/año parseado. Ejecutar `test/validation/ValidateMovieTitleParse.ps1` |
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
| Caché | [`../recursos/README_CACHE.md`](../recursos/README_CACHE.md) |

---

**Última actualización:** 2026-07-15  
**Versión búsqueda poster:** 2.2 (parseo películas + caché estricta)
