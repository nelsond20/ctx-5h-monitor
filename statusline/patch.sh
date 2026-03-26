#!/bin/sh
# ctx-5h-monitor — Statusline patch
#
# This file shows the code to integrate into your Claude Code statusline script.
# It is NOT an automated patcher — copy the relevant sections into your
# statusline-command.sh manually (see README.md for instructions).
#
# Tested with: ~/.claude/statusline-command.sh
# macOS only — uses BSD date (-jf flag), does not work on Linux.

# =============================================================================
# SECTION 1 — Normalize five_hour percentage
# Place this block where you read .rate_limits.five_hour.used_percentage
# =============================================================================

five_hour_raw=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$five_hour_raw" ]; then
  # Handles both fraction (0–1) and percentage (0–100) formats
  five_hour=$(LC_ALL=C awk -v v="$five_hour_raw" 'BEGIN { printf "%.0f", (v > 0 && v <= 1) ? v*100 : v }')
else
  five_hour=""
fi
# Unix timestamp of window reset — authoritative across all Claude apps
five_hour_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

# =============================================================================
# SECTION 2 — 5h window logic (reset countdown + ceiling estimation from JSONL)
# Place this block after reading the input variables, before building output.
# Requires: five_hour + five_hour_reset (from Section 1), jq + find in PATH
# macOS only — uses BSD date -r for epoch conversion.
# =============================================================================

reset_str=""

# Reset countdown — authoritative (covers all Claude apps)
if [ -n "$five_hour_reset" ]; then
  now_epoch=$(date "+%s")
  remaining_min=$(( (five_hour_reset - now_epoch) / 60 ))
  if [ "$remaining_min" -gt 0 ]; then
    r_h=$(( remaining_min / 60 ))
    r_m=$(( remaining_min % 60 ))
    [ "$r_h" -gt 0 ] && reset_str="${r_h}h ${r_m}m" || reset_str="${r_m}m"
  fi
fi

# Ceiling estimation from JSONL — counts all token types in the current window
# Thresholds: Bajo < 8M, Medio 8–18M, Alto > 18M
ceiling_level=""

if [ -n "$five_hour_reset" ] && [ -n "$five_hour" ] && [ "$five_hour" -gt 0 ] 2>/dev/null; then
  window_start_epoch=$(( five_hour_reset - 18000 ))
  window_start_iso=$(date -u -r "$window_start_epoch" "+%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null)

  CEILING_CACHE="/tmp/ctx-ceiling-${window_start_epoch}.json"
  WINDOW_MARKER="/tmp/ctx-window-marker-${window_start_epoch}"

  # Limpiar caches de ventanas anteriores
  for _f in /tmp/ctx-ceiling-*.json; do
    [ -e "$_f" ] && [ "$_f" != "$CEILING_CACHE" ] && rm -f "$_f" 2>/dev/null
  done
  for _f in /tmp/ctx-window-marker-*; do
    [ -e "$_f" ] && [ "$_f" != "$WINDOW_MARKER" ] && rm -f "$_f" 2>/dev/null
  done

  # Marcador de inicio de ventana (para find -newer)
  if [ ! -f "$WINDOW_MARKER" ] && [ -n "$window_start_iso" ]; then
    touch_time=$(date -r "$window_start_epoch" "+%Y%m%d%H%M.%S" 2>/dev/null)
    touch -t "$touch_time" "$WINDOW_MARKER" 2>/dev/null || touch "$WINDOW_MARKER"
  fi

  # Cache TTL 60s
  _use_cache=0
  if [ -f "$CEILING_CACHE" ]; then
    _cache_mtime=$(date -r "$CEILING_CACHE" "+%s" 2>/dev/null)
    if [ -n "$_cache_mtime" ]; then
      _cache_age=$(( $(date "+%s") - $_cache_mtime ))
      [ "$_cache_age" -lt 60 ] && _use_cache=1
    fi
  fi

  if [ "$_use_cache" = "1" ]; then
    ceiling_level=$(jq -r '.ceilingLevel // empty' "$CEILING_CACHE" 2>/dev/null)
  elif [ -f "$WINDOW_MARKER" ] && [ -n "$window_start_iso" ]; then
    tokens_cc=$(find ~/.claude/projects -name "*.jsonl" -newer "$WINDOW_MARKER" \
      -exec cat {} + 2>/dev/null | \
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
      printf '{"windowStart":%s,"windowEnd":%s,"estimatedCeiling":%s,"ceilingLevel":"%s","calculatedAt":"%s"}' \
        "$window_start_epoch" "$five_hour_reset" "$est_ceiling" "$lvl" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_tmp" && mv "$_tmp" "$CEILING_CACHE"
      ceiling_level="$lvl"
    fi
  fi
fi

# =============================================================================
# SECTION 3 — Display: add 5h fields to the statusline output string
# Place this where you build the $parts output string, after ctx% is added.
# =============================================================================

if [ -n "$five_hour" ]; then
  five_str="5h: $(printf '%.0f' "$five_hour")%"
  [ -n "$ceiling_level" ] && five_str="${five_str} [${ceiling_level}]"
  parts="${parts} | ${five_str}"
fi
[ -n "$reset_str" ] && parts="${parts} | reset: ${reset_str}"
