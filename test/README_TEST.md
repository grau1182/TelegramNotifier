# Guía del entorno de test

Documentación del entorno `test/` y su relación con producción (`core/`). El objetivo del test es **replicar el escenario completo de producción**, salvo cuando se activa explícitamente el modo rápido.

---

## Resumen: producción vs test

| Aspecto | Producción (`core/`) | Test FULL (`test_v4_wrapper.ps1`) | Test QuickTest / parcial |
|---------|----------------------|-----------------------------------|--------------------------|
| Script principal | `core/TelegramNotifier.ps1` | `test/TelegramTorrent_Test.ps1` (vía wrapper) | Igual |
| Punto de entrada qBittorrent | Sí | No (CSV o manual) | No |
| Envío Telegram | Activado por defecto | Omitido en `TestMode` | Omitido |
| Librerías | `core/lib/*.ps1` | `test/lib/*.ps1` (espejo; validar aquí primero) | Igual |
| Caché Plex | `recursos/plex_cache.json` | `test/recursos/plex_cache_test.json` (aislada, se regenera) | `recursos/plex_cache.json` (producción) |
| Partial scan Plex | Activado | Activado | **Desactivado** (`-SkipPlexScan`) |
| Pasada 2 (validación caché) | No | **Sí** (solo FULL) | No |
| Informe HTML | No | Vía `run_test_pipeline.ps1` o `AnalyzeResults.ps1` | Opcional (pipeline) |
| Captura JSON | No | `test/results/json/` | Igual |
| Logs | `core/logs/TelegramNotifier_YYYYMMDD.log` | `test/logs/TelegramNotifier_Test.log` | Igual |

> **Nota:** En FULL, la caché de producción **no se modifica**. El test escribe solo en `test/recursos/plex_cache_test.json`.

---

## Series (julio 2026): poster temporada → serie

Para EPISODIO y TEMPORADA PACK:

- **Poster:** `parentThumb` (temporada) → `grandparentThumb` (serie). Nunca snapshot del capítulo.
- **Caché:** `grandparentRatingKey` (show), reutilizable entre temporadas/episodios.
- **Título Telegram:** parseado del torrent (sin `(año)` en TEMPORADA; sin título de capítulo Plex).
- **Scoring:** match vs `grandparentTitle`; show/temporada priorizados sobre episodio en PACK.

---

## Flujo de búsqueda de poster (v2.2 — julio 2026)

Ambos entornos comparten la misma lógica en `plex-functions.ps1`:

```
0. Parseo película: Get-MovieTitleAndYear (prioriza (YYYY) entre paréntesis)
1. Caché (recursos/plex_cache.json)
   ├─ Resolve-RatingKey → solo exacto / alias (sin fuzzy)
   └─ Get-PosterByCache → exacto, alias, fuzzy ≥85% (+ filtro año)
   └─ Hit → poster instantáneo

2. Partial scan Plex (solo si SkipPlexScan=$false, hay ContentPath **y existe en disco**)
   ├─ Resolve-PlexSectionForPath → detecta sección (G:\PELIS, G:\SERIES...)
   ├─ Invoke-PlexPartialScan → fuerza indexación del archivo
   └─ Wait-ForPlexItem → polling cada 3s, máx. ~12s (defaults test)

3. Lookup por ruta (items recientes en Plex)
   └─ Match por ContentPath aunque el título en Plex sea distinto

4. Búsqueda progresiva por título
   ├─ Título completo: "Kingsman, El Servicio Secreto"
   ├─ Pre-coma: "Kingsman"
   └─ Primera palabra significativa (omitida si el título contiene un año, ej. 2049)
   └─ Scoring por año + raíz de título (ES vs EN sin mapeos manuales)

5. Add-ToCache + Add-CacheAliases (alias automático)
   └─ Guarda título del torrent como alias si difiere del título Plex
```

**No se usa `title_overrides.json`**. Los títulos en español se resuelven con búsqueda progresiva, scoring por año y aliases automáticos en caché.

---

## Parámetros de Plex (compartidos)

