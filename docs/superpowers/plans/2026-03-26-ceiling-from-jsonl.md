# Techo desde JSONL locales — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar la estimación del techo de ventana 5h basada en `ccusage` por una lectura directa de los archivos JSONL locales de Claude Code, filtrada por el rango de tiempo autoritativo de la API.

**Architecture:** El script `statusline-command.sh` ya obtiene `resets_at` del input JSON; se usa ese valor para calcular `window_start = resets_at - 18000` y escanear únicamente los JSONL con timestamps dentro de esa ventana. El resultado se cachea 60 segundos con clave basada en `window_start_epoch` para evitar latencia en el statusline.

**Tech Stack:** POSIX sh, jq, BSD date (macOS), find

---

## Mapa de archivos

| Archivo | Cambio |
|---------|--------|
| `~/.claude/statusline-command.sh` | Eliminar bloque ccusage (líneas 25-43 y 59-91), agregar lógica JSONL |
| `~/Documents/workspace/ctx-5h-monitor/statusline/patch.sh` | Actualizar Section 2 con la nueva lógica |

---

## Task 1: Reemplazar bloque ccusage en statusline-command.sh

**Files:**
- Modify: `~/.claude/statusline-command.sh:25-91`

- [ ] **Step 1: Abrir el archivo y verificar el bloque a reemplazar**

```sh
grep -n "ccusage\|CCUSAGE\|block_json\|CEILING_CACHE" ~/.claude/statusline-command.sh
```

Salida esperada: referencias a ccusage en líneas ~25-91.

- [ ] **Step 2: Eliminar el bloque de fetch de ccusage (primera parte)**

En `~/.claude/statusline-command.sh`, localizar y **eliminar** el siguiente bloque completo (son las líneas que obtienen datos de ccusage con cache):

```sh
CCUSAGE_CACHE="/tmp/ctx-ccusage-cache.json"
CEILING_CACHE="/tmp/ctx-ceiling.json"

# Obtener datos de ccusage con cache de 30 segundos para evitar latencia
block_json=""
if [ -f "$CCUSAGE_CACHE" ]; then
  cache_age=$(( $(date "+%s") - $(date -r "$CCUSAGE_CACHE" "+%s" 2>/dev/null || echo 0) ))
  if [ "$cache_age" -lt 30 ]; then
    block_json=$(cat "$CCUSAGE_CACHE")
  fi
fi
if [ -z "$block_json" ]; then
  block_json=$(ccusage blocks --active --json 2>/dev/null)
  if [ -n "$block_json" ]; then
    tmp_ccusage=$(mktemp /tmp/ctx-ccusage-XXXXXX.json)
    printf '%s' "$block_json" > "$tmp_ccusage" && mv "$tmp_ccusage" "$CCUSAGE_CACHE"
  fi
fi
```

- [ ] **Step 3: Reemplazar el bloque if block_json con la nueva lógica JSONL**

En el mismo archivo, localizar el bloque que empieza con `if [ -n "$block_json" ]` (justo después del bloque de `reset_str`) y termina con su `fi` correspondiente, antes del comentario `# --- Fin lógica ventana 5h ---`. Reemplazar **ese bloque** por:

