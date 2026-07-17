# 🎬 TelegramNotifier - Sistema Automático de Notificaciones de Torrents

Un sistema PowerShell completo que monitorea torrents completados en qBittorrent, busca posters en tu servidor Plex, y envía notificaciones a Telegram con la portada del contenido.

## 🎯 RESUMEN EJECUTIVO

**¿Qué es?** Un agente automático que observa qBittorrent y notifica a Telegram cada vez que un torrent se completa.

**¿Cómo funciona?** Cuando qBittorrent termina una descarga:
1. Ejecuta `TelegramNotifier.ps1` automáticamente
2. Analiza el nombre del torrent (película, serie, temporada, capítulo)
3. Busca el poster en tu servidor Plex (caché local o API REST)
4. Envía a Telegram con imagen en 0-2 segundos
5. Registra todo en logs diarios

**Características clave:**
- ⚡ **Instantáneo**: 0ms cache local, 500ms-2s búsqueda en Plex API
- 🎨 **Con posters**: Obtiene imágenes de portadas automáticamente
- 🧠 **Inteligente**: Partial scan Plex, lookup por ruta, búsqueda progresiva y aliases automáticos en caché
- 📊 **Confiable**: 88.61% cobertura en 237 torrents de prueba
- 🔄 **Modular**: 4 librerías PowerShell independientes
- 📝 **Logueable**: Rotación diaria, niveles de severidad, timestamps

**Estadísticas:**
- ✅ 210/237 torrents encontrados (88.61%)
- 📦 115+ títulos en caché persistente (crece automáticamente)
- ⚙️ 30+ funciones en 3300+ líneas (libs + scripts principales)
- 🧪 Suite de tests con 237 casos

---

## 🔄 FLUJO DE EJECUCIÓN EN TIEMPO REAL

```
┌─────────────────────────────────────────────────────────────────┐
│ qBITTORRENT (Torrent Completado)                                │
│ ¿Descarga terminada? → SÍ                                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ↓
        ╔════════════════════════════════════╗
        ║  EJECUTA: TelegramNotifier.ps1     ║
        ║  Parámetros: %N (nombre)           ║
        ║             %F (ruta)              ║
        ╚════────────┬─────────────────────╝
                     │
        ┌────────────┴─────────────┐
        ↓                          ↓
   ╔═══════════════╗     ╔════════════════╗
   ║ PARSEAR TIPO  ║     ║ CARGAR LIBRERÍAS║
   ║ (S##E##?)     ║     ║ (4 .ps1 files) ║
   ╚═══════┬═══════╝     ╚════────┬───────╝
           │                      │
           └──────────┬───────────┘
                      ↓
        ╔═════════════════════════════╗
        ║ BUSCAR POSTER               ║
        ║ 1. Caché en memoria (0ms)   ║
        ║ 2. Partial scan + path (60s)║
        ║ 3. Búsqueda progresiva API  ║
        ║ 4. Auto-agregar a caché     ║
        ╚═════════────┬───────────════╝
                      │
        ┌─────────────┴──────────────┐
        ↓                            ↓
   ╔═════════════╗          ╔═══════════════════╗
   ║ POSTER      ║          ║ SIN POSTER        ║
   ║ ENCONTRADO  ║          ║ (Texto solamente) ║
   ╚─────┬───────╝          ╚────────┬──────────╝
         │                           │
         ↓                           ↓
   ╔═════════════════════╗  ╔════════════════════╗
   ║ TELEGRAM            ║  ║ TELEGRAM           ║
   ║ + Imagen (500ms)    ║  ║ + Texto (100ms)    ║
   ║ + Detalles          ║  ║ + Detalles         ║
   ╚─────┬───────────────╝  ╚────────┬───────────╝
         │                           │
         └───────────┬───────────────┘
                     ↓
            ╔════════════════════╗
            ║ REGISTRAR EN LOGS  ║
            ║ core/logs/*.log    ║
            ║ [SUCCESS] o [ERROR]║
            ╚════════════════════╝
```

---

## 📋 TABLA DE REFERENCIA

