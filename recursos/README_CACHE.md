# Sistema de Caché Persistente - Plex

## Ubicación del archivo

```
recursos/plex_cache.json
```

Compartida entre **producción** (`core/`) y **test** (`test/`).

## Qué es

Base de datos persistente con títulos Plex, `ratingKey`, URLs de poster y **aliases automáticos**. Permite búsquedas instantáneas sin consultar la API en cada ejecución.

## Flujo completo (con mejoras v2)

```
Torrent completado
    ↓
Initialize-PlexCache() → lee recursos/plex_cache.json
    ↓
Get-PosterByCache() → exact / alias / fuzzy
    ↓ (miss)
Partial scan Plex + Wait-ForPlexItem (path lookup)
    ↓ (miss)
Search-PlexWithQueries (búsqueda progresiva)
    ↓ (found)
Add-ToCache + alias del título torrent si difiere del título Plex
```

## Estructura del archivo

```json
{
  "version": "1.0",
  "lastUpdated": "2026-07-06T09:00:00Z",
  "totalItems": 109,
  "cache": [
    {
      "titulo_original": "Kingsman: The Secret Service",
      "titulo_normalizado": "kingsmanthesecretservice",
      "ratingKey": "1234",
      "tipo": "PELICULA",
      "poster_url": "http://127.0.0.1:32400/library/metadata/1234/thumb/...",
      "year": 2014,
      "aliases": ["Kingsman, El Servicio Secreto"]
    }
  ]
}
```

### Aliases automáticos

Cuando el poster se encuentra con un título Plex distinto al del torrent (ej. inglés vs español), el sistema guarda el título del torrent en `aliases`. La próxima descarga del mismo contenido será **cache hit** sin llamadas API.

Funciones: `Add-ToCache -Aliases`, `Add-CacheAlias` en `cache-manager.ps1`.

## Casos de uso

### 1. Descarga de torrent nuevo

1. Busca en caché (exacto, alias, fuzzy ≥85%)
2. Si miss: partial scan + lookup por ruta
3. Si miss: búsqueda progresiva (`Kingsman, El...` → `Kingsman`)
4. Al encontrar: guarda entrada + alias

### 2. Búsqueda por ratingKey

```powershell
$cache = Get-Content "recursos/plex_cache.json" | ConvertFrom-Json
$titulo = $cache.cache | Where-Object { $_.ratingKey -eq "1234" }
$url = $titulo.poster_url
```

## Actualizar la caché

### Automáticamente

Cada torrent procesado que encuentra poster nuevo actualiza el archivo.

### Suite de test

```powershell
cd test

# Suite completa (paridad producción, con scan Plex)
.\test_v4_wrapper.ps1

# Suite rápida (10 torrents, sin scan)
.\test_v4_wrapper.ps1 -QuickTest
```

## Ventajas

| Aspecto | Con caché + alias | Sin caché |
|---------|-------------------|-----------|
| Velocidad (hit) | 1-5 ms | 500 ms – 60 s |
| Títulos ES/EN | Alias automático | Re-búsqueda API |
| Llamadas API | Mínimas | Una por torrent |

## Referencia en código

- Ruta: `Get-PlexCacheFilePath` en `cache-manager.ps1` → `recursos/plex_cache.json`
- Escritura: `Add-ToCache`, `Add-CacheAlias`
- Lectura: `Initialize-PlexCache`, `Get-PosterByCache`

## Documentación relacionada

- [`test/README_TEST.md`](../test/README_TEST.md) — modos test vs producción
- [`core/README.md`](../core/README.md) — flujo producción

**Última actualización:** 2026-07-06
