#!/bin/bash
# paperclip-coordinator.sh — MoltGus Paperclip Coordinator v2
# Roda a cada 15min via cron
# Função: Detect pedidos de ajuda, monitora comentários, alerta sobre tasks críticas
#
# Cron: */15 * * * * /root/clawd/scripts/paperclip-coordinator.sh >> /root/clawd/logs/paperclip-coordinator.log 2>&1
#
# Este coordinator é um MONITOR LEVE — detecta e loga.
# MoltGus (via OpenClaw) faz a coordenação real.

set -euo pipefail

LOCK="/tmp/paperclip-coordinator.lock"
LOG="/root/clawd/logs/paperclip-coordinator.log"
STATE_FILE="/root/clawd/logs/paperclip-coordinator-state.json"
API_HELPER="/root/clawd/scripts/paperclip-api.sh"
API_URL="${PAPERCLIP_API_URL:-http://localhost:3100}"
COMPANY="${PAPERCLIP_COMPANY:-e2ecd7ae-85e6-4114-9035-03ab83e24d6e}"

# OpenClaw agent names to detect in Paperclip comments
OPENCLAW_AGENTS="dev-agent|marketing-agent|main|titan|luna|dr-miguel|dra-carla|dr-felipe|dr-ricardo|alexandre|dra-fernanda|dra-helena|dr-bruno|dra-juliana"

# Critical alert threshold: hours
CRITICAL_BLOCKED_HOURS=1

# ─── Lock ──────────────────────────────────────────────────────────────────

acquire_lock() {
    if [[ -f "$LOCK" ]]; then
        local pid
        pid=$(cat "$LOCK" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            echo "[$(date)] Coordinator already running (pid $pid), exiting." >> "$LOG"
            exit 0
        fi
        rm -f "$LOCK"
    fi
    echo $$ > "$LOCK"
    trap 'rm -f "$LOCK"' EXIT
}

release_lock() {
    rm -f "$LOCK"
}

# ─── Helpers ───────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# Ensure state file exists
init_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" <<EOF
{
  "lastSeenAt": null,
  "lastRun": null,
  "runs": 0,
  "alerts": {
    "criticalBlocked": {},
    "mentionDetected": {}
  }
}
EOF
    fi
}

# Read a value from state JSON
state_get() {
    local key="$1"
    jq -r ".$key // empty" "$STATE_FILE" 2>/dev/null
}

