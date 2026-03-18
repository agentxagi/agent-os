#!/bin/bash
# sprint-creator.sh — Automatically creates sprint tasks for @agentxagi Growth
# Called by cron at scheduled times (8h, 12h, 16h, 20h BRT)
#
# Sprint types based on time of day:
# - 08:00: Morning Research Sprint
# - 12:00: Midday Engagement Sprint  
# - 16:00: Afternoon Content Sprint
# - 20:00: Evening Analytics Sprint

set -euo pipefail

LOCK="/tmp/sprint-creator.lock"
LOG="/root/clawd/logs/sprint-creator.log"
API="/root/clawd/scripts/paperclip-api.sh"
STATE="/root/clawd/logs/sprint-creator-state.json"
COMPANY_ID="e2ecd7ae-85e6-4114-9035-03ab83e24d6e"
PROJECT_ID="289b243b-f6de-4d29-87f0-bc1a8d636b16"

# Agent IDs
BA_ID="f8928dbe-8ed5-4a9e-be28-c25c66a00d06"    # Business Analyst
CTO_ID="bea6e4c0-cbf8-4d81-8a6f-b7dc76ee918b"   # CTO
PM_ID="5cdee2de-2e8b-492d-925d-a6f1f818c089"     # Product Manager
DE_ID="e9888012-3203-43ad-8e4c-3d4b4c0dde36"     # Data Engineer
DESIGNER_ID="6b4b11b6-d13e-414d-9d8c-b781769fd844" # Designer

# Lock
if [[ -f "$LOCK" ]]; then
    pid=$(cat "$LOCK" 2>/dev/null)
    if kill -0 "$pid" 2>/dev/null; then
        echo "[$(date)] Already running (PID $pid)" >> "$LOG"
        exit 0
    fi
    rm -f "$LOCK"
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# Health check
bash "$API" health > /dev/null 2>&1 || {
    echo "[$(date)] Paperclip unreachable, aborting." >> "$LOG"
    exit 1
}

# Determine sprint type based on hour
HOUR=$(date +%H)
case $HOUR in
    08) SPRINT="Morning Research"; TYPE="research" ;;
    12) SPRINT="Midday Engagement"; TYPE="engagement" ;;
    16) SPRINT="Afternoon Content"; TYPE="content" ;;
    20) SPRINT="Evening Analytics"; TYPE="analytics" ;;
    *)  echo "[$(date)] No sprint scheduled for hour $HOUR" >> "$LOG"; exit 0 ;;
esac

DATE=$(date +%Y-%m-%d)
SPRINT_NAME="${DATE} ${SPRINT}"

# Load state
if [[ -f "$STATE" ]]; then
    LAST=$(jq -r '.lastSprint // ""' "$STATE" 2>/dev/null)
    if [[ "$LAST" == "$SPRINT_NAME" ]]; then
        echo "[$(date)] Sprint '${SPRINT_NAME}' already created." >> "$LOG"
        exit 0
    fi
else
    echo '{}' > "$STATE"
fi

# Check circuit breaker state
CB_STATE="CLOSED"
if [[ -f "$STATE" ]]; then
    CB_STATE=$(jq -r '.circuitBreakers.content.state // "CLOSED"' "$STATE" 2>/dev/null)
fi

if [[ "$CB_STATE" == "OPEN" ]]; then
    echo "[$(date)] Circuit breaker OPEN — skipping sprint creation." >> "$LOG"
    exit 0
fi

echo "[$(date)] Creating sprint: ${SPRINT_NAME}" >> "$LOG"

# Check for existing open tasks (don't spam if team is busy)
OPEN_TASKS=$(curl -s "http://localhost:3100/api/companies/${COMPANY_ID}/issues?status=todo,in_progress&limit=50" 2>&1 | jq '[.[] | select(.projectId == "'"$PROJECT_ID"'")] | length' 2>/dev/null)
if [[ "$OPEN_TASKS" -gt 5 ]]; then
    echo "[$(date)] ${OPEN_TASKS} open tasks — skipping sprint (team busy)." >> "$LOG"
    exit 0
fi

create_task() {
    local title="$1" desc="$2" priority="$3" assignee="$4" parent="$5"

    local payload=$(jq -n \
        --arg title "$title" \
        --arg desc "$desc" \
        --arg priority "$priority" \
        --arg project "$PROJECT_ID" \
        --arg assignee "$assignee" \
        '{
            title: $title,
            description: $desc,
            priority: $priority,
            projectId: $project,
            assigneeAgentId: $assignee
        }')

    if [[ -n "$parent" ]]; then
        payload=$(echo "$payload" | jq --arg parent "$parent" '. + {parentId: $parent}')
    fi

    local result=$(curl -s -X POST "http://localhost:3100/api/companies/${COMPANY_ID}/issues" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1)

    local id=$(echo "$result" | jq -r '.id')
    local identifier=$(echo "$result" | jq -r '.identifier')

    # Move to todo
    curl -s -X PATCH "http://localhost:3100/api/issues/${id}" \
        -H "Content-Type: application/json" \
        -d '{"status":"todo"}' > /dev/null 2>&1

    echo "${identifier}|${id}"
}

