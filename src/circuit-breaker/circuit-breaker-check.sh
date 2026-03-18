#!/bin/bash
# circuit-breaker-check.sh — Validate sprint tasks against circuit breaker state
# Runs after sprint creation as safety net
# Also runs independently every 30min to catch manual posts

set -euo pipefail

LOCK="/tmp/cb-check.lock"
LOG="/root/clawd/logs/circuit-breaker.log"
STATE="/root/clawd/logs/sprint-creator-state.json"
METRICS_DIR="/root/clawd/content-engine/data/metrics"

if [[ -f "$LOCK" ]]; then
    pid=$(cat "$LOCK" 2>/dev/null)
    if kill -0 "$pid" 2>/dev/null; then exit 0; fi
    rm -f "$LOCK"
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# Load state or initialize
if [[ -f "$STATE" ]]; then
    CB=$(jq '.' "$STATE" 2>/dev/null)
else
    CB='{"circuitBreakers":{"content":{"state":"CLOSED","consecutiveLow":0,"lastCheck":""},"engagement":{"state":"CLOSED","consecutiveLow":0,"lastCheck":""},"following":{"state":"CLOSED","consecutiveLow":0,"lastCheck":""}}}'
fi

CONTENT_STATE=$(echo "$CB" | jq -r '.circuitBreakers.content.state // "CLOSED"')
ENGAGEMENT_STATE=$(echo "$CB" | jq -r '.circuitBreakers.engagement.state // "CLOSED"')
FOLLOWING_STATE=$(echo "$CB" | jq -r '.circuitBreakers.following.state // "CLOSED"')

ALERTS=()

# --- Check Content Circuit Breaker ---
# Get recent posts
if command -v twitter &>/dev/null; then
    RECENT=$(twitter user-posts agentxagi --max 5 2>/dev/null || echo "")

    if [[ -n "$RECENT" ]]; then
        # Extract views from recent posts
        VIEWS=$(echo "$RECENT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tweets = data.get('data', [])
    if tweets:
        views = [t.get('metrics', {}).get('views', 0) for t in tweets]
        print(json.dumps({'views': views, 'avg': sum(views)/len(views), 'count': len(views)}))
except:
    print(json.dumps({'views': [], 'avg': 0, 'count': 0}))
" 2>/dev/null || echo '{"views":[],"avg":0,"count":0}')

        AVG_VIEWS=$(echo "$VIEWS" | jq '.avg // 0')
        LOW_COUNT=$(echo "$VIEWS" | jq '.views | map(select(. < 50)) | length')
        HIGH_COUNT=$(echo "$VIEWS" | jq '.views | map(select(. > 100)) | length')

        # Update consecutive counters
        case $CONTENT_STATE in
            CLOSED)
                if [[ "$LOW_COUNT" -ge 3 ]]; then
                    CONTENT_STATE="HALF_OPEN"
                    ALERTS+=("CONTENT: CLOSED → HALF_OPEN (${LOW_COUNT}/5 recent posts < 50 views, avg=${AVG_VIEWS})")
                fi
                ;;
            HALF_OPEN)
                if [[ "$HIGH_COUNT" -ge 3 ]]; then
                    CONTENT_STATE="CLOSED"
                    ALERTS+=("CONTENT: HALF_OPEN → CLOSED (${HIGH_COUNT}/5 posts > 100 views, avg=${AVG_VIEWS})")
                elif [[ "$LOW_COUNT" -ge 5 ]]; then
                    CONTENT_STATE="OPEN"
                    ALERTS+=("CONTENT: HALF_OPEN → OPEN (${LOW_COUNT}/5 posts < 20 views, avg=${AVG_VIEWS})")
                fi
                ;;
            OPEN)
                # Auto-recovery after 2h cooldown
                LAST_OPEN=$(echo "$CB" | jq -r '.circuitBreakers.content.openedAt // ""' 2>/dev/null)
                if [[ -n "$LAST_OPEN" ]]; then
                    OPEN_EPOCH=$(date -d "$LAST_OPEN" +%s 2>/dev/null || echo 0)
                    NOW_EPOCH=$(date +%s)
                    ELAPSED=$(( (NOW_EPOCH - OPEN_EPOCH) / 3600 ))
                    if [[ "$ELAPSED" -ge 2 ]]; then
                        CONTENT_STATE="HALF_OPEN"
                        ALERTS+=("CONTENT: OPEN → HALF_OPEN (cooldown ${ELAPSED}h elapsed)")
                    fi
                fi
                ;;
        esac
    fi
fi

