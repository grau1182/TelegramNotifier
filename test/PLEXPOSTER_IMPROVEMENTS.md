# Mejoras Get-PlexPoster v3.0-IMPROVED

## Estado de implementación (2026-07-06)

Las siguientes mejoras están **integradas en `core/lib/` y `test/lib/`** (no requieren script separado):

| Mejora | Estado | Funciones |
|--------|--------|-----------|
| Partial scan Plex | ✅ Implementado | `Invoke-PlexPartialScan`, `Wait-ForPlexItem` |
| Lookup por ruta | ✅ Implementado | `Find-PlexItemByPath`, `Resolve-PlexSectionForPath` |
| Búsqueda progresiva | ✅ Implementado | `Get-PlexSearchQueries`, `Search-PlexWithQueries`, `Split-TitleVariants` |
| Scoring mejorado | ✅ Implementado | `Test-PlexItemAcceptable`, raíz título pre-coma |
| Aliases automáticos | ✅ Implementado | `Add-CacheAlias`, `Save-PlexPosterResult` |
| title_overrides.json | ❌ No usado | Sustituido por búsqueda progresiva + aliases |

Documentación operativa: [`README_TEST.md`](README_TEST.md)

---

## 📋 Resumen

Implementación de mejoras para Get-PlexPoster, basadas en análisis de 237 torrents y falsos negativos (ej. Kingsman ES/EN, descargas recientes sin indexar).

**Objetivo**: Aumentar cobertura sin mapeos manuales de títulos

**Status histórico**: Diseño original en TelegramTorrent_Test_Improved.ps1 → **ahora en core/lib/plex-functions.ps1**

---

## � FASE 0: Library Lookup Directo (NEW - Ultra-Rápido)

**Problema resuelto**: 
- Muchas búsquedas son innecesarias si el contenido YA ESTÁ en tu Plex
- Búsqueda por nombre es lenta (500-1000ms) comparado con búsqueda por ID (1-5ms)

**Solución: Direct Catalog Lookup**
```
AL INICIO:
  1. Cargar todas películas/series de Plex
  2. Indexar localmente: {título_normalizado → ratingKey}
  3. Almacenar en memoria

EN CADA BÚSQUEDA:
  • Buscar localmente en índice (1-5ms) ← ULTRA RÁPIDO
  • Si coincidencia fuzzy ≥85% → ratingKey encontrado
  • Obtener poster directo por ID
  • GARANTIZADO SI EXISTE EN PLEX
```

**Funciones nuevas:**
- `Load-PlexLibraryCatalog()` - Carga catálogo al inicio (una sola vez)
- `Get-PosterByLibraryLookup()` - Búsqueda local rápida

**Ventajas:**
| Métrica | API Search | Library Lookup |
|---------|-----------|-----------------|
| Velocidad | 500-1000ms | 1-5ms (-99%) |
| Cobertura | ~70% | 100% si existe |
| Garantía Poster | No | Sí |

**Ejemplo:**
```
"The Boys" (busca por nombre)
  → Library Lookup: busca en catálogo local
  → Encuentra: título exacto → "The Boys" (ratingKey: 7223)
  → Poster: http://plex.local/metadata/7223/thumb/ ✓ INSTANTÁNEO
```

**Impacto esperado**: 
- Cobertura: +2-5% (casos que fallaban por nombre) 
- Velocidad: -99% tiempo en búsquedas exitosas

---

## �🎯 Fases Implementadas

### FASE 1: Fixes Rápidos + Limpieza de Ruido

**Funciones nuevas:**
- `Fix-PlexQueryEncoding()` - Reparar UTF-8 corrupto
  - Ã© → é, ã³ → ó, ã± → ñ, etc.
  - Se aplica automáticamente antes de búsquedas

- `Get-SearchKeywords()` - Limpiar ruido técnico
  - Elimina años entre paréntesis
  - Elimina SxxExxx (episodios)
  - Elimina resoluciones [2160p WEB-DL...]
  - Elimina paréntesis innecesarios

**Ejemplo:**
```
Input:  "The Boys S05E01 [AMZN WEB-DL 2160p HEVC DV HDR10+ ES DD+ 5.1]"
Output: "The Boys"
```

**Impacto esperado**: +10-15% cobertura

---

### FASE 2: Búsqueda Progresiva Multinivel

**Función nueva:**
- `Search-PlexProgressive()` - Búsqueda en 4 niveles

**Estrategia:**
1. **NIVEL 1 (Exacta)**: Score > 80
   - Búsqueda: "Título Completo"
   - Si falla → NIVEL 2

2. **NIVEL 2 (Sin Año)**: Score > 70
   - Búsqueda: "Título" (sin año)
   - Si falla → NIVEL 3

3. **NIVEL 3 (Keywords)**: Score > 60 + Fuzzy
   - Búsqueda: "Palabras clave principales"
   - Con fuzzy matching como fallback