| Archivo | Responsabilidad | Entrada | Salida | Criticidad |
|---------|-----------------|---------|--------|-----------|
| `core/TelegramNotifier.ps1` | Orquestador principal, punto de entrada desde qBittorrent | Nombre torrent, ruta contenido | Notificación Telegram, log | ⭐⭐⭐ |
| `core/lib/logger.ps1` | Logging centralizado con rotación automática | Texto, nivel (INFO/ERROR/SUCCESS) | Archivo log, consola coloreada | ⭐⭐ |
| `core/lib/utilities.ps1` | Parsing de nombres, detección de tipo, normalización | Nombre torrent | Metadata detectada, confianza % | ⭐⭐⭐ |
| `core/lib/cache-manager.ps1` | Gestión de caché persistente (JSON) y en memoria | Título a buscar o nuevo título a agregar | URL poster o {found: false} | ⭐⭐⭐ |
| `core/lib/plex-functions.ps1` | Scan Plex, path lookup, búsqueda progresiva + scoring | Metadata torrent, ContentPath | URL poster o null | ⭐⭐⭐ |
| `recursos/plex_cache.json` | Caché persistente compartida (115+ títulos, aliases) | N/A | Cargado al iniciar | ⭐⭐⭐ |
| `core/logs/` | Logs diarios de producción | Operaciones del script | TelegramNotifier_YYYYMMDD.log | ⭐⭐ |
| `test/README_TEST.md` | Guía detallada test vs producción, comandos y modos | N/A | Documentación | ⭐⭐ |
| `test/TelegramTorrent_Test.ps1` | Suite de 237 torrents (paridad con producción) | CSV con torrents | Análisis de cobertura | ⭐⭐ |
| `backups/backup-production.ps1` | Script de respaldo con 3 modos (FULL/PROD/TEST) | Parámetro: PRODUCTION/FULL/TEST | ZIP comprimido con timestamp | ⭐ |
| `.gitignore` | Configuración para excluir archivos sensibles | N/A | Secretos, logs, cache excluidos | ⭐⭐ |

---

## 📁 ESTRUCTURA DEL PROYECTO

```
TelegramNotifier/
├── 📄 README.md                          ← Documentación principal (ÉL MISMO)
├── 📄 .gitignore                         ← Configuración de Git
│
├── 📂 core/                              ← ⭐ PRODUCCIÓN
│   ├── 📄 TelegramNotifier.ps1           ← Punto de entrada desde qBittorrent
│   ├── 📄 run.ps1                        ← Script de ejecución rápida
│   ├── 📄 README.md                      ← Documentación técnica detallada
│   │
│   ├── 📂 lib/                           ← Librerías (dot-sourced)
│   │   ├── 📄 logger.ps1
│   │   ├── 📄 utilities.ps1              ← Get-MovieTitleAndYear, Split-TitleVariants
│   │   ├── 📄 cache-manager.ps1          ← Aliases, fuzzy con filtro de año
│   │   └── 📄 plex-functions.ps1         ← Scan, path lookup, búsqueda progresiva
│   │
│   └── 📂 logs/
│       └── 📄 TelegramNotifier_*.log
│
├── 📂 test/                              ← 🧪 SUITE DE TESTS
│   ├── 📄 README_TEST.md                 ← Guía test vs producción ⭐
│   ├── 📄 TelegramTorrent_Test.ps1
│   ├── 📄 test_v4_wrapper.ps1            ← FULL / QuickTest (CSV masivo)
│   ├── 📄 run_test_pipeline.ps1          ← Wrapper + informe HTML
│   ├── 📄 regenerate_csv.ps1
│   ├── 📄 PLEXPOSTER_IMPROVEMENTS.md
│   │
│   ├── 📂 lib/                           ← Espejo de core/lib/ (validar aquí primero)
│   │   └── 📄 test-cache-helpers.ps1     ← Pasada 2 FULL (solo test)
│   ├── 📂 recursos/
│   │   └── 📄 plex_cache_test.json         ← Caché aislada (solo FULL)
│   ├── 📂 validation/
│   │   ├── 📄 Run-UnitValidation.ps1
│   │   ├── 📄 Run-SeriesRegression.ps1
│   │   ├── 📄 ValidateKingsmanSearch.ps1
│   │   ├── 📄 ValidateMovieTitleParse.ps1
│   │   ├── 📄 AnalyzeResults.ps1         ← Informe HTML ampliado
│   │   ├── 📄 ConsolidateResults.ps1
│   │   └── 📄 OrganizeResults.ps1
│   │
│   └── 📂 results/
│       ├── 📂 json/                      ← TelegramNotifier_Test_*, CacheValidation_*
│       └── 📂 analisis/                  ← Informes HTML
│
├── 📂 recursos/
│   ├── 📄 plex_cache.json                ← Caché producción (+ QuickTest lectura/escritura)
│   ├── 📄 README_CACHE.md
│   └── 📄 torrents.csv
│
├── 📂 backups/                           ← Respaldos
│   ├── 📄 backup-production.ps1
│   └── 📄 RESTORE.md
│
└── 📂 memories/                          ← Documentación archivada
    └── 📄 *.md
```