```sh
# --- Lógica ventana 5h: techo estimado desde JSONL locales ---
ceiling_level=""

if [ -n "$five_hour_reset" ] && [ -n "$five_hour" ]; then
  window_start_epoch=$(( five_hour_reset - 18000 ))
  window_start_iso=$(date -u -r "$window_start_epoch" "+%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null)

  CEILING_CACHE="/tmp/ctx-ceiling-${window_start_epoch}.json"
  WINDOW_MARKER="/tmp/ctx-window-marker-${window_start_epoch}"

  # Limpiar caches de ventanas anteriores
  for _f in /tmp/ctx-ceiling-*.json; do
    [ "$_f" != "$CEILING_CACHE" ] && rm -f "$_f" 2>/dev/null
  done
  for _f in /tmp/ctx-window-marker-*; do
    [ "$_f" != "$WINDOW_MARKER" ] && rm -f "$_f" 2>/dev/null
  done

  # Crear marcador de inicio de ventana (para find -newer)
  if [ ! -f "$WINDOW_MARKER" ] && [ -n "$window_start_iso" ]; then
    touch_time=$(date -r "$window_start_epoch" "+%Y%m%d%H%M.%S" 2>/dev/null)
    touch -t "$touch_time" "$WINDOW_MARKER" 2>/dev/null || touch "$WINDOW_MARKER"
  fi

  # Verificar cache (TTL 60s)
  _use_cache=0
  if [ -f "$CEILING_CACHE" ]; then
    _cache_age=$(( $(date "+%s") - $(date -r "$CEILING_CACHE" "+%s" 2>/dev/null || echo 0) ))
    [ "$_cache_age" -lt 60 ] && _use_cache=1
  fi

  if [ "$_use_cache" = "1" ]; then
    ceiling_level=$(jq -r '.ceilingLevel // empty' "$CEILING_CACHE" 2>/dev/null)
  elif [ -f "$WINDOW_MARKER" ] && [ -n "$window_start_iso" ]; then
    tokens_cc=$(find ~/.claude/projects -name "*.jsonl" -newer "$WINDOW_MARKER" \
      -exec cat {} \; 2>/dev/null | \
      jq -rs --arg ws "$window_start_iso" \
      '[.[] | select(.timestamp? >= $ws) | .message.usage? // empty |
        ((.input_tokens // 0) + (.output_tokens // 0) +
         (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))] | add // 0' \
      2>/dev/null)

    if [ -n "$tokens_cc" ] && [ "$tokens_cc" -gt 0 ] 2>/dev/null; then
      est_ceiling=$(LC_ALL=C awk -v t="$tokens_cc" -v p="$five_hour" \
        'BEGIN { printf "%.0f", t / (p / 100) }')
      if [ "$est_ceiling" -lt 8000000 ]; then
        lvl="Bajo"
      elif [ "$est_ceiling" -lt 18000000 ]; then
        lvl="Medio"
      else
        lvl="Alto"
      fi
      _tmp=$(mktemp /tmp/ctx-ceiling-tmp-XXXXXX.json)
      printf '{"windowStart":%s,"estimatedCeiling":%s,"ceilingLevel":"%s","calculatedAt":"%s"}' \
        "$window_start_epoch" "$est_ceiling" "$lvl" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "$_tmp" && mv "$_tmp" "$CEILING_CACHE"
      ceiling_level="$lvl"
    fi
  fi
fi
# --- Fin lógica ventana 5h ---
```

- [ ] **Step 3: Verificar que no quedan referencias a ccusage en el archivo**

```sh
grep -n "ccusage\|block_json\|CCUSAGE_CACHE" ~/.claude/statusline-command.sh
```

Salida esperada: ninguna línea (salida vacía).

- [ ] **Step 4: Verificar que reset_str sigue calculándose**

```sh
grep -n "reset_str\|five_hour_reset" ~/.claude/statusline-command.sh
```

Salida esperada: al menos las líneas de cálculo de `reset_str` usando `five_hour_reset` (no deben haber desaparecido).

- [ ] **Step 5: Probar el statusline manualmente**

Abrir Claude Code en cualquier directorio. Observar el statusline. Debe mostrar:
- `5h: XX% [Bajo/Medio/Alto]` — con el nivel calculado desde JSONL
- `reset: Xh Ym` — tiempo restante (sin cambios)

Si el nivel no aparece aún (tokens_cc = 0 por ser sesión nueva), es correcto. Aparecerá después de algunos intercambios.

- [ ] **Step 6: Verificar el cache generado**

```sh
ls /tmp/ctx-ceiling-*.json 2>/dev/null && cat /tmp/ctx-ceiling-*.json
```

Salida esperada: un archivo JSON con `windowStart`, `estimatedCeiling`, `ceilingLevel`, `calculatedAt`.

---

## Task 2: Actualizar patch.sh en el repo

**Files:**
- Modify: `~/Documents/workspace/ctx-5h-monitor/statusline/patch.sh:32-97`

- [ ] **Step 1: Reemplazar Section 2 completa en patch.sh**

En `~/Documents/workspace/ctx-5h-monitor/statusline/patch.sh`, localizar todo el contenido entre los comentarios:

```
# =============================================================================
# SECTION 2 — 5h window logic (ceiling estimation + reset countdown)
```

y el siguiente bloque de `# ===`:

```
# =============================================================================
# SECTION 3 —
```

Reemplazar el bloque de Section 2 completo por:

