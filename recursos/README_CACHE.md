# Sistema de Caché Persistente - Plex

## 📍 Ubicación del Archivo
```
recursos/plex_cache.json
```

## 🎯 ¿Qué es?

Es una base de datos **persistente** que almacena todos los títulos disponibles en tu Plex con sus IDs (`ratingKey`). Se usa para realizar búsquedas **atómicas** (instantáneas) sin necesidad de consultar la API REST de Plex en cada ejecución.

## 🔄 Cómo Funciona

### Flujo de Carga (Initialize-PlexCache):

```
┌─────────────────────────────────────┐
│  Inicia test_v4_wrapper.ps1         │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  ¿Existe recursos/plex_cache.json?  │
└────┬────────────────────────┬───────┘
     │ SÍ                     │ NO
     │                        │
     ▼                        ▼
┌──────────────────┐    ┌────────────────┐
│ Leer desde       │    │ Consultar API  │
│ archivo (0ms)    │    │ Plex (500ms+)  │
└────────┬─────────┘    └────────┬───────┘
         │                       │
         └───────────┬───────────┘
                     │
                     ▼
          ┌──────────────────────┐
          │ Guardar en archivo   │
          │ para próxima vez     │
          └──────────────────────┘
```

## 📋 Estructura del Archivo

```json
{
  "version": "1.0",
  "lastUpdated": "2026-07-01T13:08:39Z",
  "description": "Caché persistente de Plex",
  "totalItems": 102,
  "cache": [
    {
      "titulo_original": "The Mandalorian",
      "titulo_normalizado": "themandalorian",
      "ratingKey": "1250",
      "tipo": "SERIE",
      "poster_url": "http://127.0.0.1:32400/library/metadata/1250/thumb?...",
      "year": null
    },
    ...
  ]
}
```

## 🚀 Casos de Uso

### 1. **Descarga de Nuevo Torrent**
Si descargas un torrent nuevo, el sistema:
- Busca el título en la caché primero (instantáneo)
- Si no encuentra coincidencia exacta, usa búsqueda fuzzy (85%+)
- Si tampoco hay coincidencia, consulta Plex API (fallback)

### 2. **Búsqueda Rápida por ratingKey**
Ejemplo: Necesitas el poster del título con ratingKey `1250`:

```powershell
$cache = Get-Content "recursos/plex_cache.json" | ConvertFrom-Json
$titulo = $cache.cache | Where-Object { $_.ratingKey -eq "1250" }
$url = $titulo.poster_url
```

### 3. **Buscar por Título Normalizado**
Para encontrar "the mandalorian":

```powershell
$cache = Get-Content "recursos/plex_cache.json" | ConvertFrom-Json
$resultado = $cache.cache | Where-Object { $_.titulo_normalizado -like "*mandalorian*" }
```

## 🔄 Actualizar la Caché

### Opción A: Automáticamente (Por Script)
Simplemente ejecuta `test_v4_wrapper.ps1`. Si Plex tiene nuevos títulos, se agregarán a la caché automáticamente:

```powershell
cd test
.\test_v4_wrapper.ps1
```

### Opción B: Manualmente (Forzar Recarga)
```powershell
cd test

# 1. Elimina la caché actual
Remove-Item "..\recursos\plex_cache.json" -Force

# 2. Carga nuevamente desde Plex
.\test_v4_wrapper.ps1 -QuickTest  # O sin -QuickTest para todos
```

## 📊 Datos Actuales en la Caché

```
Total de títulos: 102
├── Películas: 34
└── Series: 68

Última actualización: 2026-07-01 13:08:39Z
```

## 💾 Ventajas

| Aspecto | Con Caché | Sin Caché |
|---------|-----------|----------|
| Velocidad de búsqueda | 1-5ms | 500ms+ |
| Llamadas API Plex | ~1 (actualización) | 237 (uno por torrent) |
| Carga inicial | 0s | 5s+ |
| Uso de red | Mínimo | Intenso |

## ⚡ Ejemplo: Buscar un Torrent

```powershell
# Usuario descarga: "The.Mandalorian.S02E01.1080p"
# Sistema normaliza: "the-mandalorian-s02e01"
# Busca en caché:

$cache = Get-Content "recursos/plex_cache.json" | ConvertFrom-Json
$resultado = $cache.cache | 
    Where-Object { $_.titulo_normalizado -contains "themandalorian" }

# Resultado: ratingKey = "1250", poster_url = "http://..."
```

## 🔐 Notas Importantes

- El archivo se actualiza automáticamente al ejecutar `test_v4_wrapper.ps1`
- No necesitas modificar el archivo manualmente
- Si eliminas el archivo, se regenerará la próxima ejecución (consultando Plex)
- La caché está en formato JSON limpio y legible

## 📍 Referencia en Script

En `TelegramTorrent_Test.ps1`:
- Ruta de caché: `Join-Path (Split-Path $PSScriptRoot -Parent) "recursos\plex_cache.json"`
- Lectura: `Get-Content $cacheFilePath | ConvertFrom-Json`
- Escritura: `$cacheObject | ConvertTo-Json -Depth 5 | Set-Content $cacheFilePath`