---

## 🔌 CONFIGURACIÓN qBITTORRENT

### Paso 1: Abrir Preferencias
```
qBittorrent → Herramientas → Preferencias → Eventos ejecutables
```

### Paso 2: Configurar Acción Personalizada
```
✅ Ejecutar programa en finalización de torrent

Program (Programa):
    C:\Windows\System32\powershell.exe

Arguments (Argumentos):
    -ExecutionPolicy Bypass -File "C:\Users\grau_\Downloads\TelegramNotifier\core\TelegramNotifier.ps1" "%N" "%F"
```

### Paso 3: Variables
- `%N` → Nombre del torrent (ej: "The Mandalorian S02E08 2160p")
- `%F` → Ruta completa del contenido descargado
- `%L` → Categoría (opcional)

### Paso 4: Verificar en Logs
```powershell
# Ver últimas líneas del log
tail -f core/logs/TelegramNotifier_$(Get-Date -Format 'yyyyMMdd').log
```

---

## 📚 ANÁLISIS EXHAUSTIVO (100%)

### NIVEL 1: Arquitectura General

El proyecto funciona en **capas** independientes:

```
┌────────────────────────────────────────┐
│  CAPA 1: ENTRADA                       │
│  qBittorrent → TelegramNotifier.ps1   │
└──────────────┬─────────────────────────┘
               │
┌──────────────┴──────────────────────────┐
│  CAPA 2: PARSING & NORMALIZACIÓN       │
│  utilities.ps1                         │
│  • Detecta: EPISODIO/PELICULA/TEMPORADA│
│  • Películas: Get-MovieTitleAndYear    │
│  • Extrae: Resolución, codec, audio    │
└──────────────┬─────────────────────────┘
               │
┌──────────────┴──────────────────────────┐
│  CAPA 3: CACHÉ (DOS NIVELES)           │
│  cache-manager.ps1                     │
│  • Memoria: Array $script:PlexCache    │
│  • Disco: recursos/plex_cache.json       │
└──────────────┬─────────────────────────┘
               │
┌──────────────┴──────────────────────────┐
│  CAPA 4: BÚSQUEDA (PLEX API)           │
│  plex-functions.ps1                    │
│  • Scoring inteligente                 │
│  • Fuzzy matching (API, no caché RK)   │
└──────────────┬─────────────────────────┘
               │
┌──────────────┴──────────────────────────┐
│  CAPA 5: NOTIFICACIÓN & LOGGING        │
│  logger.ps1 + Telegram Bot API         │
│  • Envía foto + detalles               │
│  • Registra en TelegramNotifier_*.log  │
└────────────────────────────────────────┘
```

### NIVEL 2: Flujo de Ejecución Detallado

#### Fase 1: INICIALIZACIÓN (50-100ms)
```powershell
# TelegramNotifier.ps1 líneas 1-60
[1] Cargar configuración ($Plex_URL, $ChatID_Telegram, etc.)
[2] Definir función Initialize-Logger
[3] Dot-sourcing: Cargar 4 librerías desde core/lib/
    └─ logger.ps1 (55 líneas)
    └─ utilities.ps1 (201 líneas)
    └─ cache-manager.ps1 (~454 líneas)
    └─ plex-functions.ps1 (~556 líneas)
[4] Llamar Initialize-Logger → Crear core/logs/TelegramNotifier_YYYYMMDD.log
```

