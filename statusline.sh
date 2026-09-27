#!/bin/bash
input=$(cat)

CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
GREEN='\033[32m'
RED='\033[31m'
DIM='\033[2m'
R='\033[0m'

format_num() {
    printf "%d" "$1" | rev | sed 's/.\{3\}/& /g' | rev | sed 's/^ //'
}

eval $(echo "$input" | jq -r '
    @sh "SESSION_ID=\(.session_id // "default")",
    @sh "MODEL=\(.model.display_name // "Unknown")",
    @sh "CWD=\(.cwd // "")",
    @sh "CTX_SIZE=\(.context_window.context_window_size // 200000)",
    @sh "COST=\(.cost.total_cost_usd // 0)",
    @sh "INPUT_TOKENS=\(.context_window.current_usage.input_tokens // -1)",
    @sh "CACHE_CREATE=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
    @sh "CACHE_READ=\(.context_window.current_usage.cache_read_input_tokens // 0)",
    @sh "RL_5H_PCT=\(.rate_limits.five_hour.used_percentage // "")",
    @sh "RL_5H_RESET=\(.rate_limits.five_hour.resets_at // "")",
    @sh "RL_7D_PCT=\(.rate_limits.seven_day.used_percentage // "")",
    @sh "RL_7D_RESET=\(.rate_limits.seven_day.resets_at // "")"
' | tr '\n' ' ')

if [ -n "$CWD" ]; then
    PROJECT_PATH="/$(echo "$CWD" | rev | cut -d'/' -f1-2 | rev)"
else
    PROJECT_PATH=""
fi

STATUSLINE_DIR="$HOME/.claude/extensions/cc-setup"
CACHE_FILE="$STATUSLINE_DIR/ctx-cache-${SESSION_ID}"

# Round to nearest 100 to avoid flicker
if [ "$INPUT_TOKENS" -ge 0 ] 2>/dev/null; then
    CTX_RAW=$((INPUT_TOKENS + CACHE_CREATE + CACHE_READ))
    CTX_TOKENS=$(( (CTX_RAW + 50) / 100 * 100 ))
    if [ "$CTX_TOKENS" -gt 0 ]; then
        echo "$CTX_TOKENS" > "$CACHE_FILE"
    fi
else
    if [ -f "$CACHE_FILE" ]; then
        CTX_TOKENS=$(cat "$CACHE_FILE")
    else
        CTX_TOKENS=0
    fi
fi

if [ "$CTX_SIZE" -gt 0 ] && [ "$CTX_TOKENS" -gt 0 ]; then
    CTX_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($CTX_TOKENS / $CTX_SIZE) * 100}")
else
    CTX_PERCENT="0.0"
fi

COST_FMT=$(printf "%.2f" "$COST")
CTX_FMT=$(format_num $CTX_TOKENS)

