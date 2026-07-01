# ==================================================
# LOGGER.PS1 - Sistema de Logging
# ==================================================
# Gestiona logs de producción con rotación automática

param()

# Variables globales
$script:LogFile = $null
$script:LogFolder = $null

function Initialize-Logger {
    param([string]$LogPath = ".\logs")
    
    $script:LogFolder = $LogPath
    $script:LogFile = Join-Path $LogPath "TelegramNotifier_$(Get-Date -Format 'yyyyMMdd').log"
    
    if (-not (Test-Path $script:LogFolder)) {
        New-Item -ItemType Directory -Path $script:LogFolder -Force | Out-Null
    }
}

function Rotate-Log {
    if (-not (Test-Path $script:LogFile)) {
        return
    }

    $SizeMB = (Get-Item $script:LogFile).Length / 1MB

    if ($SizeMB -ge 5) {
        $Date = Get-Date -Format "yyyyMMdd_HHmmss"
        Rename-Item -Path $script:LogFile -NewName "TelegramNotifier_$Date.log"
    }
}

function Write-Log {
    param([string]$Text, [string]$Level = "INFO")
    
    if (-not $script:LogFile) {
        Initialize-Logger
    }

    Rotate-Log

    try {
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogEntry = "[$Timestamp] [$Level] $Text"
        
        Add-Content -Path $script:LogFile -Value $LogEntry -Encoding UTF8
        
        # También mostrar en consola
        $color = switch ($Level) {
            "ERROR"   { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default   { "White" }
        }
        
        Write-Host $LogEntry -ForegroundColor $color
    }
    catch {
        Write-Host "ERROR escribiendo log: $($_.Exception.Message)" -ForegroundColor Red
    }
}
