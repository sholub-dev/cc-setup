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

    while IFS= read -r -d '' UNTRACKED_FILE; do
        if [ -f "$UNTRACKED_FILE" ]; then
            ADDED_FILES=$((ADDED_FILES + 1))
            UNTRACKED_LINES=$(wc -l < "$UNTRACKED_FILE" 2>/dev/null)
            if [[ "$UNTRACKED_LINES" =~ ^[[:space:]]*[0-9]+$ ]]; then
                ADDED=$((ADDED + UNTRACKED_LINES))
            fi
        fi
    done < <(git ls-files --others --exclude-standard -z 2>/dev/null)
fi

echo -e "${CYAN}${MODEL}${R} ${DIM}|${R} ${PROJECT_PATH} ${DIM}|${R} ${MAGENTA}${BRANCH}${R} ${DIM}|${R} L: ${GREEN}+${ADDED}${R} ${RED}-${REMOVED}${R} ${DIM}|${R} F: ${GREEN}+${ADDED_FILES}${R} ${RED}-${REMOVED_FILES}${R}"

CTX_COST_STR="Ctx: ${CYAN}${CTX_PERCENT}%${R} ${DIM}(${CTX_FMT})${R} ${DIM}|${R} Cost: ${CYAN}\$${COST_FMT}${R}"

if [ -n "$RL_5H_PCT" ] || [ -n "$RL_7D_PCT" ]; then
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

    if [ -n "$LINE2" ]; then
        LINE2="${LINE2} ${DIM}|${R} ${CTX_COST_STR}"
    else
        LINE2="$CTX_COST_STR"
    fi

    echo -e "$LINE2"
else
    echo -e "$CTX_COST_STR"
fi
