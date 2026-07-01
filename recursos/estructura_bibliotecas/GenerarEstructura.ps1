# GenerarEstructura.ps1
# Genera un árbol de directorios y archivos desde la carpeta actual
# Salida: EstructuraTelegramNotifier.txt

$outputFile = Join-Path (Get-Location) "EstructuraTelegramNotifier.txt"

# Vaciar el archivo si existe
"" | Set-Content $outputFile -Encoding UTF8

function Write-Tree {
    param(
        [string]$Path,
        [string]$Prefix = ""
    )

    $items = Get-ChildItem -LiteralPath $Path -Force | Sort-Object @{Expression={$_.PSIsContainer};Descending=$true}, Name

    for ($i = 0; $i -lt $items.Count; $i++) {

        $item = $items[$i]

        $isLast = ($i -eq $items.Count - 1)

        if ($isLast) {
            $connector = "└── "
            $nextPrefix = $Prefix + "    "
        }
        else {
            $connector = "├── "
            $nextPrefix = $Prefix + "│   "
        }

        Add-Content $outputFile ($Prefix + $connector + $item.Name)

        if ($item.PSIsContainer) {
            Write-Tree -Path $item.FullName -Prefix $nextPrefix
        }
    }
}

$rootName = Split-Path (Get-Location) -Leaf
Add-Content $outputFile $rootName
Write-Tree -Path (Get-Location)

Write-Host ""
Write-Host "Estructura generada correctamente:"
Write-Host $outputFile