| Parámetro | Default producción | Default test | Descripción |
|-----------|-------------------|--------------|-------------|
| `PlexScanPollSeconds` | `5` | `3` | Segundos entre reintentos tras partial scan |
| `PlexScanPollMaxAttempts` | `12` | `4` | Intentos máximos (~12 s total en test) |
| `SkipPlexScan` | `$false` | `$false` | Si `$true`, salta FASE 1 (scan + path lookup) |
| `PlexMoviePathPrefix` | `G:\PELIS` | `G:\PELIS` | Fallback para resolver sección películas |
| `PlexSeriesPathPrefix` | `G:\SERIES` | `G:\SERIES` | Fallback para resolver sección series |

---

---

## Tabla de modos de ejecución (test)

| Modo | Comando | Torrents | Caché | Scan Plex | Pasada 2 | HTML |
|------|---------|----------|-------|-----------|----------|------|
| **FULL** | `.\test_v4_wrapper.ps1` | Todos (`torrents.csv`) | `plex_cache_test.json` | Sí | Sí | No (manual o pipeline) |
| **FULL + análisis** | `.\run_test_pipeline.ps1` | Todos | `plex_cache_test.json` | Sí | Sí | **Sí** (auto) |
| **QuickTest** | `.\test_v4_wrapper.ps1 -QuickTest` | 10 | `plex_cache.json` (prod) | No | No | No |
| **QuickTest + HTML** | `.\run_test_pipeline.ps1 -QuickTest` | 10 | prod | No | No | Sí |
| **Parcial** | `.\test_v4_wrapper.ps1 -MaxTorrents 50` | N primeros | prod | Sí | No | No |
| **Un torrent** | `.\TelegramTorrent_Test.ps1 -TorrentName ... -TestMode` | 1 | prod (lectura) | Sí (default) | No | No |
| **Unitarios** | `.\validation\Run-UnitValidation.ps1` | Casos fijos | prod (lectura) | No | No | No |
| **Regresión series** | `.\validation\Run-SeriesRegression.ps1` | 3 casos Plex | prod | Sí (default) | No | No |

**Recomendado antes de promover cambios a `core/`:** unitarios → regresión series → **FULL + pipeline** → revisar HTML.

### Duración aproximada (observada / estimada)

| Modo | Torrents | Duración típica | Notas |
|------|----------|-----------------|-------|
| FULL (caché prod, histórico) | 247 | ~18 min | JSON `20260717_114438` |
| FULL (caché test vacía) | 247 | ~25–50 min | Variable; más lento sin hits iniciales |
| QuickTest | 10 | ~2 min | Sin scan Plex |
| AnalyzeResults (HTML) | — | ~20–30 s | Fase 2 del pipeline |

El pipeline muestra un **rango estimado al inicio** (`run_test_pipeline.ps1`) usando `last_pipeline_timing.json` o el último JSON del mismo modo. Tras cada ejecución actualiza el registro con tiempos reales.

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

### 4. Test — suite FULL (modo largo, paridad producción)

