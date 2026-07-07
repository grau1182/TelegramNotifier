# 📱 Configuración de Notificaciones Telegram - qBittorrent

## ✅ Cambio Realizado

El script **TelegramNotifier.ps1** ahora tiene el parámetro `-SendTelegram` por defecto en **`$true`**, lo que significa:

- ✅ Los avisos **SE ENVIARÁN AUTOMÁTICAMENTE** a Telegram desde producción
- ✅ No necesitas parámetros adicionales en qBittorrent
- ✅ Cada torrent completado generará un aviso

## 🔧 Configuración en qBittorrent

### Opción 1: Script simple (RECOMENDADO)

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Users\grau_\Downloads\TelegramNotifier\core\TelegramNotifier.ps1" "%N" "%F"
```

**Parámetros qBittorrent:**
- `%N` = Nombre del torrent
- `%F` = Ruta del contenido

### Opción 2: Con control manual (si necesitas desactivar Telegram ocasionalmente)

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Users\grau_\Downloads\TelegramNotifier\core\TelegramNotifier.ps1" "%N" "%F" -SendTelegram:$true
```

### Opción 3: Desactivar Telegram (solo si necesitas)

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Users\grau_\Downloads\TelegramNotifier\core\TelegramNotifier.ps1" "%N" "%F" -SendTelegram:$false
```

## 📋 Dónde configurar en qBittorrent

1. **Abre qBittorrent**
2. **Preferencias → Ejecutar acciones personalizadas**
3. **Crea nueva acción:**
   - **Nombre**: TelegramNotifier
   - **Programa**: `powershell.exe`
   - **Argumentos**: `-ExecutionPolicy Bypass -File "C:\Users\grau_\Downloads\TelegramNotifier\core\TelegramNotifier.ps1" "%N" "%F"`
   - **Evento**: Torrent completado ✓
   - **Ejecutar en**: Sistema

4. **Guarda y aplica**

## ✅ Verificar que Funciona

### Método 1: Ver el log

```powershell
Get-Content "C:\Users\grau_\Downloads\TelegramNotifier\core\logs\TelegramNotifier_*.log" -Tail 20
```

Busca estas líneas:
```
[2026-07-01 XX:XX:XX] [INFO] Notificación Telegram enviada (con poster)
[2026-07-01 XX:XX:XX] [INFO] Notificación Telegram enviada (texto)
```

### Método 2: Test rápido

```powershell
cd C:\Users\grau_\Downloads\TelegramNotifier\core
.\TelegramNotifier.ps1 -TorrentName "Test S01E01 2160p" -ContentPath "G:\SERIES\Test" -SendTelegram
```

## 📞 Credenciales Telegram

El script usa estas credenciales (configuradas en `core/TelegramNotifier.ps1`):

```powershell
$BotToken = "8755898341:AAFSxCy9zjYS_rLl-kFpVPCmJ3V2XLjKjYg"
$ChatID   = "-1004350117652"
```

✅ Verificadas y activas

## 🚨 Troubleshooting

### "Notificación Telegram no llegó"

**Verificar:**
1. El log dice "Notificación Telegram enviada"? → Problema en Telegram API
2. El log dice "Error enviando Telegram"? → Ver el error específico
3. ¿Hay conexión a internet? → Verificar conexión

### "curl.exe no encontrado"

Windows PowerShell 5.1+ incluye `curl.exe`. Si no está:

```powershell
Get-Command curl.exe
```

Si no existe, descargar desde: https://curl.se/download.html

### "Error 401 Telegram"

El token es inválido. Verificar:
- Bot token correcto en `TelegramNotifier.ps1`
- Chat ID correcto (debe ser negativo para chats privados)

## 📊 Estructura del Aviso Telegram

El aviso incluye:

**Con Poster:**
- 🖼️ Imagen del poster (desde Plex)
- 📝 Título, tipo (EPISODIO/PELÍCULA/TEMPORADA), resolución, tamaño

**Sin Poster:**
- 📝 Mensaje de texto con los detalles del contenido

**Ejemplo:**
```
EPISODIO DESCARGADO

The Mandalorian
T02 - E03

2160p
4.5 GB
```

## ✓ Confirmación del Cambio

**Antes:**
```powershell
[switch]$SendTelegram = $false  # ❌ Por defecto NO envía
```

**Ahora:**
```powershell
[switch]$SendTelegram = $true   # ✅ Por defecto SÍ envía
```

---

**Fecha del cambio**: 2026-07-01  
**Versión**: 1.1 (Telegram automático en producción)
