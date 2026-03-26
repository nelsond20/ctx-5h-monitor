# Diseño: Techo de ventana 5h desde JSONL locales

**Fecha:** 2026-03-26
**Estado:** Aprobado

---

## Problema

El cálculo actual del techo `[Alto/Medio/Bajo]` en `statusline-command.sh` usa `ccusage blocks --active` para obtener los tokens del bloque activo y divide por `five_hour_pct`:

```sh
est_ceiling = ccusage_totalTokens / (five_hour_pct / 100)
```

Si la ventana de 5h empezó en claude.ai o mobile antes de que Claude Code arrancara, el bloque activo de ccusage tiene menos tokens que los realmente consumidos en la ventana. El resultado: el techo queda subestimado y el nivel `[Bajo/Medio/Alto]` es incorrecto.

## Objetivo

Calcular los tokens de Claude Code consumidos en la ventana actual de 5h leyendo directamente los archivos JSONL locales, filtrando por el rango de tiempo que la API define como la ventana actual. Eliminar la dependencia de ccusage en `statusline-command.sh`.

---

## Arquitectura

### Fuente de datos

| Dato | Fuente | Notas |
|------|--------|-------|
| `window_start` | `resets_at - 18000` (input JSON) | Autoritativo, incluye todas las apps |
| `five_hour_pct` | `rate_limits.five_hour.used_percentage` (input JSON) | Autoritativo |
| `tokens_cc_ventana` | JSONL en `~/.claude/projects/**/*.jsonl` | Solo Claude Code, filtrado por timestamp |

### Cálculo del techo

```
window_start_epoch = resets_at - 18000
window_start_iso   = ISO 8601 de window_start_epoch

tokens_cc_ventana  = suma de (input_tokens + output_tokens +
                     cache_creation_input_tokens + cache_read_input_tokens)
                     de todos los mensajes en JSONL con timestamp >= window_start_iso

est_ceiling = tokens_cc_ventana / (five_hour_pct / 100)
```

### Clasificación

| Rango | Nivel |
|-------|-------|
| < 8M tokens | Bajo |
| 8M – 18M tokens | Medio |
| > 18M tokens | Alto |

### Estrategia de cache

- Archivo: `/tmp/ctx-ceiling-<window_start_epoch>.json`
- TTL: 60 segundos
- Invalidación: al detectar un `resets_at` distinto al cacheado, eliminar `/tmp/ctx-ceiling-*.json` y recalcular
- La clave incluye `window_start_epoch`, por lo que al cambiar la ventana el cache anterior queda automáticamente huérfano

### Optimización de rendimiento

- Crear un archivo marcador `/tmp/ctx-window-marker-<window_start_epoch>` con `touch -t <window_start_timestamp>`
- Usar `find ~/.claude/projects -name "*.jsonl" -newer <marker>` para procesar solo archivos modificados dentro de la ventana actual
- El cache de 60s evita el scan en la mayoría de llamadas al statusline

---

## Flujo de datos

```
input JSON
  → resets_at, five_hour_pct
  → window_start = resets_at - 18000
  → [cache hit?] → leer /tmp/ctx-ceiling-<window_start_epoch>.json
  → [cache miss] → find *.jsonl -newer <marker>
                 → jq: filtrar timestamp >= window_start_iso, sumar tokens
                 → est_ceiling = tokens / (pct / 100)
                 → escribir cache
  → clasificar [Bajo/Medio/Alto]
  → mostrar en statusline
```

---

## Casos borde

| Caso | Comportamiento |
|------|----------------|
| Sin archivos JSONL en la ventana (`tokens_cc_ventana = 0`) | Omitir el nivel, no calcular |
| `five_hour_pct` ausente o = 0 | Omitir el nivel, no calcular |
| `resets_at` ausente del input JSON | Omitir el nivel, no calcular |
| Cache de ventana anterior detectado | Limpiar `/tmp/ctx-ceiling-*.json`, recalcular |

---

## Cambios en archivos

| Archivo | Cambio |
|---------|--------|
| `~/.claude/statusline-command.sh` | Reemplazar bloque de ccusage por lectura de JSONL + nuevo cache |
| `~/Documents/workspace/ctx-5h-monitor/statusline/patch.sh` | Mismo cambio (es la copia del repo) |
| `ctx-status.sh` | Sin cambios (script separado, fuera de scope) |

---

## Fuera de scope

- Techo histórico basado en promedio de ventanas anteriores (tarea pendiente separada)
- Cambios en `ctx-status.sh`