BRANCH=$(git branch --show-current 2>/dev/null || echo "N/A")
ADDED=0
REMOVED=0
ADDED_FILES=0
REMOVED_FILES=0
if [ "$BRANCH" != "N/A" ]; then
    while IFS=$'\t' read -r ADD_COUNT REMOVE_COUNT _; do
        if [[ "$ADD_COUNT" =~ ^[0-9]+$ ]]; then
            ADDED=$((ADDED + ADD_COUNT))
        fi
        if [[ "$REMOVE_COUNT" =~ ^[0-9]+$ ]]; then
            REMOVED=$((REMOVED + REMOVE_COUNT))
        fi
    done < <(git diff --numstat HEAD 2>/dev/null)

    while IFS=$'\t' read -r STATUS _; do
        case "$STATUS" in
            A*)
                ADDED_FILES=$((ADDED_FILES + 1))
                ;;
            D*)
                REMOVED_FILES=$((REMOVED_FILES + 1))
                ;;
        esac
    done < <(git diff --name-status HEAD 2>/dev/null)

    # Untracked trees can hold thousands of files and gigabytes of data. One wc
    # per file, over all of them, took minutes and froze the whole machine, so
    # read lines from a bounded sample only and mark the total as a lower bound.
    MAX_UNTRACKED_FILES=500
    MAX_UNTRACKED_SIZE=512k
    UNTRACKED_SAMPLE=()
    while IFS= read -r -d '' UNTRACKED_FILE; do
        ADDED_FILES=$((ADDED_FILES + 1))
        if [ ${#UNTRACKED_SAMPLE[@]} -lt $MAX_UNTRACKED_FILES ]; then
            UNTRACKED_SAMPLE+=("$UNTRACKED_FILE")
        fi
    done < <(git ls-files --others --exclude-standard -z 2>/dev/null)

    LINES_CAPPED=""
    [ $ADDED_FILES -gt $MAX_UNTRACKED_FILES ] && LINES_CAPPED="+"
    if [ ${#UNTRACKED_SAMPLE[@]} -gt 0 ]; then
        UNTRACKED_LINES=$(find "${UNTRACKED_SAMPLE[@]}" -maxdepth 0 -type f -size -"$MAX_UNTRACKED_SIZE" -print0 2>/dev/null \
            | xargs -0 cat 2>/dev/null | wc -l)
        if [[ "$UNTRACKED_LINES" =~ ^[[:space:]]*[0-9]+$ ]]; then
            ADDED=$((ADDED + UNTRACKED_LINES))
        fi
        if [ -n "$(find "${UNTRACKED_SAMPLE[@]}" -maxdepth 0 -type f ! -size -"$MAX_UNTRACKED_SIZE" -print -quit 2>/dev/null)" ]; then
            LINES_CAPPED="+"
        fi
    fi
fi

echo -e "${CYAN}${MODEL}${R} ${DIM}|${R} ${PROJECT_PATH} ${DIM}|${R} ${MAGENTA}${BRANCH}${R} ${DIM}|${R} L: ${GREEN}+${ADDED}${LINES_CAPPED}${R} ${RED}-${REMOVED}${R} ${DIM}|${R} F: ${GREEN}+${ADDED_FILES}${R} ${RED}-${REMOVED_FILES}${R}"

CTX_COST_STR="Ctx: ${CYAN}${CTX_PERCENT}%${R} ${DIM}(${CTX_FMT})${R} ${DIM}|${R} Cost: ${CYAN}\$${COST_FMT}${R}"

# Per-model weekly buckets (e.g. Fable).
MS_STR=""
append_ms() {
    [ -z "$1" ] && return
    local PCT SEG
    PCT=$(printf "%.0f" "$2")
    SEG="$1: ${CYAN}${PCT}%${R}"
    if [ -n "$MS_STR" ]; then
        MS_STR="${MS_STR} ${DIM}|${R} ${SEG}"
    else
        MS_STR="$SEG"
    fi
}

while IFS=$'\t' read -r MS_NAME MS_PCT; do
    append_ms "$MS_NAME" "$MS_PCT"
done < <(echo "$input" | jq -r '.rate_limits.model_scoped // [] | .[] | select(.utilization != null) | "\(.display_name)\t\(.utilization)"' 2>/dev/null)

# The CLI (as of 2.1.241) never fills model_scoped in the statusline input,
# so fall back to polling the usage endpoint (cached, refreshed in background).
if [ -z "$MS_STR" ]; then
    USAGE_CACHE="$STATUSLINE_DIR/usage-scoped.json"
    CACHE_MTIME=$(stat -f %m "$USAGE_CACHE" 2>/dev/null || stat -c %Y "$USAGE_CACHE" 2>/dev/null || echo 0)
    CACHE_AGE=$(( $(date +%s) - CACHE_MTIME ))
    if [ "$CACHE_AGE" -ge 300 ]; then
        touch "$USAGE_CACHE" 2>/dev/null
        (
            TOK=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty')
            if [ -z "$TOK" ] && [ -f "$HOME/.claude/.credentials.json" ]; then
                TOK=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
            fi
            [ -n "$TOK" ] || exit 0
            OUT=$(curl -s --max-time 5 https://api.anthropic.com/api/oauth/usage \
                -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
                -H "anthropic-beta: oauth-2025-04-20" \
                | jq -c 'select(.error == null) | [.limits // [] | .[] | select(.kind == "weekly_scoped" and .scope.model.display_name != null) | {display_name: .scope.model.display_name, utilization: .percent}] | select(length > 0)' 2>/dev/null)
            if [ -n "$OUT" ] && [ "$OUT" != "null" ]; then
                printf '%s\n' "$OUT" > "$USAGE_CACHE.$$" && mv -f "$USAGE_CACHE.$$" "$USAGE_CACHE"
            fi
        ) >/dev/null 2>&1 &
    fi
    if [ -s "$USAGE_CACHE" ]; then
        while IFS=$'\t' read -r MS_NAME MS_PCT; do
            append_ms "$MS_NAME" "$MS_PCT"
        done < <(jq -r '.[]? | "\(.display_name)\t\(.utilization)"' "$USAGE_CACHE" 2>/dev/null)
    fi
fi

if [ -n "$RL_5H_PCT" ] || [ -n "$RL_7D_PCT" ] || [ -n "$MS_STR" ]; then
    LINE2=""

    if [ -n "$RL_5H_PCT" ]; then
        RL_5H_PCT=$(printf "%.0f" "$RL_5H_PCT")
        FH_STR="${CYAN}${RL_5H_PCT}%${R}"
        if [ -n "$RL_5H_RESET" ]; then
            NOW=$(date +%s)
            DIFF=$((RL_5H_RESET - NOW))
            [ "$DIFF" -lt 0 ] && DIFF=0
            HRS=$((DIFF / 3600))
            MINS=$(( (DIFF % 3600) / 60 ))
            FH_STR="${FH_STR} ${HRS}h ${MINS}m"
        fi
        LINE2="$FH_STR"
    fi

    if [ -n "$RL_7D_PCT" ]; then
        RL_7D_PCT=$(printf "%.0f" "$RL_7D_PCT")
        SD_STR="${CYAN}${RL_7D_PCT}%${R}"
        if [ -n "$RL_7D_RESET" ]; then
            SD_DATE=$(date -r "$RL_7D_RESET" "+%a %-I:%M %p" 2>/dev/null || date -d "@$RL_7D_RESET" "+%a %-I:%M %p" 2>/dev/null || echo "")
            if [ -n "$SD_DATE" ]; then
                SD_STR="${SD_STR} ${SD_DATE}"
            fi
        fi
        if [ -n "$LINE2" ]; then
            LINE2="${LINE2} ${DIM}|${R} ${SD_STR}"
        else
            LINE2="$SD_STR"
        fi
    fi

    if [ -n "$MS_STR" ]; then
        if [ -n "$LINE2" ]; then
            LINE2="${LINE2} ${DIM}|${R} ${MS_STR}"
        else
            LINE2="$MS_STR"
        fi
    fi

    if [ -n "$LINE2" ]; then
        LINE2="${LINE2} ${DIM}|${R} ${CTX_COST_STR}"
    else
        LINE2="$CTX_COST_STR"
    fi

    echo -e "$LINE2"
else
    echo -e "$CTX_COST_STR"
fi