# Blacklist
BLACKLIST="boycott, concert, crypto, trading, paramount, elon musk, muslim, fasting, midjourney, warner"
BLACKLIST_NOTE="Blacklist: ${BLACKLIST}. English ONLY."

TASK_IDS=()

case $TYPE in
    research)
        # Task 1: Trend research (Business Analyst)
        T1=$(create_task \
            "Research Sprint — Find top 5 trending AI/agent topics" \
            "Search Twitter for trending AI/agent topics. Find 5 topics with active discussion (50+ likes threads).\n\nFor each topic: the angle @agentxagi should take, key voices involved, estimated engagement potential.\n\nUse: twitter search queries\n\nOutput: /root/clawd/content-engine/data/trends/${DATE}-sprint.md\n\nPriority topics: AI agents, coding agents, agent orchestration, Claude Code, OpenClaw, tool use, AI productivity, MCP, LLM benchmarks\n\n${BLACKLIST_NOTE}" \
            "high" "$BA_ID" "")
        TASK_IDS+=("$T1")

        # Task 2: Create content based on research (CTO, depends on research)
        T2=$(create_task \
            "Create 2 threads based on sprint research" \
            "After Business Analyst completes trend research, write 2 threads (5-8 tweets each).\n\nThread format:\n1/n [HOOK — Bold claim or contrarian take]\n2/n [CONTEXT — Why this matters now]\n3/n [INSIGHT — The key learning]\n4/n [EXAMPLE — Real scenario]\n5/n [PREDICTION — Where this is going]\n6/n [TAKEAWAY — One actionable thing]\n\nOutput: /root/clawd/content-engine/data/threads/${DATE}-sprint-thread-1.md and thread-2.md\n\nDO NOT POST — Designer will review.\n\n${BLACKLIST_NOTE}" \
            "high" "$CTO_ID" "$(echo "$T1" | cut -d'|' -f2)")
        TASK_IDS+=("$T2")

        # Task 3: Engagement (PM, independent)
        .*engagement.*$
            "Find and reply to 15 AI/agent discussions on Twitter.\n\nTarget: 5K-100K followers, active (last 24h), discussing AI agents/LLMs/coding tools.\n\nReply quality:\n- Add genuine insight or share experience\n- Reference specific points from original tweet\n- NEVER generic 'Great thread!'\n- NO self-promotion, NO links\n\nLog: /root/clawd/content-engine/data/engagement/${DATE}-replies.md\n\n${BLACKLIST_NOTE}" \
            "high" "$PM_ID" "")
        TASK_IDS+=("$T3")

        # Task 4: Post approved content (Designer, depends on CTO)
        T4=$(create_task \
            "Review and post approved threads" \
            "After CTO creates threads, review for quality:\n\nChecklist:\n- English only\n- Technical but accessible\n- Specific numbers/examples\n- Opinionated (has a real take)\n- No blacklisted topics\n- Each tweet < 280 chars\n\nIf quality passes: Post using twitter post, one tweet at a time, 10-15s between tweets.\nIf quality fails: Comment on CTO task with feedback.\n\nLog: /root/clawd/content-engine/data/engagement/${DATE}-posts.md\n\n${BLACKLIST_NOTE}" \
            "high" "$DESIGNER_ID" "$(echo "$T2" | cut -d'|' -f2)")
        TASK_IDS+=("$T4")
        ;;

    engagement)
        # Heavy engagement sprint
        T1=$(create_task \
            "Engagement sprint — Reply to 25 relevant discussions" \
            "Heavy engagement sprint. Find and reply to 25 AI/agent discussions.\n\nTargets:\n- 10 replies to large accounts (10K+ followers) — add value to their threads\n- 10 replies to mid-size accounts (1K-10K) — build relationships\n- 5 replies to small accounts (<1K) — community building\n\nLog: /root/clawd/content-engine/data/engagement/${DATE}-engagement-sprint.md\n\n${BLACKLIST_NOTE}" \
            "high" "$PM_ID" "")
        TASK_IDS+=("$T1")

        T2=$(create_task \
            "Strategic follows — Follow 20 relevant AI accounts" \
            "Find and follow 20 accounts that:\n- Post about AI agents, LLMs, coding tools\n- Active (posted in last 7 days)\n- 1K+ followers\n- NOT: bots, crypto, engagement farmers\n\nUse: twitter user USERNAME, then twitter follow USERNAME\n\nDO NOT unfollow anyone. Follow only.\n\n${BLACKLIST_NOTE}" \
            "medium" "$BA_ID" "")
        TASK_IDS+=("$T2")
        ;;

    content)
        # Content creation sprint
        T1=$(create_task \
            "Content Sprint — Create 1 standalone hot take tweet" \
            "Write 1 standalone hot take tweet (NOT a thread) about AI agents/LLMs.\n\nRules:\n- Max 280 chars\n- Bold, opinionated take\n- Include a specific number or data point\n- English only\n- No blacklisted topics\n\nOutput: /root/clawd/content-engine/data/threads/${DATE}-hot-take.md\n\n${BLACKLIST_NOTE}" \
            "medium" "$CTO_ID" "")
        TASK_IDS+=("$T1")

        T2=$(create_task \
            "Content Sprint — Create 1 thread (6-8 tweets)" \
            "Write 1 thread (6-8 tweets) about AI agents/LLMs.\n\nStructure: Hook → Context → Insight → Example → Prediction → Takeaway\n\nOutput: /root/clawd/content-engine/data/threads/${DATE}-thread.md\n\nDO NOT POST.\n\n${BLACKLIST_NOTE}" \
            "high" "$CTO_ID" "")
        TASK_IDS+=("$T2")

        .*engagement.*$
            "Review and post content" \
            "Review content from CTO tasks and post if quality passes.\n\nChecklist: English, <280 chars, opinionated, no blacklisted topics.\n\nPost using: twitter post (one tweet at a time, 10-15s between).\n\nLog: /root/clawd/content-engine/data/engagement/${DATE}-posts.md" \
            "high" "$DESIGNER_ID" "$(echo "$T2" | cut -d'|' -f2)")
        TASK_IDS+=("$T3")

        T4=$(create_task \
            "Reply to 10 relevant AI/agent discussions.\n\nLog: /root/clawd/content-engine/data/engagement/${DATE}-replies.md\n\n${BLACKLIST_NOTE}" \
            "medium" "$PM_ID" "")
        TASK_IDS+=("$T4")
        ;;

    analytics)
        # Analytics sprint
        T1=$(create_task \
            "Daily metrics snapshot and report" \
            "Collect @agentxagi metrics and create a report.\n\nData: twitter user agentxagi, twitter user-posts agentxagi --max 40\n\nOutput:\n1. Raw: /root/clawd/content-engine/data/metrics/${DATE}.json\n2. Report: /root/clawd/content-engine/data/reports/DAILY-${DATE}.md\n\nReport must include:\n- Follower/following ratio\n- Posts today with engagement\n- Avg views per post\n- Best/worst content\n- Recommendations\n\nUse REAL data only." \
            "medium" "$DE_ID" "")
        TASK_IDS+=("$T1")

        T2=$(create_task \
            "Update circuit breaker state based on metrics" \
            "After Data Engineer completes metrics, analyze and update circuit breaker state.\n\nRead: /root/clawd/content-engine/data/metrics/${DATE}.json\n\nUpdate: /root/clawd/logs/sprint-creator-state.json\n\nCircuit breaker rules:\n- Content: CLOSED (8-10 posts/day) → HALF_OPEN (3-5) → OPEN (stop) based on avg views\n  - CLOSED → HALF_OPEN: avg views < 50 for 3 consecutive posts\n  - HALF_OPEN → OPEN: avg views < 20 for 5 consecutive posts\n  - HALF_OPEN → CLOSED: avg views > 100 for 3 consecutive posts\n  - OPEN → HALF_OPEN: cooldown 2h\n\n- Engagement: CLOSED (15-20 replies) → HALF_OPEN (5-10) → OPEN (stop)\n  - CLOSED → HALF_OPEN: 0 likes on last 10 replies\n  - HALF_OPEN → OPEN: rate limited or shadowbanned\n  - HALF_OPEN → CLOSED: getting engagement\n  - OPEN → HALF_OPEN: cooldown 4h\n\n- Following: CLOSED (50/h) → HALF_OPEN (10/h) → OPEN (stop)\n  - CLOSED → HALF_OPEN: ratio < 1.5\n  - HALF_OPEN → OPEN: ratio < 1.2 OR 429\n  - HALF_OPEN → CLOSED: ratio > 2.0\n  - OPEN → HALF_OPEN: cooldown 6h\n\nUpdate the JSON file with new states." \
            "medium" "$BA_ID" "$(echo "$T1" | cut -d'|' -f2)")
        TASK_IDS+=("$T2")
        ;;
esac

# Update state
TASK_IDENTIFIERS=$(for t in "${TASK_IDS[@]}"; do echo "$t" | cut -d'|' -f1; done | tr '\n' ', ')
jq -n --arg sprint "$SPRINT_NAME" --arg tasks "$TASK_IDENTIFIERS" --arg date "$(date -Iseconds)" \
    '{lastSprint: $sprint, lastRun: $date, tasks: $tasks}' > "$STATE"

echo "[$(date)] Sprint '${SPRINT_NAME}' created with ${#TASK_IDS[@]} tasks: ${TASK_IDENTIFIERS%,}" >> "$LOG"
