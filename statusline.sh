#!/bin/bash
# Must run on macOS /bin/bash 3.2: no $EPOCHSECONDS, no printf '%(...)T'.

CYAN=$'\033[1;36m'
MAGENTA=$'\033[1;35m'
GREEN=$'\033[32m'
RED=$'\033[31m'
DIM=$'\033[2m'
R=$'\033[0m'

STATUSLINE_DIR="$HOME/.claude/extensions/cc-setup"
USAGE_CACHE="$STATUSLINE_DIR/usage-scoped.v2"

# Cache format: first line is the last refresh attempt (epoch), then one
# "name<TAB>percent" line per model.
USAGE_TEXT=""
[ -s "$USAGE_CACHE" ] && USAGE_TEXT=$(<"$USAGE_CACHE")

# Program lives in a variable because bash 3.2 mangles backslashes and quotes
# in a $(...) inside double quotes.
read -r -d '' JQ_PROG <<'JQ'
    def cents: (. * 100 + 0.5 | floor) as $x
        | "\($x / 100 | floor).\($x % 100 | if . < 10 then "0\(.)" else tostring end)";
    def seg($p): "\($C)\($p | round)%\($R)";

    " \($D)|\($R) " as $SEP
    | (.context_window.context_window_size // 200000) as $size
    | .context_window.current_usage as $u
    | (if $u.input_tokens != null
       then ((($u.input_tokens + ($u.cache_creation_input_tokens // 0)
               + ($u.cache_read_input_tokens // 0)) + 50) / 100 | floor) * 100
       else -1 end) as $tok
    | (.rate_limits // {}) as $rl
    | ([$rl.model_scoped // [] | .[] | select(.utilization != null)
        | {n: .display_name, p: .utilization}]) as $live
    | ($S | split("\n")) as $lines
    | ($lines[1:] | map(select(length > 0))) as $data
    | ($data | map(split("\t") | {n: .[0], p: (.[1] | tonumber? // 0)})) as $cached
    | (now | floor) as $now
    | (if ($live | length) > 0 then $live else $cached end) as $ms
    | ([
        (($rl.five_hour // {}) | select(.used_percentage != null)
            | seg(.used_percentage)
              + (if .resets_at != null
                 then ((.resets_at - $now) | if . < 0 then 0 else . end)
                      | " \(. / 3600 | floor)h \(. % 3600 / 60 | floor)m"
                 else "" end)),
        (($rl.seven_day // {}) | select(.used_percentage != null)
            | seg(.used_percentage)
              + (if .resets_at != null
                 then " " + (.resets_at | localtime | strftime("%a %-I:%M %p"))
                 else "" end)),
        (if ($ms | length) > 0
         then $ms | map("\(.n): \(seg(.p))") | join($SEP)
         else empty end)
      ] | join($SEP)) as $head
    | @sh "SESSION_ID=\(.session_id // "default")",
      @sh "MODEL=\(.model.display_name // "Unknown")",
      @sh "CWD=\(.cwd // "")",
      @sh "CTX_SIZE=\($size)",
      @sh "CTX_TOKENS=\($tok)",
      @sh "COST_FMT=\(.cost.total_cost_usd // 0 | cents)",
      @sh "LINE2_HEAD=\($head)",
      @sh "NOW=\($now)",
      @sh "USAGE_DATA=\($data | join("\n"))",
      @sh "USAGE_STALE=\(if ($live | length) == 0 and $now - ($lines[0] | tonumber? // 0) >= 300 then 1 else 0 end)"
JQ

eval "$(jq -r --arg C "$CYAN" --arg D "$DIM" --arg R "$R" \
    --arg S "$USAGE_TEXT" "$JQ_PROG")"

PROJECT_PATH=""
BRANCH="N/A"
DIR=""
if [ -n "$CWD" ]; then
    PARENT=${CWD%/*}
    PROJECT_PATH="/${PARENT##*/}/${CWD##*/}"
    DIR=$CWD
    while [ -n "$DIR" ] && [ ! -e "$DIR/.git" ]; do DIR=${DIR%/*}; done
    if [ -n "$DIR" ]; then
        GIT_DIR="$DIR/.git"
        if [ -f "$GIT_DIR" ]; then
            read -r _ GIT_DIR < "$GIT_DIR"
            case $GIT_DIR in /*) ;; *) GIT_DIR="$DIR/$GIT_DIR" ;; esac
        fi
        HEAD_REF=""
        read -r HEAD_REF < "$GIT_DIR/HEAD" 2>/dev/null
        case $HEAD_REF in
            "ref: refs/heads/"*) BRANCH=${HEAD_REF#ref: refs/heads/} ;;
            ?*) BRANCH=${HEAD_REF:0:7} ;;
        esac
    fi
fi

# Rounded to the nearest 100 by jq to avoid flicker. Without current_usage,
# reuse the last value of this session.
CACHE_FILE="$STATUSLINE_DIR/ctx-cache-${SESSION_ID}"
if [ "$CTX_TOKENS" -ge 0 ]; then
    [ "$CTX_TOKENS" -gt 0 ] && echo "$CTX_TOKENS" > "$CACHE_FILE"
else
    CTX_TOKENS=0
    [ -f "$CACHE_FILE" ] && read -r CTX_TOKENS < "$CACHE_FILE"
fi
[ "$CTX_TOKENS" -gt 0 ] 2>/dev/null || CTX_TOKENS=0
CTX_PERCENT="0.0"
if [ "$CTX_TOKENS" -gt 0 ] && [ "$CTX_SIZE" -gt 0 ]; then
    TENTHS=$(( (CTX_TOKENS * 1000 + CTX_SIZE / 2) / CTX_SIZE ))
    CTX_PERCENT="$((TENTHS / 10)).$((TENTHS % 10))"
fi
CTX_FMT=""
DIGITS=$CTX_TOKENS
while [ ${#DIGITS} -gt 3 ]; do
    CTX_FMT=" ${DIGITS: -3}$CTX_FMT"
    DIGITS=${DIGITS%???}
done
CTX_FMT="$DIGITS$CTX_FMT"

# Git stats come from a per-repo cache that a background job refreshes. The
# interval grows with the job's duration so big repos are polled rarely.
GIT_SEG=""
if [ -n "$DIR" ]; then
    STATS_CACHE="$STATUSLINE_DIR/git-stats-${DIR//\//_}"
    G_TIME=0 G_DUR=0 G_ADD="" G_REM="" G_ADD_FILES="" G_REM_FILES=""
    [ -r "$STATS_CACHE" ] && read -r G_TIME G_DUR G_ADD G_REM G_ADD_FILES G_REM_FILES < "$STATS_CACHE"
    case "$G_TIME$G_DUR$G_ADD$G_REM$G_ADD_FILES" in *[!0-9]*) G_REM_FILES="" ;; esac
    if [ -n "$G_REM_FILES" ]; then
        GIT_SEG=" ${DIM}|${R} L: ${GREEN}+${G_ADD}${R} ${RED}-${G_REM}${R} ${DIM}|${R} F: ${GREEN}+${G_ADD_FILES}${R} ${RED}-${G_REM_FILES}${R}"
        INTERVAL=$((G_DUR * 20))
        [ "$INTERVAL" -lt 15 ] && INTERVAL=15
        [ "$INTERVAL" -gt 300 ] && INTERVAL=300
    else
        G_TIME=0 INTERVAL=0
    fi
    if [ $((NOW - G_TIME)) -ge "$INTERVAL" ]; then
        LOCK="$STATS_CACHE.lock"
        # A crashed job leaves its lock behind; drop locks older than 5 minutes.
        if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then
            rmdir "$LOCK" 2>/dev/null
        fi
        if mkdir "$LOCK" 2>/dev/null; then
            (
                trap 'rmdir "$LOCK"' EXIT
                cd "$DIR" || exit 0
                LOW="nice -n 19"
                command -v taskpolicy >/dev/null 2>&1 && LOW="taskpolicy -b"
                START=$(date +%s)
                A=0 D=0 AF=0 DF=0
                if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
                    while IFS=$'\t' read -r N1 N2 _; do
                        case "$N1" in
                            " create mode "*) AF=$((AF + 1)) ;;
                            " delete mode "*) DF=$((DF + 1)) ;;
                            *)
                                [[ "$N1" =~ ^[0-9]+$ ]] && A=$((A + N1))
                                [[ "$N2" =~ ^[0-9]+$ ]] && D=$((D + N2))
                                ;;
                        esac
                    done < <($LOW git --no-optional-locks diff --numstat --summary HEAD 2>/dev/null)
                fi
                # Untracked files count only as added files; reading them costs too much I/O.
                UNTRACKED=$($LOW git --no-optional-locks ls-files --others --exclude-standard 2>/dev/null | wc -l)
                AF=$((AF + UNTRACKED))
                END=$(date +%s)
                printf '%s %s %s %s %s %s\n' "$END" "$((END - START))" "$A" "$D" "$AF" "$DF" > "$STATS_CACHE.$$" \
                    && mv -f "$STATS_CACHE.$$" "$STATS_CACHE"
            ) >/dev/null 2>&1 &
        fi
    fi
fi

if [ "$USAGE_STALE" = 1 ]; then
    # Throttle: record the attempt now, keep the old lines.
    printf '%s\n%s\n' "$NOW" "$USAGE_DATA" > "$USAGE_CACHE.$$" 2>/dev/null && mv -f "$USAGE_CACHE.$$" "$USAGE_CACHE"
    (
        TOK=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty')
        if [ -z "$TOK" ] && [ -f "$HOME/.claude/.credentials.json" ]; then
            TOK=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
        fi
        [ -n "$TOK" ] || exit 0
        OUT=$(curl -s --max-time 5 https://api.anthropic.com/api/oauth/usage \
            -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
            -H "anthropic-beta: oauth-2025-04-20" \
            | jq -r 'select(.error == null) | .limits // [] | .[]
                | select(.kind == "weekly_scoped" and .scope.model.display_name != null)
                | "\(.scope.model.display_name)\t\(.percent)"' 2>/dev/null)
        if [ -n "$OUT" ]; then
            printf '%s\n%s\n' "$(date +%s)" "$OUT" > "$USAGE_CACHE.$$" && mv -f "$USAGE_CACHE.$$" "$USAGE_CACHE"
        fi
    ) >/dev/null 2>&1 &
fi

printf '%s\n' "${CYAN}${MODEL}${R} ${DIM}|${R} ${PROJECT_PATH} ${DIM}|${R} ${MAGENTA}${BRANCH}${R}${GIT_SEG}"

LINE2="Ctx: ${CYAN}${CTX_PERCENT}%${R} ${DIM}(${CTX_FMT})${R} ${DIM}|${R} Cost: ${CYAN}\$${COST_FMT}${R}"
[ -n "$LINE2_HEAD" ] && LINE2="${LINE2_HEAD} ${DIM}|${R} ${LINE2}"
printf '%s\n' "$LINE2"
