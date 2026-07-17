# Resultados de test — organización

> **Documento de referencia.** Guía completa de modos y pipeline: [`../README_TEST.md`](../README_TEST.md).

## Pipeline actual

| Script | Función |
|--------|---------|
| `test_v4_wrapper.ps1` | Procesa `recursos/torrents.csv`. **FULL:** caché test + pasada 2. **QuickTest:** 10 torrents, caché prod. |
| `run_test_pipeline.ps1` | Wrapper + `AnalyzeResults.ps1` (informe HTML al final) |
| `validation/AnalyzeResults.ps1` | Informe HTML: cobertura, fallos explicados, jerarquía poster, regresión |
| `validation/ConsolidateResults.ps1` | Consolida JSONs |
| `validation/OrganizeResults.ps1` | Organiza resultados |

## Artefactos generados

| Tipo | Ruta | Cuándo |
|------|------|--------|
| JSON resultados | `results/json/TelegramNotifier_Test_*.json` | Cada ejecución del wrapper |
| Validación caché | `results/json/CacheValidation_*.json` | Solo FULL (pasada 2) |
| Informe HTML | `results/analisis/TelegramNotifier_Analisis_*.html` | Tras `AnalyzeResults` o pipeline |
| Caché test | `../recursos/plex_cache_test.json` | Solo FULL (regenerada cada vez) |
| Log activo | `../logs/TelegramNotifier_Test.log` | Durante cualquier test con log |
| Log archivado | `../logs/TelegramNotifier_*.log` | Inicio de cada FULL |

## Estructura de results

```
results/
├── json/
│   ├── TelegramNotifier_Test_*.json
│   ├── CacheValidation_*.json
│   └── pruebas/                    ← JSONs de pruebas puntuales (si se usan)
├── analisis/
│   ├── TelegramNotifier_Analisis_*.html
│   └── pruebas/
└── ORGANIZACION_README.md          ← este archivo
```

## Comandos habituales

```powershell
cd test

# FULL + HTML (recomendado)
.\run_test_pipeline.ps1

# Solo FULL (sin HTML)
.\test_v4_wrapper.ps1

# Análisis de un JSON concreto
.\validation\AnalyzeResults.ps1 -JsonPath "results\json\TelegramNotifier_Test_YYYYMMDD_HHMMSS.json"
```

**Última actualización:** 2026-07-17