Procesa todos los torrents de `recursos/torrents.csv` con scan Plex activo, **caché test aislada** y **pasada 2** de validación:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test
.\test_v4_wrapper.ps1
```

#### Flujo FULL (un solo log de sesión)

```
1. Archivar log anterior → test/logs/TelegramNotifier_YYYYMMDD_HHMMSS.log
2. Vaciar test/recursos/plex_cache_test.json
3. PASADA 1: procesar torrents → Plex + escribir caché test
4. PASADA 2: recargar caché test → verificar lecturas vs pasada 1
5. Exportar JSON de resultados
```

**Salidas FULL:**

| Artefacto | Ruta |
|-----------|------|
| Log sesión | `test/logs/TelegramNotifier_Test.log` |
| JSON resultados | `test/results/json/TelegramNotifier_Test_YYYYMMDD_HHMMSS.json` |
| Caché generada | `test/recursos/plex_cache_test.json` |
| Validación pasada 2 | `test/results/json/CacheValidation_YYYYMMDD_HHMMSS.json` |

**Nota:** con las optimizaciones de test (polling corto, skip si ruta no existe, pasada 2 sin API Plex), un FULL suele tardar **8–15 min** con caché caliente o **12–20 min** con caché fría (antes ~18–50 min).

#### Optimizaciones de velocidad (julio 2026)

| Flag | Comando | Efecto |
|------|---------|--------|
| Caché caliente | `.\run_test_pipeline.ps1 -KeepTestCache` | No vacía `plex_cache_test.json`; reutiliza entradas previas |
| Sin pasada 2 | `.\run_test_pipeline.ps1 -SkipPass2` | Omite validación de lectura caché (~1–3 min menos) |
| Replay | `.\run_test_pipeline.ps1 -ReplayCacheOnly` | Solo pasada 2 sobre el último JSON FULL + caché test existente (~1–2 min) |
| Combinado dev | `.\run_test_pipeline.ps1 -KeepTestCache -SkipPass2` | Iteración rápida tras un FULL inicial |

**Automáticas (sin flags):**
- Si `ContentPath` no existe en disco → no partial scan ni polling (va directo a búsqueda API).
- Polling test: 3 s × 4 intentos (vs 5 s × 12 en producción).
- Pasada 2 lee solo caché (sin `Resolve-PlexSeriesPoster` vía HTTP).

Ejemplos:

```powershell
# Desarrollo diario tras un FULL inicial
.\run_test_pipeline.ps1 -KeepTestCache

# Validar solo lectura de caché
.\run_test_pipeline.ps1 -ReplayCacheOnly

# Replay sobre JSON concreto
.\test_v4_wrapper.ps1 -ReplayCacheOnly -ReplayJsonPath "results\json\TelegramNotifier_Test_YYYYMMDD_HHMMSS.json"
```

#### Pipeline FULL + informe HTML (recomendado)

Ejecuta el wrapper FULL y, al terminar, `AnalyzeResults.ps1` sobre el JSON más reciente. Al inicio muestra **duración estimada** (basada en la última ejecución o JSON histórico):

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test
.\run_test_pipeline.ps1
```

Al finalizar guarda tiempos reales en `test/results/last_pipeline_timing.json` para mejorar la estimación siguiente.

Análisis manual sobre un JSON concreto:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test\validation
.\AnalyzeResults.ps1 -JsonPath "..\results\json\TelegramNotifier_Test_YYYYMMDD_HHMMSS.json"
# Sin abrir navegador:
.\AnalyzeResults.ps1 -JsonPath "..." -NoOpen
```

El informe HTML incluye: métricas de cobertura, fallos explicados por categoría, jerarquía de posters (show vs temporada), regresión Blade Runner / The Boys / Percy, y listado completo con URLs de poster.

HTML generado en: `test/results/analisis/TelegramNotifier_Analisis_YYYYMMDD_HHMMSS.html`

### 5. Test — suite rápida (`QuickTest`, 10 torrents)

Equivalente al modo largo pero con `-SkipPlexScan`, solo 10 entradas del CSV y **caché de producción** (no genera `plex_cache_test.json` ni pasada 2):

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test
.\test_v4_wrapper.ps1 -QuickTest

# Con informe HTML al final
.\run_test_pipeline.ps1 -QuickTest
```

### 5b. Preparar CSV de torrents

```powershell
# Desde qBittorrent (Windows)
cd C:\Users\grau_\Downloads\TelegramNotifier\recursos\listado_qbittorrent
.\Exportar_listado_qBittorrent.ps1 -OnlyCompleted

cd ..\..\test
.\regenerate_csv.ps1 -OnlyWithContent   # genera recursos/torrents.csv (UTF-8 BOM)
```

### 6. Validación unitaria (suite completa)

Ejecuta parseo de películas, caché, scoring Kingsman y series (poster jerárquico):

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test\validation
.\Run-UnitValidation.ps1
```

### 6b. Regresión series con Plex real (Windows)

Requiere Plex en `127.0.0.1:32400` y rutas `G:\SERIES` / `G:\PELIS`. Escribe log detallado en `test\logs\TelegramNotifier_Test.log`:

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test\validation

# Con partial scan + polling (como producción, ~60s por caso)
.\Run-SeriesRegression.ps1

# Rápido: solo caché + búsqueda por título
.\Run-SeriesRegression.ps1 -SkipPlexScan
```