```sh
# =============================================================================
# SECTION 2 — 5h window logic (ceiling estimation)
# Place this block after reading the input variables, before building output.
# Requires: five_hour (from Section 1), five_hour_reset (from Section 1), jq in PATH
# =============================================================================

ceiling_level=""

if [ -n "$five_hour_reset" ] && [ -n "$five_hour" ]; then
  window_start_epoch=$(( five_hour_reset - 18000 ))
  window_start_iso=$(date -u -r "$window_start_epoch" "+%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null)

  CEILING_CACHE="/tmp/ctx-ceiling-${window_start_epoch}.json"
  WINDOW_MARKER="/tmp/ctx-window-marker-${window_start_epoch}"

  # Limpiar caches de ventanas anteriores
  for _f in /tmp/ctx-ceiling-*.json; do
    [ "$_f" != "$CEILING_CACHE" ] && rm -f "$_f" 2>/dev/null
  done
  for _f in /tmp/ctx-window-marker-*; do
    [ "$_f" != "$WINDOW_MARKER" ] && rm -f "$_f" 2>/dev/null
  done

  # Crear marcador de inicio de ventana (para find -newer)
  if [ ! -f "$WINDOW_MARKER" ] && [ -n "$window_start_iso" ]; then
    touch_time=$(date -r "$window_start_epoch" "+%Y%m%d%H%M.%S" 2>/dev/null)
    touch -t "$touch_time" "$WINDOW_MARKER" 2>/dev/null || touch "$WINDOW_MARKER"
  fi

  # Verificar cache (TTL 60s)
  _use_cache=0
  if [ -f "$CEILING_CACHE" ]; then
    _cache_age=$(( $(date "+%s") - $(date -r "$CEILING_CACHE" "+%s" 2>/dev/null || echo 0) ))
    [ "$_cache_age" -lt 60 ] && _use_cache=1
  fi

  if [ "$_use_cache" = "1" ]; then
    ceiling_level=$(jq -r '.ceilingLevel // empty' "$CEILING_CACHE" 2>/dev/null)
  elif [ -f "$WINDOW_MARKER" ] && [ -n "$window_start_iso" ]; then
    tokens_cc=$(find ~/.claude/projects -name "*.jsonl" -newer "$WINDOW_MARKER" \
      -exec cat {} \; 2>/dev/null | \
      jq -rs --arg ws "$window_start_iso" \
      '[.[] | select(.timestamp? >= $ws) | .message.usage? // empty |
        ((.input_tokens // 0) + (.output_tokens // 0) +
         (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))] | add // 0' \
      2>/dev/null)

    if [ -n "$tokens_cc" ] && [ "$tokens_cc" -gt 0 ] 2>/dev/null; then
      est_ceiling=$(LC_ALL=C awk -v t="$tokens_cc" -v p="$five_hour" \
        'BEGIN { printf "%.0f", t / (p / 100) }')
      if [ "$est_ceiling" -lt 8000000 ]; then
        lvl="Bajo"
      elif [ "$est_ceiling" -lt 18000000 ]; then
        lvl="Medio"
      else
        lvl="Alto"
      fi
      _tmp=$(mktemp /tmp/ctx-ceiling-tmp-XXXXXX.json)
      printf '{"windowStart":%s,"estimatedCeiling":%s,"ceilingLevel":"%s","calculatedAt":"%s"}' \
        "$window_start_epoch" "$est_ceiling" "$lvl" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "$_tmp" && mv "$_tmp" "$CEILING_CACHE"
      ceiling_level="$lvl"
    fi
  fi
fi
```

- [ ] **Step 2: Verificar que patch.sh no tiene referencias a ccusage**

```sh
grep -n "ccusage\|CCUSAGE\|block_json" ~/Documents/workspace/ctx-5h-monitor/statusline/patch.sh
```

Salida esperada: ninguna línea.

---

## Task 3: Commit

**Files:**
- `~/.claude/statusline-command.sh`
- `~/Documents/workspace/ctx-5h-monitor/statusline/patch.sh`
- `~/Documents/workspace/ctx-5h-monitor/docs/superpowers/`

- [ ] **Step 1: Verificar diff de statusline-command.sh**

```sh
git -C ~/.claude diff statusline-command.sh 2>/dev/null || diff /dev/null /dev/null
```

Si `~/.claude` no es un repositorio git, saltar este step.

- [ ] **Step 2: Commit en el repo ctx-5h-monitor**

```sh
cd ~/Documents/workspace/ctx-5h-monitor
git add statusline/patch.sh docs/
git commit -m "feat: calcular techo de ventana 5h desde JSONL locales

Reemplaza ccusage blocks --active por lectura directa de los archivos
JSONL de Claude Code, filtrada por window_start = resets_at - 18000.
Elimina el sesgo cuando la ventana de 5h empezó en otra app de Claude."
```

- [ ] **Step 3: Confirmar estado del repo**

```sh
cd ~/Documents/workspace/ctx-5h-monitor && git log --oneline -3
```

Salida esperada: el commit recién creado al tope.
