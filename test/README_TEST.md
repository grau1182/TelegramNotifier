# Guía del entorno de test

Documentación del entorno `test/` y su relación con producción (`core/`). El objetivo del test es **replicar el escenario completo de producción**, salvo cuando se activa explícitamente el modo rápido.

---

## Resumen: producción vs test

| Aspecto | Producción (`core/`) | Test (`test/`) |
|---------|----------------------|----------------|
| Script principal | `core/TelegramNotifier.ps1` | `test/TelegramTorrent_Test.ps1` |
| Punto de entrada qBittorrent | Sí | No (manual o wrapper) |
| Envío Telegram | Activado por defecto | Omitido en `TestMode` |
| Librerías | `core/lib/*.ps1` | `test/lib/*.ps1` (copia espejo) |
| Caché Plex | `recursos/plex_cache.json` | Mismo archivo compartido |
| Partial scan Plex | Activado (`SkipPlexScan=$false`) | **Igual por defecto** |
| Modo rápido | No disponible | `-SkipPlexScan` o `-QuickTest` |
| Captura JSON resultados | No | Sí (`test/results/`) |
| Logs en disco | `core/logs/TelegramNotifier_YYYYMMDD.log` | Solo si `-TestMode:$false` → `test/logs/TelegramNotifier_Test.log` |

> **Nota:** Con `-TestMode $true` (default), `Write-Log` no escribe a fichero; la salida va a consola y a `test/results/`.

---

## Flujo de búsqueda de poster (v2 — julio 2026)

Ambos entornos comparten la misma lógica en `plex-functions.ps1`:

```
1. Caché (recursos/plex_cache.json)
   └─ Hit → poster instantáneo

2. Partial scan Plex (solo si SkipPlexScan=$false y hay ContentPath)
   ├─ Resolve-PlexSectionForPath → detecta sección (G:\PELIS, G:\SERIES...)
   ├─ Invoke-PlexPartialScan → fuerza indexación del archivo
   └─ Wait-ForPlexItem → polling cada 5s, máx. 60s

3. Lookup por ruta (items recientes en Plex)
   └─ Match por ContentPath aunque el título en Plex sea distinto

4. Búsqueda progresiva por título
   ├─ Título completo: "Kingsman, El Servicio Secreto"
   ├─ Pre-coma: "Kingsman"
   └─ Primera palabra significativa
   └─ Scoring por año + raíz de título (ES vs EN sin mapeos manuales)

5. Add-ToCache + Add-CacheAliases (alias automático)
   └─ Guarda título del torrent como alias si difiere del título Plex
```

**No se usa `title_overrides.json`**. Los títulos en español se resuelven con búsqueda progresiva, scoring por año y aliases automáticos en caché.

---

## Parámetros de Plex (compartidos)

| Parámetro | Default producción | Default test | Descripción |
|-----------|-------------------|--------------|-------------|
| `PlexScanPollSeconds` | `5` | `5` | Segundos entre reintentos tras partial scan |
| `PlexScanPollMaxAttempts` | `12` | `12` | Intentos máximos (≈60 s total) |
| `SkipPlexScan` | `$false` | `$false` | Si `$true`, salta FASE 1 (scan + path lookup) |
| `PlexMoviePathPrefix` | `G:\PELIS` | `G:\PELIS` | Fallback para resolver sección películas |
| `PlexSeriesPathPrefix` | `G:\SERIES` | `G:\SERIES` | Fallback para resolver sección series |

---

## Modos de ejecución

### 1. Producción — torrent de prueba manual

Simula lo que hace qBittorrent al completar una descarga:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\core

# Solo buscar poster + log (sin Telegram)
.\TelegramNotifier.ps1 `
  -TorrentName "Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -ContentPath "G:\PELIS\Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -SendTelegram:$false

# Con notificación Telegram
.\TelegramNotifier.ps1 `
  -TorrentName "Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -ContentPath "G:\PELIS\Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -SendTelegram

# Ajustar tiempos de polling
.\TelegramNotifier.ps1 `
  -TorrentName "..." `
  -ContentPath "G:\PELIS\..." `
  -PlexScanPollSeconds 10 `
  -PlexScanPollMaxAttempts 18 `
  -SendTelegram:$false
```

Vía `run.ps1`:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\core
.\run.ps1 -TorrentName "minority-report-(2002).mkv" -ContentPath "G:\PELIS\Minority Report (2002).mkv"
```

### 2. Test — un torrent (paridad con producción)

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test

.\TelegramTorrent_Test.ps1 `
  -TorrentName "Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -ContentPath "G:\PELIS\Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -TestMode
```

Incluye partial scan + polling (igual que producción). No envía Telegram.

### 3. Test — modo rápido manual (`SkipPlexScan`)

Omite partial scan y polling. Solo caché + búsqueda progresiva por título. Útil para iterar sin esperar 60 s por torrent:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test

.\TelegramTorrent_Test.ps1 `
  -TorrentName "Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -ContentPath "G:\PELIS\Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -TestMode `
  -SkipPlexScan
```

### 4. Test — suite completa (modo largo, paridad producción)

Procesa todos los torrents de `recursos/torrents.csv` con scan Plex activo:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test
.\test_v4_wrapper.ps1
```

Pipeline completo con análisis HTML:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test
.\run_test_pipeline.ps1
```

**Nota:** puede tardar mucho (hasta ~60 s por torrent sin hit de caché).

### 5. Test — suite rápida (`QuickTest`, 10 torrents)

Equivalente a modo largo pero con `-SkipPlexScan` y solo 10 entradas del CSV:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test
.\test_v4_wrapper.ps1 -QuickTest