Casos: Percy Jackson S02 PACK, The Boys S05E01, Blade Runner 2049.

### 7. Validación por área (opcional)

**Parseo + caché** (Blade Runner 2049, fuzzy, etc.):

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test\validation
.\ValidateMovieTitleParse.ps1
```

**Series — poster jerárquico** (sin Plex, mocks):

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test\validation
.\ValidateSeriesPoster.ps1
```

**Variantes y scoring ES/EN** (casos Kingsman, sin Plex real):

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test\validation
.\ValidateKingsmanSearch.ps1
```

---

## Estructura del entorno test

```
test/
├── README_TEST.md                  ← Este archivo
├── TelegramTorrent_Test.ps1        ← Script principal de test (1 torrent)
├── test_v4_wrapper.ps1             ← Procesa recursos/torrents.csv (FULL / QuickTest)
├── run_test_pipeline.ps1           ← Wrapper + AnalyzeResults.ps1 (HTML)
├── regenerate_csv.ps1              ← torrents.csv desde qBittorrent JSON
├── PLEXPOSTER_IMPROVEMENTS.md      ← Historial de diseño (referencia)
│
├── lib/                            ← Espejo de core/lib/ (validar aquí, luego promover)
│   ├── utilities.ps1               ← Get-TorrentSearchMetadata, Get-MovieTitleAndYear
│   ├── cache-manager.ps1           ← UseTestCache, Resolve-RatingKey, Get-PosterByCache
│   ├── plex-functions.ps1          ← Scan, path lookup, jerarquía poster
│   ├── test-cache-helpers.ps1      ← Pasada 2, Archive-TestSessionLog
│   └── pipeline-timing.ps1         ← Estimación duración pipeline
│
├── recursos/
│   └── plex_cache_test.json        ← Caché aislada (solo FULL; se regenera cada ejecución)
│
├── validation/
│   ├── Run-UnitValidation.ps1      ← Suite unitaria (ejecuta todos)
│   ├── Run-SeriesRegression.ps1    ← Regresión Plex real (Percy, Boys, Blade Runner)
│   ├── ValidateKingsmanSearch.ps1
│   ├── ValidateMovieTitleParse.ps1
│   ├── ValidateSeriesPoster.ps1
│   ├── AnalyzeResults.ps1          ← Informe HTML ampliado
│   ├── ConsolidateResults.ps1
│   └── OrganizeResults.ps1
│
├── logs/
│   ├── TelegramNotifier_Test.log   ← Log sesión activa
│   └── TelegramNotifier_*.log      ← Logs archivados (inicio de cada FULL)
│
└── results/
    ├── json/
    │   ├── TelegramNotifier_Test_*.json
    │   └── CacheValidation_*.json  ← Resultado pasada 2 (solo FULL)
    ├── last_pipeline_timing.json   ← Tiempos reales del último pipeline
    └── analisis/
        └── TelegramNotifier_Analisis_*.html
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

### Test FULL (pasada 1 / pasada 2)