# Write a value to state JSON
state_set() {
    local key="$1"
    local value="$2"
    local tmp
    tmp=$(mktemp)
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# Increment runs counter
state_increment_runs() {
    local tmp
    tmp=$(mktemp)
    jq '.runs = (.runs // 0) + 1' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# Update lastRun timestamp
state_touch_run() {
    local now
    now=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')
    local tmp
    tmp=$(mktemp)
    jq --arg ts "$now" '.lastRun = $ts' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# ─── Checks ────────────────────────────────────────────────────────────────

check_paperclip_health() {
    local health
    health=$(curl -s --connect-timeout 5 --max-time 5 "${API_URL}/api/health" 2>&1 || echo "DOWN")

    if echo "$health" | jq -e '.status' >/dev/null 2>&1; then
        local status
        status=$(echo "$health" | jq -r '.status')
        if [[ "$status" != "ok" ]]; then
            log "❌ Paperclip health: $status"
        fi
    else
        log "❌ Paperclip unreachable"
        return 1
    fi
    return 0
}

check_agents_error() {
    local error_agents
    error_agents=$(bash "$API_HELPER" agents 2>/dev/null | grep "error" || true)

    if [[ -n "$error_agents" ]]; then
        log "⚠️  Agents in error: $error_agents"
    fi
}

check_idle_agents() {
    local idle_count active_count
    idle_count=$(bash "$API_HELPER" agents 2>/dev/null | grep -c "idle" || echo 0)
    active_count=$(bash "$API_HELPER" agents 2>/dev/null | grep -cv "idle" || echo 0)

    log "👥 Agents: $idle_count idle, $active_count active/error"
}

# ─── Comment Detection ─────────────────────────────────────────────────────

# Fetch issues updated since lastSeenAt and scan for agent mentions in comments
detect_agent_mentions() {
    local last_seen
    last_seen=$(state_get "lastSeenAt")

    # Fetch all active issues (todo, in_progress, blocked)
    local issues_json
    issues_json=$(bash "$API_HELPER" --json tasks "todo,in_progress,blocked" 2>/dev/null || echo "[]")

    if [[ "$issues_json" == "[]" || -z "$issues_json" ]]; then
        return 0
    fi

    # Filter issues updated after lastSeenAt (if set), limit to 20 to avoid heavy processing
    local recent_issues
    if [[ -n "$last_seen" && "$last_seen" != "null" ]]; then
        recent_issues=$(echo "$issues_json" | jq -r --arg since "$last_seen" \
            '[.[] | select(.updatedAt > $since)] | .[0:20]')
    else
        # First run: check all, limit to 10
        recent_issues=$(echo "$issues_json" | jq '.[0:10]')
    fi

    local count
    count=$(echo "$recent_issues" | jq 'length')
    if (( count == 0 )); then
        return 0
    fi

    local mentions_found=0

    # Iterate over each recently updated issue
    while IFS= read -r issue; do
        local issue_id issue_title
        issue_id=$(echo "$issue" | jq -r '.id')
        issue_title=$(echo "$issue" | jq -r '.title')

        # Fetch comments for this issue
        local comments
        comments=$(curl -s --connect-timeout 5 --max-time 5 \
            "${API_URL}/api/issues/${issue_id}/comments" 2>/dev/null || echo "[]")

        if [[ "$comments" == "[]" || -z "$comments" ]]; then
            continue
        fi

        # Filter comments since lastSeenAt
        local recent_comments
        if [[ -n "$last_seen" && "$last_seen" != "null" ]]; then
            recent_comments=$(echo "$comments" | jq -r --arg since "$last_seen" \
                '[.[] | select(.createdAt > $since)]')
        else
            recent_comments="$comments"
        fi

        local comment_count
        comment_count=$(echo "$recent_comments" | jq 'length')
        if (( comment_count == 0 )); then
            continue
        fi

        # Check each comment for agent mentions
        while IFS= read -r comment; do
            local body created_at author
            body=$(echo "$comment" | jq -r '.body // ""')
            created_at=$(echo "$comment" | jq -r '.createdAt // "unknown"')
            author=$(echo "$comment" | jq -r '.authorName // .agentName // "unknown"')

            if echo "$body" | grep -qiE "@?(${OPENCLAW_AGENTS})"; then
                # Extract which agents were mentioned
                local mentioned
                mentioned=$(echo "$body" | grep -oiE "@?(${OPENCLAW_AGENTS})" | sort -u | tr '\n' ',' | sed 's/,$//')

                log "🔔 AGENT MENTION DETECTED in [${issue_id:0:8}] \"${issue_title}\""
                log "   Author: $author | Mentioned: $mentioned"
                log "   Comment: $(echo "$body" | head -c 200)"

                mentions_found=$((mentions_found + 1))
            fi
        done < <(echo "$recent_comments" | jq -c '.[]')
    done < <(echo "$recent_issues" | jq -c '.[]')

    # Update lastSeenAt to now
    local now
    now=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')
    state_set "lastSeenAt" "$now"

    if (( mentions_found > 0 )); then
        log "📊 Found $mentions_found comment(s) mentioning OpenClaw agents this run"
    fi
}

# ─── Critical Blocked Alert ────────────────────────────────────────────────

alert_critical_blocked() {
    local blocked_json
    blocked_json=$(bash "$API_HELPER" --json tasks blocked 2>/dev/null || echo "[]")

    if [[ "$blocked_json" == "[]" || -z "$blocked_json" ]]; then
        return 0
    fi

    local now_epoch
    now_epoch=$(date +%s)

    # Check each blocked task
    while IFS= read -r task; do
        local task_id task_title priority updated_at
        task_id=$(echo "$task" | jq -r '.id')
        task_title=$(echo "$task" | jq -r '.title')
        priority=$(echo "$task" | jq -r '.priority // "none"')
        updated_at=$(echo "$task" | jq -r '.updatedAt // .createdAt // "unknown"')

        # Only alert on critical (or high) priority tasks
        if [[ "$priority" != "critical" && "$priority" != "high" ]]; then
            continue
        fi

        # Parse updatedAt to epoch
        if [[ "$updated_at" == "unknown" ]]; then
            continue
        fi

        local blocked_epoch
        blocked_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo 0)
        if (( blocked_epoch == 0 )); then
            continue
        fi

        local blocked_hours=$(( (now_epoch - blocked_epoch) / 3600 ))

        # Alert if blocked longer than threshold
        if (( blocked_hours >= CRITICAL_BLOCKED_HOURS )); then
            # Check if we already alerted for this task (avoid spam every 15min)
            local last_alert
            last_alert=$(jq -r --arg id "$task_id" '.alerts.criticalBlocked[$id] // "never"' "$STATE_FILE")

            local should_alert=false
            if [[ "$last_alert" == "never" ]]; then
                should_alert=true
            else
                local last_alert_epoch
                last_alert_epoch=$(date -d "$last_alert" +%s 2>/dev/null || echo 0)
                # Only re-alert every 4 hours
                if (( now_epoch - last_alert_epoch > 14400 )); then
                    should_alert=true
                fi
            fi

            if $should_alert; then
                log "🚨 CRITICAL BLOCKED: [${task_id:0:8}] \"${task_title}\" — priority=$priority, blocked for ${blocked_hours}h"

                # Update alert timestamp in state
                local now_ts
                now_ts=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')
                local tmp
                tmp=$(mktemp)
                jq --arg id "$task_id" --arg ts "$now_ts" '.alerts.criticalBlocked[$id] = $ts' \
                    "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
            fi
        fi
    done < <(echo "$blocked_json" | jq -c '.[]')
}

# ─── Main ──────────────────────────────────────────────────────────────────

acquire_lock
init_state

log "=== Coordinator v2 run #$(state_get "runs") ==="

if ! check_paperclip_health; then
    log "=== Coordinator aborted (Paperclip down) ==="
    release_lock
    exit 1
fi

check_agents_error
check_idle_agents
detect_agent_mentions
alert_critical_blocked

state_increment_runs
state_touch_run

log "=== Coordinator done ==="

release_lock