#### Fase 2: PARSING DEL TORRENT (20-50ms)
```powershell
# utilities.ps1 + TelegramNotifier.ps1
[1] Normalize-Name($TorrentName)
    └─ "Blade Runner 2049 (2017)..." → "blade-runner-2049-(2017)..."
[2] Get-CleanName($OriginalName)
    └─ Quita resolución y etiquetas técnicas
[3] Detección de tipo:
    ├─ EPISODIO: S##E## en CleanName
    ├─ TEMPORADA: S## sin episodio
    └─ PELICULA: Get-MovieTitleAndYear($OriginalName)
        ├─ Prioriza año entre paréntesis: (2017) → año de estreno
        ├─ Título = texto antes de `[`, sin (año)
        └─ Ej: "Blade Runner 2049 (2017)..." → Title "Blade Runner 2049", Year 2017
        └─ Fallback: regex sobre CleanName si no hay (año)
[4] Extract metadata: Resolución, codec, audio, etc.
```

#### Fase 3: BÚSQUEDA DE POSTER (0-60000ms)
```powershell
# cache-manager.ps1 + plex-functions.ps1
[1] Initialize-PlexCache()
    └─ Carga recursos/plex_cache.json (compartida producción + test)

[2] Get-PosterByCache($Title, $DetectedMetadata) + Resolve-RatingKey
    ├─ Resolve-RatingKey: solo exacto / alias (sin fuzzy)
    ├─ Get-PosterByCache: exacto, alias, fuzzy ≥85% con filtro de año
    └─ Return poster URL o miss

[3] Si miss y SkipPlexScan=$false:
    ├─ Resolve-PlexSectionForPath(ContentPath)
    ├─ Invoke-PlexPartialScan → GET /library/sections/{id}/refresh?path=...
    └─ Wait-ForPlexItem → polling Find-PlexItemByPath (5s × 12)

[4] Si sigue sin poster → Search-PlexWithQueries
    ├─ Variantes: título completo | pre-coma | primera palabra*
    ├─ *No genera primera palabra si el título contiene un año (ej. 2049)
    ├─ GET /search?query=...&type=1|2|8
    └─ Test-PlexItemAcceptable (score + año + raíz título)

[5] Save-PlexPosterResult → Add-ToCache + alias automático del título torrent
```

#### Fase 4: TELEGRAM (100-500ms)
```powershell
# TelegramNotifier.ps1 función Send-TelegramNotification
[1] Si $PosterUrl encontrada:
    └─ Usar /sendPhoto (multipart, incluye imagen)
    
[2] Si SIN poster:
    └─ Usar /sendMessage (solo texto)

[3] Enviar a Telegram Bot API (token + chat ID)
    └─ curl.exe POST a https://api.telegram.org/bot{TOKEN}/sendPhoto

[4] Capturar respuesta → Log
```

#### Fase 5: LOGGING (10-20ms)
```powershell
# logger.ps1
[1] Write-Log escribe línea timestamped a archivo
[2] Verificar tamaño (Rotate-Log si ≥5MB)
[3] Emitir a consola con color según nivel
```

**Timing Total:** 200-2500ms (caché) vs 1-3s (API fallback)

### NIVEL 3: Sistema de Testing

**Suite de 237 torrents:**
- Fuente: `test/TelegramTorrent_Test.ps1`
- Cobertura: 88.61% (210 encontrados, 27 no encontrados)
- Tipos: EPISODIO (140), PELICULA (60), TEMPORADA (30), DESCONOCIDO (7)

**Análisis de Resultados:**
```powershell
# test/validation/AnalyzeResults.ps1
└─ Genera HTML interactivo con:
   ├─ Gráficos por tipo (éxito/fallo)
   ├─ Top 20 torrents no encontrados
   ├─ Análisis de confianza
   └─ Sugerencias de mejora
```

### NIVEL 4: Sistema de Caché

**Algoritmo de Caché:**

1. **Carga Inicial:**
   ```json
   {
     "version": "1.0",
     "lastUpdated": "2026-07-01T14:15:25Z",
     "totalItems": 112,
     "cache": [
       {
         "titulo_normalizado": "themandalorian",
         "titulo_original": "The Mandalorian",
         "ratingKey": "8030",
         "tipo": "SERIE",
         "poster_url": "http://127.0.0.1:32400/library/metadata/8030/thumb/...",
         "year": null
       }
     ]
   }
   ```

2. **Búsqueda en caché (Get-PosterByCache):**
   - **Exacto / alias:** match por `titulo_normalizado` o `aliases`
   - **Fuzzy ≥85%:** solo en poster cache; filtra por año en películas (`Test-CacheItemYearMatch`)
   - **Resolve-RatingKey:** solo exacto/alias — no usa fuzzy (evita falsos positivos)
   - **Contains bonus:** solo si `minLen/maxLen ≥ 0.75` (evita `blade` ⊂ `bladerunner2049`)

3. **Ejemplo corregido — Blade Runner 2049:**
   ```
   Torrent: "Blade Runner 2049 (2017) [2160p...].mkv"
   Parseo:  Title "Blade Runner 2049", Year 2017 (no confunde 2049 con año)
   Caché:   miss (no matchea Blade/4424 por fuzzy ni por año)
   Plex:    path_lookup → ratingKey 8190 → se añade a caché
   ```

4. **Auto-Agregación:**
   - Si nuevo título encontrado en API
   - → Agregar a `$script:PlexCache` (memoria)
   - → Actualizar `recursos/plex_cache.json` (disco)

4. **Regeneración del Caché:**

   **¿Cómo funciona?**
   - El caché se regenera automáticamente mientras usas el sistema
   - Cada vez que procesas un torrent, se ejecuta `TelegramNotifier.ps1`
   - Si el poster NO está en el caché → se busca en Plex API
   - Si se encuentra → se agrega automáticamente a `recursos/plex_cache.json`
   
   **¿Cuándo se regenera?**
   - ✅ **Automáticamente**: Cada torrent completado en qBittorrent
   - ✅ **Primer uso**: Descarga inicial vacía, se rellena con cada búsqueda
   - ❌ **Nunca manual**: No requiere acciones del usuario
   
   **Proceso paso a paso:**
   ```powershell
   1. Torrent completado en qBittorrent
       ↓
   2. Ejecuta: PowerShell.exe -File TelegramNotifier.ps1 "nombre_torrent" "ruta"
       ↓
   3. Initialize-PlexCache() carga recursos/plex_cache.json
       ↓
   4. Get-PosterByCache() busca en caché
       ├─ ✅ Encontrado → Usa URL (0ms)
       └─ ❌ No encontrado → Llama Plex API
       ↓
   5. Get-PlexPoster() → partial scan, path lookup, búsqueda progresiva
       ↓
   6. Si encontrado → Add-ToCache() + Add-CacheAliases (alias automático)
       └─ Persistencia vía Get-CacheFileData / Save-CacheToFile
       └─ Guarda en recursos/plex_cache.json (JSON persistente)
       ↓
   7. Próxima búsqueda del mismo título → ✅ Hit de caché
   ```

   **Ejemplo de Regeneración:**
   ```
   Torrent 1: "La Casa del Dragon S01E01" 
   ├─ Caché vacío → Busca en API → Encuentra "ratingKey: 8103"
   └─ Agrega: {"titulo_normalizado": "lacasadeldragon", "ratingKey": "8103", ...}
   
   Torrent 2: "La Casa del Dragon S01E02"
   └─ Encuentra en caché con RatingKey 8103 → ✅ 0ms (sin llamada API)
   ```

   **Contenido generado automáticamente:**
   ```json
   {
     "version": "1.0",
     "lastUpdated": "2026-07-01T16:30:45Z",
     "totalItems": 2,
     "description": "Caché persistente de Plex",
     "cache": [
       {
         "titulo_normalizado": "lacasadeldragon",
         "titulo_original": "La casa del dragón",
         "ratingKey": "8103",
         "tipo": "SERIE",
         "poster_url": "http://127.0.0.1:32400/library/metadata/8103/thumb/...",
         "year": "2022"
       }
     ]
   }
   ```

   **Forzar Regeneración Manual (Opcional):**
   ```powershell
   # Si necesitas vaciar y regenerar desde cero:
   Remove-Item "C:\ruta\recursos\plex_cache.json"
   
   # Luego procesa cualquier torrent:
   & "C:\ruta\core\TelegramNotifier.ps1" "Nombre Torrent" "C:\ruta\contenido"
   # El sistema creará un plex_cache.json nuevo automáticamente
   ```

   **Ventajas del Sistema:**
   - 🚀 **Rápido**: Hits de caché en 0ms, sin latencia de API
   - 📊 **Persistente**: Survives to restarts (JSON en disco)
   - 🔄 **Automático**: Crece solo mientras usas el sistema
   - 🎯 **Inteligente**: RatingKey prioritized (identificador único de Plex)
   - 🛡️ **Robusto**: Transliteración de acentos y ñ (`Remove-Accents` → `28anosdespues`)

### NIVEL 5: Sistema de Logging

**Rotación Diaria + Tamaño:**
```
core/logs/
├── TelegramNotifier_20260701.log    ← Hoy (activo)
├── TelegramNotifier_20260630.log    ← Ayer
└── TelegramNotifier_20260701_001.log ← Rotado (≥5MB)
```

**Formato de Log:**
```
[2026-07-01 14:15:25] [INFO] Procesando torrent: The Mandalorian S02E08...
[2026-07-01 14:15:25] [INFO] Tipo: EPISODIO (S02E08)
[2026-07-01 14:15:25] [SUCCESS] Poster encontrado: http://127.0.0.1:32400/...
[2026-07-01 14:15:26] [SUCCESS] Notificación Telegram enviada (con poster)
```

**Niveles:**
- ℹ️ **INFO** (Blanco): Información general
- ⚠️ **WARNING** (Amarillo): Advertencias no-críticas
- ❌ **ERROR** (Rojo): Errores que requieren atención
- ✅ **SUCCESS** (Verde): Operaciones exitosas

### NIVEL 6: Integración Plex API

**Endpoint Principal:**
```
GET http://127.0.0.1:32400/library/search?query={Title}&type={Type}
Headers: X-Plex-Token: {TOKEN}
```

**Tipos de Búsqueda:**
- `type=1` → Películas
- `type=2` → Series
- `type=8` → Episodios

**Respuesta XML:**
```xml
<?xml version="1.0"?>
<MediaContainer>
  <Video key="/library/metadata/8030"
         type="show"
         title="The Mandalorian"
         ratingKey="8030"
         thumb="/library/metadata/8030/thumb/1782873896?X-Plex-Token=...">
    <Media videoResolution="4K" />
  </Video>
</MediaContainer>
```

**Scoring (0-200 puntos):**
- Match archivo: +0-100 (exacto=100, padre=70)
- Match título: +0-50 (exacto=50, contiene=30)
- Match año: +0-40 (movies)
- Match season/ep: +0-60 (shows)
- **Total**: Ganador es el que suma más

---

## ✨ CARACTERÍSTICAS PRINCIPALES

✅ **Búsqueda Instantánea**
- 0ms: Caché local en memoria
- 500ms-2s: Fallback a Plex API
- Auto-actualización de caché con nuevos títulos

✅ **Fuzzy Matching Inteligente**
- Normalización de caracteres especiales (`Normalize-CacheKey`, `Remove-Accents`)
- Fuzzy en caché (poster) con umbral 85% y filtro de año en películas
- Fuzzy en API Plex para scoring de resultados
- Sin fuzzy en `Resolve-RatingKey` (solo exacto/alias)
- Variantes de búsqueda sin acortar títulos con año en el nombre

✅ **Notificaciones en Telegram**
- Foto con poster + detalles
- Fallback a texto si no hay poster
- Timestamps y niveles de log

✅ **Cobertura Comprobada**
- 88.61% en 237 torrents de test
- 115+ títulos en caché persistente
- Análisis HTML de resultados

✅ **Logging Automático**
- Rotación diaria de logs
- Rotación por tamaño (≥5MB)
- Colores por nivel en consola

✅ **Modular y Extensible**
- 4 librerías PowerShell independientes
- Arquitectura de capas separadas
- Fácil de debuguear

---

## 🎯 GUÍA RÁPIDA

### Para Producción

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\core

# Torrent de prueba manual (sin Telegram)
.\TelegramNotifier.ps1 `
  -TorrentName "Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -ContentPath "G:\PELIS\Kingsman, El Servicio Secreto (2014) [2160p HEVC].mkv" `
  -SendTelegram:$false

# Ver logs
Get-Content "logs\TelegramNotifier_$(Get-Date -Format 'yyyyMMdd').log" -Tail 30
```

Ver documentación completa: [`core/README.md`](core/README.md)

### Para Testing

Documentación detallada: [`test/README_TEST.md`](test/README_TEST.md)

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\test

# Un torrent (paridad con producción — incluye partial scan)
.\TelegramTorrent_Test.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." -TestMode

# Un torrent (modo rápido — sin scan Plex)
.\TelegramTorrent_Test.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." -TestMode -SkipPlexScan

# FULL: todos los torrents + caché test aislada + pasada 2
.\test_v4_wrapper.ps1

# FULL + informe HTML (recomendado antes de promover a core/)
.\run_test_pipeline.ps1

# Suite rápida (10 torrents, caché producción, sin scan)
.\test_v4_wrapper.ps1 -QuickTest
.\run_test_pipeline.ps1 -QuickTest

# Validación unitaria y regresión series
.\validation\Run-UnitValidation.ps1
.\validation\Run-SeriesRegression.ps1

# Análisis HTML manual
.\validation\AnalyzeResults.ps1 -JsonPath "results\json\TelegramNotifier_Test_....json"
```

---

## 📊 ESTADÍSTICAS DEL PROYECTO

| Métrica | Valor |
|---------|-------|
| Archivos PowerShell (.ps1) | 23 |
| Líneas de código (libs + scripts principales) | 3300+ |
| Funciones definidas | 30+ |
| Librerías principales | 4 |
| Torrents en test suite | 237 |
| Cobertura de test | 88.61% |
| Títulos en caché | 115+ |
| Tiempo caché local | 0ms |
| Tiempo API fallback | 500ms-2s |
| Uptime (producción) | 24/7 |

---

## 🔧 CONFIGURACIÓN INICIAL

### 1. Verificar Plex
```powershell
# Testear conectividad a Plex
curl http://127.0.0.1:32400/library/sections?X-Plex-Token=Yt-aqViZD-ydpysRvGyP

# Debe devolver XML con librerías
```

### 2. Verificar Telegram
```powershell
# Testear bot
curl https://api.telegram.org/bot8755898341:AAFSxCy9zjYS_rLl-kFpVPCmJ3V2XLjKjYg/getMe

# Debe devolver: {"ok":true,"result":{"id":...}}
```

### 3. Probar búsqueda Plex manualmente
```powershell
# Ver secciones Plex
Invoke-RestMethod "http://127.0.0.1:32400/library/sections?X-Plex-Token=TU_TOKEN"

# Probar torrent en producción
cd core
.\TelegramNotifier.ps1 -TorrentName "..." -ContentPath "G:\PELIS\..." -SendTelegram:$false
```

---

## 🐛 TROUBLESHOOTING

| Problema | Solución |
|----------|----------|
| "Repository not found" en Git | Crear repo en https://github.com/new |
| Caracteres rotos en logs (Ã±, Ã¡) | Verificar UTF-8 BOM: `[System.IO.File]::ReadAllBytes()` |
| Notificación no llega a Telegram | Verificar token bot y chat ID en TelegramNotifier.ps1 |
| Poster no encontrado (texto-only) | Revisar log: `Escaneo parcial activado`, `Queries progresivas`. Ver [`test/README_TEST.md`](test/README_TEST.md) |
| Log file muy grande | Automático: rotación a los 5MB con timestamp |
| Poster incorrecto (película distinta) | Revisar log: año/título parseado. Validar con `ValidateMovieTitleParse.ps1` |
| Caché desincronizado | Caché en `recursos/plex_cache.json`; se auto-actualiza con aliases |

---

## 📞 SOPORTE RÁPIDO

```powershell
# Ver último error
Get-Content core/logs/TelegramNotifier_$(Get-Date -Format 'yyyyMMdd').log -Tail 20

# Testear TelegramNotifier manualmente
cd core
.\TelegramNotifier.ps1 "Test Torrent S01E01 2160p" "C:\Test\Content" $true

# Limpiar logs antiguos (>30 días)
Get-ChildItem core/logs/TelegramNotifier_*.log |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
  Remove-Item

# Ver config Plex
Get-Content recursos/plex_cache.json | ConvertFrom-Json | Select -ExpandProperty cache | Select -First 5
```

---

## 🎓 ESTRUCTURA DE APRENDIZAJE

```
1. COMENZAR
   └─ Leer README.md (ÉL MISMO)
   └─ Entender flujo: qBittorrent → Telegram

2. CONFIGURAR
   └─ Seguir "CONFIGURACIÓN qBITTORRENT"
   └─ Verificar tokens en TelegramNotifier.ps1

3. PROBAR
   └─ Ejecutar test/TelegramTorrent_Test.ps1
   └─ Analizar resultados

4. ENTENDER
   └─ Leer core/README.md (documentación técnica)
   └─ Explorar core/lib/*.ps1 (librerías)

5. DESARROLLAR
   └─ Modificar utilities.ps1 para nuevos tipos
   └─ Agregar funciones a plex-functions.ps1

6. DEPLOY
   └─ Ejecutar backups/backup-production.ps1
   └─ Configurar en servidor de producción
```

---

**Versión:** v1.3 (2026-07-15)
**Última actualización:** 2026-07-15
**Autor:** Sistema TelegramNotifier
**Repositorio:** https://github.com/grau1182/TelegramNotifier
