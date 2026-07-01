# 🚀 TelegramNotifier - Versión Producción

Versión de producción limpia y optimizada del sistema de notificación de torrents con integración Plex.

## 📋 Contenido

```
core/
├── run.ps1                          # Ejecutable principal
├── TelegramNotifier.ps1             # Script principal (importa librerías)
├── lib/
│   ├── logger.ps1                   # Sistema de logging con rotación
│   ├── utilities.ps1                # Funciones generales (parseo, normalización)
│   ├── cache-manager.ps1            # Gestión de caché Plex persistente
│   └── plex-functions.ps1           # Búsqueda y obtención de posters Plex
├── config/
│   ├── plex_cache.json              # Caché persistente (auto-generado)
│   ├── title_overrides.json         # Sobrescrituras de títulos
│   └── legacy_series_fallback.json  # Fallback para series
├── logs/                            # Logs de ejecución
└── README.md                        # Este archivo
```

## 🎯 Características

✅ **Sistema de Caché Persistente**
- Carga inicial desde archivo: 0 segundos
- 100+ títulos Plex almacenados
- Auto-actualización cuando encuentra nuevos títulos

✅ **Búsqueda Inteligente de Posters**
- Búsqueda exacta en caché
- Búsqueda fuzzy (85%+ similitud)
- Fallback a API Plex si no está en caché

✅ **Logging Automático**
- Rotación de logs en 5MB
- Timestamps para cada operación
- Niveles: INFO, WARNING, ERROR, SUCCESS

✅ **Modular y Limpio**
- Separación de responsabilidades en librerías
- Fácil de mantener y extender
- Sin código de testing

## 🚀 Uso

### Búsqueda de Poster Básica

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\core

# Buscar poster para un torrent
.\run.ps1 -TorrentName "the-boys-s05e01-amzn-web-dl.mkv" -ContentPath "D:\Series\The Boys"
```

### Envío a Telegram

```powershell
# Buscar poster y enviar a Telegram
.\run.ps1 -TorrentName "minority-report-2002.mkv" -ContentPath "D:\Películas" -SendTelegram
```

### Uso Programático

```powershell
# Desde otro script
$params = @{
    TorrentName = "the-expanse-s01.mkv"
    ContentPath = "D:\Series\The Expanse"
    SendTelegram = $true
    ConfigPath = ".\core"
}

& "C:\...\core\run.ps1" @params
```

## 📦 Configuración

### Credenciales Plex

Editar `TelegramNotifier.ps1` líneas 12-14:

```powershell
$PlexUrl   = "http://127.0.0.1:32400"
$PlexToken = "Tu-Token-Plex-Aqui"
```

### Credenciales Telegram

Editar `TelegramNotifier.ps1` líneas 10-11:

```powershell
$BotToken = "Tu-Bot-Token"
$ChatID   = "Tu-Chat-ID"
```

### Sobrescrituras de Títulos

`config/title_overrides.json`:

```json
{
  "the-boys": "The Boys",
  "from-2022": "From",
  "breaking-bad": "Breaking Bad"
}
```

## 🔧 Arquitectura

### Flujo de Búsqueda

```
1. Process-Torrent()
   └─ Normaliza nombre y extrae metadata
   
2. Get-PlexPoster()
   ├─ Intenta caché (Initialize-PlexCache + Get-PosterByCache)
   │  └─ Búsqueda exacta + fuzzy (85%+)
   │
   └─ Si no está: busca en Plex API
      ├─ Por tipo (película/serie/episodio)
      ├─ Calcula scores de coincidencia
      └─ Auto-actualiza caché (Add-ToCache)

3. Send-TelegramNotification() [opcional]
   └─ Envía foto/mensaje a Telegram
