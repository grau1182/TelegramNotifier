# RESUMEN: REORGANIZACIÓN DE ARCHIVOS

> **Documento histórico (2026-07-01).** Para modos test vs producción, partial scan Plex y comandos actuales, ver [`../README_TEST.md`](../README_TEST.md).

La reorganización de `test/results/` (carpetas `analisis/`, `json/pruebas/`, etc.) describió un pipeline basado en `generate_test_data.ps1`, que **ya no existe**.

## Pipeline actual

| Script | Función |
|--------|---------|
| `test_v4_wrapper.ps1` | Procesa `recursos/torrents.csv` |
| `run_test_pipeline.ps1` | Wrapper + análisis HTML |
| `validation/ConsolidateResults.ps1` | Consolida JSONs |
| `validation/OrganizeResults.ps1` | Organiza resultados |
| `validation/AnalyzeResults.ps1` | Genera informe HTML |

## Estructura de results (referencia)

```
results/
├── torrents.json
├── analisis/
├── json/
└── ORGANIZACION_README.md   ← este archivo
```

---

*Contenido detallado del pipeline original conservado a continuación como referencia histórica.*

## ESTRUCTURA FINAL (histórico)
