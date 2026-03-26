#!/bin/sh
CEILING_CACHE="/tmp/ctx-ceiling.json"

# Fresh data from ccusage — no cache, CLI always wants current state
block_json=$(ccusage blocks --active --json 2>/dev/null)

if [ -z "$block_json" ]; then
  echo "[No ccusage data — is a Claude Code session active?]"
  exit 0
fi

block_id=$(echo "$block_json" | jq -r '.blocks[0].id // empty')
total_tokens=$(echo "$block_json" | jq -r '.blocks[0].totalTokens // 0')
end_time_raw=$(echo "$block_json" | jq -r '.blocks[0].endTime // empty')
burn_rate=$(echo "$block_json" | jq -r '.blocks[0].burnRate.tokensPerMinute // 0')

# Calculate time remaining until window reset
reset_str="unknown"
if [ -n "$end_time_raw" ]; then
  end_time_clean=$(echo "$end_time_raw" | sed 's/\.[0-9]*Z$//')
  end_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "$end_time_clean" "+%s" 2>/dev/null)
  now_epoch=$(date "+%s")
  if [ -n "$end_epoch" ] && [ -n "$now_epoch" ]; then
    remaining_min=$(( (end_epoch - now_epoch) / 60 ))
    if [ "$remaining_min" -gt 0 ]; then
      r_h=$(( remaining_min / 60 ))
      r_m=$(( remaining_min % 60 ))
      if [ "$r_h" -gt 0 ]; then
        reset_str="${r_h}h ${r_m}m"
      else
        reset_str="${r_m}m"
      fi
    else
      reset_str="resetting..."
    fi
  fi
fi

# Read ceiling from cache (written by the statusline integration)
estimated_ceiling=""
ceiling_level=""
if [ -f "$CEILING_CACHE" ]; then
  cached_block_id=$(jq -r '.blockId // empty' "$CEILING_CACHE" 2>/dev/null)
  if [ "$cached_block_id" = "$block_id" ]; then
    estimated_ceiling=$(jq -r '.estimatedCeiling // empty' "$CEILING_CACHE" 2>/dev/null)
    ceiling_level=$(jq -r '.ceilingLevel // empty' "$CEILING_CACHE" 2>/dev/null)
  fi
fi

# Format values
tokens_m=$(LC_ALL=C awk -v t="$total_tokens" 'BEGIN { printf "%.1f", t / 1000000 }')
burn_k=$(LC_ALL=C awk -v b="$burn_rate" 'BEGIN { printf "%.0f", b / 1000 }')

# Build output line
case "$estimated_ceiling" in
  ''|*[!0-9]*) estimated_ceiling="" ;;
esac
if [ -n "$estimated_ceiling" ] && [ "$estimated_ceiling" -gt 0 ]; then
  ceiling_m=$(LC_ALL=C awk -v c="$estimated_ceiling" 'BEGIN { printf "%.1f", c / 1000000 }')
  used_pct=$(LC_ALL=C awk -v t="$total_tokens" -v c="$estimated_ceiling" 'BEGIN { printf "%.0f", t / c * 100 }')
  echo "[Ceiling: ${ceiling_level} ~${ceiling_m}M] ${used_pct}% used (${tokens_m}M tokens) | Burn: ${burn_k}k tok/min | Resets in ${reset_str}"
else
  echo "[Ceiling: calculating...] ${tokens_m}M tokens | Burn: ${burn_k}k tok/min | Resets in ${reset_str}"
fi