4. **NIVEL 4 (Primera palabra)**: Score > 50
   - Búsqueda: "Primera Palabra"

**Ejemplo:**
```
"Minority Report (2002)" [WEB-DL 2160p]
  ↓ NIVEL 1 (falla)
  ↓ NIVEL 2: "Minority Report" → ÉXITO (Score 160)
```

**Impacto esperado**: +10-15% cobertura

---

### FASE 3: Detección de Idioma Bilingüe

**Funciones nuevas:**
- `Detect-TitleLanguage()` - Detectar SPANISH vs ENGLISH
  - Busca palabras españolas comunes
  - Detecta caracteres diacríticos
  - Retorna: "SPANISH" o "ENGLISH"

**Estrategia:**
```
SI idioma = SPANISH
  ├─ Buscar en español primero
  └─ SI falla → Buscar en inglés

SI idioma = ENGLISH  
  ├─ Buscar en inglés primero
  └─ SI falla → Buscar en español
```

**Ejemplos:**
```
"Para Toda La Humanidad" (detecta SPANISH)
  → Busca en Plex: "Para toda la humanidad" ✓

"Berlin" (detecta ENGLISH pero Plex devuelve "Berlín")
  → Fuzzy match detiene similitud y acepta ✓
```

**Impacto esperado**: +5-10% cobertura

---

### FASE 4: Caché Local Inteligente + Fuzzy Matching

**Funciones nuevas:**

- `Get-CachedPoster()` - Consulta caché antes de buscar
  - Busca por título normalizado
  - Incrementa métrica: `cache_hits`
  - Retorna poster directo si existe

- `Update-PlexCache()` - Guardar resultado en caché
  - Agrega entrada a `plex_cache.json`
  - Evita duplicados
  - Persiste en archivo

- `Get-FuzzyMatchScore()` - Levenshtein distance
  - Calcula similitud de texto (0-100%)
  - Usa en matching cuando exacta = 0
  - Threshold: 85% similaridad acepta resultado

**Caché JSON:**
```json
{
  "titulo": "The Boys",
  "poster_url": "http://127.0.0.1:32400/library/metadata/7223/thumb/...",
  "tipo": "serie",
  "plex_id": "7223",
  "timestamp": "2026-07-01 10:40:00"
}
```

**Ejemplo Fuzzy:**
```
Búsqueda: "The Clon Wars"
Resultado Plex: "The Clone Wars" (exacta = 0)
Fuzzy score: 95% → ACEPTA ✓
```

**Impacto esperado**: 
- Cobertura: +5-10%
- Velocidad: -80% tiempo (caché hits)

---

## 📊 Estadísticas de Mejora

### Flujo Integrado (Get-PlexPoster Completo)
```
PASO 1: Revisar CACHÉ local (plex_cache.json)
        ↓ SI ENCONTRADO → Retorna poster directo ✓
        
PASO 2: LIBRARY LOOKUP (búsqueda local en catálogo)
        ↓ SI ENCONTRADO (fuzzy ≥85%) → Retorna poster directo ✓
        
PASO 3: Revisar TITLE MAPPINGS (títulos alternativos conocidos)
        
PASO 4: Reparar ENCODING (UTF-8 corrupto)
        
PASO 5: Limpiar KEYWORDS (ruido técnico)
        
PASO 6: Detectar IDIOMA (SPANISH/ENGLISH)
        
PASO 7: BÚSQUEDA PROGRESIVA (4 niveles en Plex API)
        • NIVEL 1: Exacta (score > 80)
        • NIVEL 2: Sin año (score > 70)
        • NIVEL 3: Keywords+Fuzzy (score > 60)
        • NIVEL 4: Primera palabra (score > 50)
        ↓ SI ENCONTRADO → Retorna poster ✓
        
PASO 8: LEGACY FALLBACK (ratingKey directo para series especiales)
        ↓ SI ENCONTRADO → Retorna poster ✓
        
Si TODO falla → Retorna NULL
```

### Baseline (v2.0)
```
Cobertura: 49% (116/237 con poster)
Falsos negativos: 51% (121 sin poster)
Tiempo: ~3 minutos
```

### Proyectado (v3.0-IMPROVED con FASE 0)
```
Fase 0 (Library Lookup): +2-5%  (-99% tiempo búsquedas)
Fase 1: +10-15% (encoding + keywords)
Fase 2: +10-15% (búsqueda progresiva)
Fase 3: +5-10%  (bilingüe)
Fase 4: +5-10%  (fuzzy + caché)

CUMULATIVE TOTAL: 81-99% ✅
Velocidad: -90% tiempo (mayoría caché + library hits)
```

---

## 📁 Archivos Creados