# --- Check Following Circuit Breaker ---
PROFILE=$(twitter user agentxagi 2>/dev/null || echo "")
if [[ -n "$PROFILE" ]]; then
    FOLLOWERS=$(echo "$PROFILE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    u = d.get('data', {}).get('user', {}).get('result', {}).get('legacy', {})
    print(f\"{u.get('followers_count', 0)}|{u.get('friends_count', 0)}\")
except:
    print('0|0')
" 2>/dev/null || echo "0|0")

    FOLLOWERS_COUNT=$(echo "$FOLLOWERS" | cut -d'|' -f1)
    FOLLOWING_COUNT=$(echo "$FOLLOWERS" | cut -d'|' -f2)

    if [[ "$FOLLOWING_COUNT" -gt 0 && "$FOLLOWERS_COUNT" -gt 0 ]]; then
        RATIO=$(python3 -c "print(f\"{$FOLLOWING_COUNT/$FOLLOWERS_COUNT:.2f}\")")
        RATIO_NUM=$(python3 -c "print(f\"{$FOLLOWING_COUNT/$FOLLOWERS_COUNT:.1f}\")")

        case $FOLLOWING_STATE in
            CLOSED)
                if (( $(echo "$RATIO_NUM < 1.5" | bc -l) )); then
                    FOLLOWING_STATE="HALF_OPEN"
                    ALERTS+=("FOLLOWING: CLOSED → HALF_OPEN (ratio ${RATIO}:1 < 1.5)")
                fi
                ;;
            HALF_OPEN)
                if (( $(echo "$RATIO_NUM > 2.0" | bc -l) )); then
                    FOLLOWING_STATE="CLOSED"
                    ALERTS+=("FOLLOWING: HALF_OPEN → CLOSED (ratio ${RATIO}:1 > 2.0)")
                elif (( $(echo "$RATIO_NUM < 1.2" | bc -l) )); then
                    FOLLOWING_STATE="OPEN"
                    ALERTS+=("FOLLOWING: HALF_OPEN → OPEN (ratio ${RATIO}:1 < 1.2)")
                fi
                ;;
            OPEN)
                LAST_OPEN=$(echo "$CB" | jq -r '.circuitBreakers.following.openedAt // ""' 2>/dev/null)
                if [[ -n "$LAST_OPEN" ]]; then
                    OPEN_EPOCH=$(date -d "$LAST_OPEN" +%s 2>/dev/null || echo 0)
                    NOW_EPOCH=$(date +%s)
                    ELAPSED=$(( (NOW_EPOCH - OPEN_EPOCH) / 3600 ))
                    if [[ "$ELAPSED" -ge 6 ]]; then
                        FOLLOWING_STATE="HALF_OPEN"
                        ALERTS+=("FOLLOWING: OPEN → HALF_OPEN (cooldown ${ELAPSED}h elapsed)")
                    fi
                fi
                ;;
        esac
    fi
fi

# --- Save State ---
NOW=$(date -Iseconds)

# Track openedAt when transitioning to OPEN
if [[ "$CONTENT_STATE" == "OPEN" ]] && [[ "$(echo "$CB" | jq -r '.circuitBreakers.content.state // "CLOSED"')" != "OPEN" ]]; then
    CB=$(echo "$CB" | jq --arg now "$NOW" '.circuitBreakers.content.openedAt = $now')
fi
if [[ "$FOLLOWING_STATE" == "OPEN" ]] && [[ "$(echo "$CB" | jq -r '.circuitBreakers.following.state // "CLOSED"')" != "OPEN" ]]; then
    CB=$(echo "$CB" | jq --arg now "$NOW" '.circuitBreakers.following.openedAt = $now')
fi

CB=$(echo "$CB" | jq \
    --arg cs "$CONTENT_STATE" \
    --arg es "$ENGAGEMENT_STATE" \
    --arg fs "$FOLLOWING_STATE" \
    --arg now "$NOW" \
    '.circuitBreakers.content.state = $cs | .circuitBreakers.content.lastCheck = $now |
     .circuitBreakers.engagement.state = $es | .circuitBreakers.engagement.lastCheck = $now |
     .circuitBreakers.following.state = $fs | .circuitBreakers.following.lastCheck = $now')

echo "$CB" > "$STATE"

# Log
if [[ ${#ALERTS[@]} -gt 0 ]]; then
    for alert in "${ALERTS[@]}"; do
        echo "[$(date)] ⚡ $alert" >> "$LOG"
    done
fi

echo "[$(date)] Content=${CONTENT_STATE} Engagement=${ENGAGEMENT_STATE} Following=${FOLLOWING_STATE} | Alerts: ${#ALERTS[@]}" >> "$LOG"