```

### Librerías Modulares

| Librería | Responsabilidad | Funciones Clave |
|----------|-----------------|-----------------|
| **logger.ps1** | Sistema de logging | Initialize-Logger, Write-Log, Rotate-Log |
| **utilities.ps1** | Parsing y normalización | Normalize-Name, Get-CleanName, Get-PatternDetected, Convert-Title |
| **cache-manager.ps1** | Gestión caché Plex | Initialize-PlexCache, Add-ToCache, Get-PosterByCache, Get-FuzzyMatchScore |
| **plex-functions.ps1** | Búsqueda Plex | Get-PlexPoster, Get-PlexMatchScore, Get-PlexPosterFromItem |

## 📊 Caché Persistente

### Ubicación
`config/plex_cache.json`

### Estructura

```json
{
  "version": "1.0",
  "lastUpdated": "2026-07-01T13:23:08Z",
  "totalItems": 108,
  "cache": [
    {
      "titulo_normalizado": "themandalorian",
      "titulo_original": "The Mandalorian",
      "ratingKey": "1250",
      "tipo": "SERIE",
      "poster_url": "http://127.0.0.1:32400/library/metadata/1250/thumb?...",
      "year": null
    }
  ]
}
```

### Auto-Actualización

- Se actualiza automáticamente cuando encuentra un nuevo título en Plex
- Solo agrega si no existe (verifica por titulo_normalizado + ratingKey)
- Se guarda cada vez que se encuentra un nuevo título
- Timestamp siempre actualizado

## 📝 Logging

### Ubicación
`logs/TelegramNotifier_YYYYMMDD.log`

### Ejemplo

```
[2026-07-01 13:15:32] [INFO] ========================================
[2026-07-01 13:15:32] [INFO] Procesando torrent: the-boys-s05e01.mkv
[2026-07-01 13:15:32] [INFO] Ruta: D:\Series\The Boys
[2026-07-01 13:15:32] [INFO] Tipo: EPISODIO (S05E01)
[2026-07-01 13:15:32] [INFO] Título detectado: The Boys
[2026-07-01 13:15:32] [SUCCESS] Poster encontrado: http://127.0.0.1:32400/...
```

### Rotación Automática
- Archivo actual: `TelegramNotifier_YYYYMMDD.log`
- Archivos: máximo 5MB
- Cuando se alcanza: se renombra con timestamp (ej: `TelegramNotifier_20260701_131532.log`)

## 🔄 Detección de Patrones

| Patrón | Regex | Ejemplo |
|--------|-------|---------|
| EPISODIO_SIMPLE | `^(.*?)-s(\d{1,2})e(\d{1,2})` | `the-boys-s05e01` |
| TEMPORADA | `^(.*?)-s(\d{1,2})(?:-\|$)` | `the-expanse-s01-[pack]` |
| PELICULA_CON_AÑO | `^(.*?)[-\s\(](19\d{2}\|20\d{2})` | `minority-report-(2002)` |
| SIN_PATRON | (No coincide) | `random-content` |

## ⚙️ Algoritmo Fuzzy Matching

Para caché local (sin API):

1. **Exacto (100%)**: titulo_normalizado coincide exactamente
2. **Fuzzy (85%+)**: Similitud de caracteres ≥ 85%
3. **No encontrado**: Score < 85% → búsqueda en API

Ejemplo:
- "the mandalorian" vs "themandalorian" → 100% (exacto)
- "themandalorian" vs "themndalorian" → 91% (fuzzy, 1 char falta)

## 🛡️ Mantenimiento

### Limpiar Logs Antiguos

```powershell
Remove-Item "core\logs\TelegramNotifier_*.log" -OlderThan (Get-Date).AddDays(-30)
```

### Resetear Caché (recarga desde Plex)

```powershell
Remove-Item "core\config\plex_cache.json"
# Próxima ejecución recargará desde Plex API
```

### Ver Caché Actual

```powershell
$cache = Get-Content "core\config\plex_cache.json" | ConvertFrom-Json
$cache.cache | Format-Table titulo_original, tipo, year
```

## 📈 Performance

| Operación | Tiempo |
|-----------|--------|
| Búsqueda exacta en caché | 1-5ms |
| Búsqueda fuzzy en caché | 5-20ms |
| Carga caché desde archivo | 0 segundos |
| Búsqueda en Plex API | 500ms - 2s |
| Proceso completo (con caché) | ~50ms |
| Proceso completo (sin caché) | ~1s |

## 🐛 Troubleshooting

### "Caché no disponible. Cargando desde Plex API..."
- ✅ Normal en primer uso
- ✅ Se creará `config/plex_cache.json` automáticamente

### "Error connecting to Plex"
- Verificar IP/puerto Plex: `http://127.0.0.1:32400`
- Verificar token en `TelegramNotifier.ps1`

### "No se encontró poster"
- Título no existe en Plex
- Verificar en Plex manualmente
- Considerar usar `config/title_overrides.json`

## 📚 Referencia Rápida

```powershell
# Ver caché
$cache = Get-Content "config\plex_cache.json" | ConvertFrom-Json; $cache.cache.Count

# Ver logs recientes
Get-Content "logs\TelegramNotifier_*.log" -Tail 20

# Ejecutar con debug
Set-PSDebug -Trace 1
.\run.ps1 -TorrentName "test.mkv"
Set-PSDebug -Trace 0
```

## 📞 Soporte

Para issues o mejoras, ver documentación de test en `/test`

---

**Última actualización**: 2026-07-01  
**Versión**: 1.0 (Producción)