```
test/
├── TelegramTorrent_Test_Improved.ps1      ← Script principal mejorado
├── plex_cache.json                        ← Caché persistente
├── titles_mapping.json                    ← Mapeos de títulos alternativos
├── legacy_series_fallback.json            ← Fallback para series antiguas
├── generate_test_data_improved.ps1        ← Pipeline mejorado
├── ValidatePlexImprovements.ps1           ← Script de validación
├── UnitTests_PlexFunctions.ps1            ← Tests unitarios (pendiente)
└── PLEXPOSTER_IMPROVEMENTS.md             ← Este archivo
```

---

## 🚀 Cómo Ejecutar

### Opción 1: Versión Mejorada (Recomendado)
```powershell
PS> cd test
PS> .\generate_test_data_improved.ps1
```

### Opción 2: Validar contra baseline
```powershell
PS> cd test
PS> .\ValidatePlexImprovements.ps1
```

### Opción 3: Test individual
```powershell
PS> cd test
PS> .\TelegramTorrent_Test_Improved.ps1 -TorrentName "The Boys S05E01" -ContentPath "C:\path\to\content" -TestMode $true
```

---

## 📈 Métricas en JSON

Cada torrent en el JSON consolidado incluye:

```json
"search_metrics": {
  "cache_hits": 5,
  "cache_misses": 232,
  "fuzzy_matches": 15,
  "progressive_level": "NO_YEAR"
}
```

Y en metadata:
```json
"cache_stats": {
  "total_cache_size": 50,
  "cache_hits": 125,
  "cache_misses": 112,
  "fuzzy_matches": 18
}
```

---

## 🔍 Casos de Éxito Esperados

### Caso 0: Library Lookup (NUEVO - FASE 0)
```
"The Boys" [Descargado, está en Plex]
  → PASO 2: Library Lookup busca localmente
  → Encuentra: ratingKey=7223 en catálogo
  → Poster: /metadata/7223/thumb/ → INSTANTÁNEO (1-5ms) ✓
```

### Caso 1: Encoding Corrupto
```
Antes: "Devuã©lvemela (2024)" → NO ENCONTRADO
Después: Fix encoding → "Devuélvemela" → ENCONTRADO ✓
```

### Caso 2: Años Confunden
```
Antes: "The Expanse (2015)" → FALLA en Plex
Después: Intenta SIN año → "The Expanse" → ENCONTRADO ✓
```

### Caso 3: Similitud Parcial
```
Antes: "The Clon Wars" → 0 puntos (typo)
Después: Fuzzy 95% → ACEPTA "The Clone Wars" ✓
```

### Caso 4: Caché Hit
```
Antes: "The Boys" busca 3 veces en Plex (3 búsquedas)
Después: Primera busca Plex, luego 2 hits de caché (1 búsqueda)
```

### Caso 5: Library Lookup + Fuzzy
```
"the-boys-season-1" [nombre descarga mal formateado]
  → Library Lookup busca localmente: "theboyseason1"
  → Catalogo: "the boys" (fuzzy 92% > 85%)
  → Poster: ENCONTRADO ✓ (1ms)
```

---

## 🔧 Configuración

### titles_mapping.json
```json
{
  "detected": "the-clon-wars",
  "plex_search": "Star Wars: The Clone Wars",
  "type_hint": "SERIE",
  "priority": 1
}
```

Agrega nuevos mappings para títulos alternativos conocidos.

### legacy_series_fallback.json
```json
{
  "title": "Falling Skies",
  "year": 2011,
  "fallback_action": "MANUAL_REVIEW"
}
```

Para series no indexadas en Plex, marcar como SKIP o MANUAL_REVIEW.

---

## ✅ Validación

Ejecutar después de implementar:

```powershell
# 1. Validar contra baseline
PS> .\ValidatePlexImprovements.ps1

# 2. Ejecutar pipeline mejorado
PS> .\generate_test_data_improved.ps1

# 3. Comparar JSON (antes vs después)
# - Revisar "poster_encontrado" = true (%)
# - Revisar "search_metrics"
# - Revisar duración total

# 4. Target: ≥75% cobertura (+26% vs baseline)
```

---

## 🎯 Próximas Fases (Futuro)

### FASE 5 (OPCIONAL): APIs Externas
- IMDb API fallback
- TMDB API fallback
- Para casos irrecuperables (2-3%)

### FASE 6: Optimizaciones
- Paralelizar búsquedas
- Caché en Redis
- Estadísticas avanzadas

---

## 📝 Changelog

- **v3.0-IMPROVED** (2026-07-01)
  - ✅ FASE 0: Library Lookup (NEW - búsqueda local ultra-rápida)
  - ✅ FASE 1: Encoding + Keywords
  - ✅ FASE 2: Búsqueda Progresiva
  - ✅ FASE 3: Bilingüe
  - ✅ FASE 4: Caché + Fuzzy

- **v2.0** (anterior)
  - Búsqueda básica
  - Cobertura 49%

---

**Documentación Actualizada**: 2026-07-01
**Versión Script**: 3.0-IMPROVED
**Estado**: ✅ LISTO PARA TESTING