# O vía pipeline
.\run_test_pipeline.ps1 -QuickTest
```

### 6. Validación Kingsman (scoring sin Plex)

Comprueba variantes de título y umbrales de scoring para los 3 casos del log:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test\validation
.\ValidateKingsmanSearch.ps1
```

---

## Estructura del entorno test

```
test/
├── README_TEST.md                  ← Este archivo
├── TelegramTorrent_Test.ps1        ← Script principal de test
├── test_v4_wrapper.ps1             ← Procesa recursos/torrents.csv
├── run_test_pipeline.ps1           ← Wrapper + AnalyzeResults.ps1
├── PLEXPOSTER_IMPROVEMENTS.md      ← Historial de diseño (referencia)
│
├── lib/                            ← Espejo de core/lib/ (sin logger.ps1)
│   ├── utilities.ps1               ← Split-TitleVariants
│   ├── cache-manager.ps1           ← Add-CacheAliases, Save-CacheToFile
│   └── plex-functions.ps1          ← Scan, path lookup, búsqueda progresiva
│
├── validation/
│   ├── ValidateKingsmanSearch.ps1  ← Test unitario Kingsman
│   ├── ValidatePlexImprovements.ps1
│   ├── ValidateTest.ps1
│   ├── AnalyzeResults.ps1          ← Informe HTML
│   ├── ConsolidateResults.ps1
│   └── OrganizeResults.ps1
│
├── logs/                           ← Solo si TestMode=$false
│   └── TelegramNotifier_Test.log
│
└── results/                        ← JSON generados en TestMode
    └── torrents.json
```

---

## Qué buscar en los logs

### Producción (`core/logs/TelegramNotifier_YYYYMMDD.log`)

```
[INFO] Escaneo parcial activado: section=1 path=G:\PELIS\...
[INFO] Intento de búsqueda por ruta 1/12 sin resultado, esperando 5s...
[INFO] Item encontrado por ruta (intento 2, puntuación 100): Kingsman: Servicio secreto
```

O, si falla path lookup:

```
[INFO] Queries progresivas: Kingsman, El Servicio Secreto | Kingsman
[INFO] Plex devolvio 1 items para query 'Kingsman' (pelicula)
[INFO]   Match aceptable (score 75): Kingsman: Servicio secreto
[INFO] Caché actualizado: Nuevo título 'Kingsman: Servicio secreto' agregado
```

### Test con SkipPlexScan

```
[INFO] SkipPlexScan activo, omitiendo partial scan
[INFO] Queries progresivas: ...
```

---

## Diagnóstico Plex (servidor Windows)

```powershell
$PlexToken = "Yt-aqViZD-ydpysRvGyP"

# Ver bibliotecas y section IDs
Invoke-RestMethod "http://127.0.0.1:32400/library/sections?X-Plex-Token=$PlexToken"

# Forzar scan parcial de un archivo
$path = [uri]::EscapeDataString("G:\PELIS\Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv")
Invoke-RestMethod "http://127.0.0.1:32400/library/sections/SECTION_ID/refresh?path=$path&X-Plex-Token=$PlexToken"

# Buscar por título corto
Invoke-RestMethod "http://127.0.0.1:32400/search?query=Kingsman&X-Plex-Token=$PlexToken&type=1"
```

---

## Caché compartida y aliases

Ubicación única: `recursos/plex_cache.json`

Tras encontrar un poster con título distinto al del torrent, se guarda automáticamente un alias:

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

La clave `titulo_normalizado` se genera con `Normalize-CacheKey` (transliteración de acentos/ñ + minúsculas + solo `[a-z0-9]`).

La segunda descarga del mismo contenido con nombre en español será **cache hit** vía alias.

---

## Troubleshooting test vs producción

| Síntoma | Causa probable | Acción |
|---------|----------------|--------|
| Poster en prod, no en test | `-SkipPlexScan` activo | Ejecutar sin `-SkipPlexScan` ni `-QuickTest` |
| Test muy lento | Modo largo con scan activo | Normal; usar `-QuickTest` para iterar |
| `Escaneo parcial activado` no aparece | `SkipPlexScan` o `ContentPath` vacío | Verificar ruta y flag |
| Plex devuelve 0 items | Título ES vs EN | Debería resolverse con query `Kingsman` + año |
| Timeout 60s | Plex tarda en indexar | Aumentar `-PlexScanPollMaxAttempts` |

---

## Referencia rápida de comandos

```powershell
# ── PRODUCCIÓN ──────────────────────────────────────────
cd core
.\TelegramNotifier.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." -SendTelegram:$false

# ── TEST: un torrent (como producción) ─────────────────
cd test
.\TelegramTorrent_Test.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." -TestMode

# ── TEST: un torrent (rápido, sin scan) ────────────────
.\TelegramTorrent_Test.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." -TestMode -SkipPlexScan

# ── TEST: suite completa (lento, como producción) ─────
.\test_v4_wrapper.ps1

# ── TEST: suite rápida (10 torrents, sin scan) ─────────
.\test_v4_wrapper.ps1 -QuickTest

# ── TEST: pipeline completo + HTML ─────────────────────
.\run_test_pipeline.ps1              # largo
.\run_test_pipeline.ps1 -QuickTest   # rápido

# ── VALIDACIÓN Kingsman ────────────────────────────────
.\validation\ValidateKingsmanSearch.ps1
```

---

**Última actualización:** 2026-07-07  
**Versión búsqueda poster:** 2.1 (partial scan + path lookup + búsqueda progresiva)