```
[INFO] === TEST FULL - inicio ===
[INFO] === PASADA 1: Plex + generación plex_cache_test.json ===
[INFO] Caché actualizado: Nuevo título '...' agregado con RatingKey ...
[INFO] === PASADA 1 fin: 224 posters / 247 torrents, 180 entradas en caché test ===
[INFO] === PASADA 2: verificacion caché test ===
[INFO] PASADA 2 OK #1: ... rk=7223 metodo=cache_exact
[INFO] === PASADA 2 fin: 220/224 lecturas OK (98.21%) ===
[INFO] === TEST FULL - fin ===
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

### Test con SkipPlexScan (QuickTest)

```
[INFO] SkipPlexScan activo, omitiendo partial scan
[INFO] Queries progresivas: ...
```

---

## Caché: producción vs test

### Producción y QuickTest

Ubicación: `recursos/plex_cache.json`

Usada en producción (`core/`) y en tests QuickTest/parciales/un torrent (solo lectura salvo que Plex encuentre entradas nuevas en esos modos).

### FULL test (aislada)

Ubicación: `test/recursos/plex_cache_test.json`

- Se **vacía al inicio** de cada FULL.
- **Pasada 1:** cada poster encontrado se escribe aquí (no toca `recursos/plex_cache.json`).
- **Pasada 2:** recarga el JSON y verifica que cada torrent con poster en pasada 1 se lee correctamente desde caché.
- Sirve para validar criterios de título normalizado, `ratingKey` de show y poster antes de promover lógica a producción.

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
| FULL modifica prod cache | Pasada 1 escribía en prod (antiguo) | Confirmar `plex_cache_test.json`; prod intacto |
| Pasada 2 muchos FAIL | Claves/alias/poster distintos pasada 1 vs 2 | Revisar `CacheValidation_*.json` y log PASADA 2 |
| `elseif` / `Test-Path` vacío al dot-source | Sesión PowerShell con variables `$TorrentName`/`$ContentPath` | Cerrar sesión o usar wrapper actualizado |
| Poster en prod, no en test | `-SkipPlexScan` activo | Ejecutar FULL sin `-QuickTest` |
| Test muy lento | Modo largo con scan activo | Normal; usar `-QuickTest` para iterar |
| `Escaneo parcial activado` no aparece | `SkipPlexScan` o `ContentPath` vacío | Verificar ruta y flag |
| Plex devuelve 0 items | Título ES vs EN | Debería resolverse con query `Kingsman` + año |
| Poster incorrecto (película distinta) | Parseo o fuzzy en caché | Ejecutar `ValidateMovieTitleParse.ps1`; revisar título/año en log |
| Timeout 60s | Plex tarda en indexar | Aumentar `-PlexScanPollMaxAttempts` |

---

---

## Promover cambios de test → producción

Flujo acordado:

1. Implementar y probar en `test/lib/` (no en `core/` directamente).
2. `.\validation\Run-UnitValidation.ps1` — parseo, caché, scoring, poster jerárquico (sin Plex o mínimo).
3. `.\validation\Run-SeriesRegression.ps1` — casos Percy / Boys / Blade Runner con Plex real.
4. `.\run_test_pipeline.ps1` — FULL + informe HTML; revisar cobertura, fallos explicados y jerarquía.
5. Copiar archivos validados de `test/lib/` a `core/lib/` y `test/TelegramTorrent_Test.ps1` → `core/TelegramNotifier.ps1` (parseo equivalente).
6. Prueba manual en prod con `-SendTelegram:$false` (ver ejemplos en `core/README.md`).

**No promover:** `test/lib/test-cache-helpers.ps1`, `test/recursos/plex_cache_test.json`, scripts de `test/validation/` (permanecen solo en test).

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

# ── TEST: FULL (caché test + pasada 2) ───────────────
.\test_v4_wrapper.ps1

# ── TEST: FULL + informe HTML (recomendado) ───────────
.\run_test_pipeline.ps1

# ── TEST: suite rápida (10 torrents, sin scan) ─────
.\test_v4_wrapper.ps1 -QuickTest

# ── TEST: QuickTest + HTML ───────────────────────────
.\run_test_pipeline.ps1 -QuickTest

# ── Análisis manual de un JSON ───────────────────────
.\validation\AnalyzeResults.ps1 -JsonPath "results\json\TelegramNotifier_Test_....json"

# ── VALIDACIÓN unitaria ──────────────────────────────
.\validation\Run-UnitValidation.ps1

# ── VALIDACIÓN regresión series (Plex real) ────────
.\validation\Run-SeriesRegression.ps1
```

---

**Última actualización:** 2026-07-17  
**Versión búsqueda poster:** 2.4 (optimizaciones velocidad test, KeepTestCache, Replay, pasada 2 sin API)
