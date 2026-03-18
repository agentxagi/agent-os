#!/bin/bash
# paperclip-api.sh — Paperclip API helper para OpenClaw agents
# Qualquer agente OpenClaw pode usar para interagir com Paperclip
#
# Uso:
#   paperclip-api.sh [--json] tasks [--status todo,in_progress,blocked] [--assignee <agent>]
#   paperclip-api.sh [--json] task <id>
#   paperclip-api.sh [--json] checkout <id> [agent-id]
#   paperclip-api.sh [--json] update <id> <status> "<comment>"
#   paperclip-api.sh [--json] comment <id> "<text>"
#   paperclip-api.sh [--json] create "<title>" "<description>" <assignee-agent-id> [project-id]
#   paperclip-api.sh [--json] subtask <parent-id> "<title>" "<description>" <assignee-agent-id>
#   paperclip-api.sh [--json] agents
#   paperclip-api.sh [--json] agent <name>
#   paperclip-api.sh [--json] projects
#   paperclip-api.sh [--json] workspaces [--project <project-id>]
#   paperclip-api.sh [--json] assign <issue-id> <agent-id>
#   paperclip-api.sh [--json] release <issue-id>
#   paperclip-api.sh [--json] costs
#   paperclip-api.sh health
#
# Flags:
#   --json   Output raw JSON instead of human-readable format
#
# Env vars:
#   PAPERCLIP_API_URL  — default: http://localhost:3100
#   PAPERCLIP_COMPANY  — default: e2ecd7ae-85e6-4114-9035-03ab83e24d6e
#   PAPERCLIP_TIMEOUT  — default: 10 (seconds for curl operations)

set -euo pipefail

API_URL="${PAPERCLIP_API_URL:-http://localhost:3100}"
COMPANY="${PAPERCLIP_COMPANY:-e2ecd7ae-85e6-4114-9035-03ab83e24d6e}"
CURL_TIMEOUT="${PAPERCLIP_TIMEOUT:-10}"

# --json flag: when set, output raw JSON instead of human-friendly text
JSON_MODE=false

# ─── Helpers ───────────────────────────────────────────────────────────────

die() { echo "❌ $*" >&2; exit 1; }
info() { echo "✅ $*"; }
warn() { echo "⚠️  $*" >&2; }

# Check if Paperclip API is reachable
health_check() {
    local http_code
    http_code=$(curl -so /dev/null -w "%{http_code}" --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" "${API_URL}/api/health" 2>/dev/null || echo "000")

    if [[ "$http_code" == "000" ]]; then
        die "Paperclip unreachable at ${API_URL} (connection refused/timeout after ${CURL_TIMEOUT}s)"
    elif [[ "$http_code" =~ ^5 ]]; then
        die "Paperclip server error (HTTP ${http_code}) at ${API_URL}"
    elif [[ "$http_code" =~ ^4 ]]; then
        # 4xx on /health is unusual but not a connectivity issue; continue
        warn "Paperclip returned HTTP ${http_code} on health check"
    fi
    return 0
}

# Safely pipe to jq, handling parse errors
safe_jq() {
    local input="$1"
    shift
    local result
    result=$(echo "$input" | jq "$@" 2>&1) && echo "$result" || {
        local jq_exit=$?
        # Check if the input itself was bad JSON
        if echo "$input" | jq '.' >/dev/null 2>&1; then
            # JSON was valid, jq expression failed
            warn "jq filter error: ${result}"
            return $jq_exit
        else
            # Input was not valid JSON — likely an HTML error page or empty response
            warn "Invalid JSON response from API. Raw output (first 200 chars):"
            echo "${input:0:200}" >&2
            die "Failed to parse API response as JSON"
        fi
    }
}

# Parse first arg for --json flag
parse_flags() {
    if [[ "${1:-}" == "--json" ]]; then
        JSON_MODE=true
        shift
    fi
}

api_get() {
    local path="$1"
    curl -s --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" "${API_URL}${path}" 2>&1
}

api_post() {
    local path="$1"
    local body="$2"
    curl -s -X POST --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" "${API_URL}${path}" \
        -H "Content-Type: application/json" \
        -d "$body" 2>&1
}

api_patch() {
    local path="$1"
    local body="$2"
    curl -s -X PATCH --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" "${API_URL}${path}" \
        -H "Content-Type: application/json" \
        -d "$body" 2>&1
}

# ─── Commands ──────────────────────────────────────────────────────────────

cmd_health() {
    local result
    result=$(curl -s --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" "${API_URL}/api/health" 2>&1)
    local http_code=$?

    if [[ -z "$result" || "$result" == *"Connection refused"* || "$result" == *"curl"* ]]; then
        if $JSON_MODE; then
            echo '{"status":"unreachable","url":"'"${API_URL}"'"}'
        else
            die "Paperclip unreachable at ${API_URL}"
        fi
    fi

    # Validate it's actually JSON
    if ! echo "$result" | jq '.' >/dev/null 2>&1; then
        if $JSON_MODE; then
            echo '{"status":"error","message":"Invalid JSON from health endpoint","raw":"'"${result:0:100}"'"}'
        else
            die "Health endpoint returned invalid response: ${result:0:100}"
        fi
    fi

    if $JSON_MODE; then
        echo "$result" | jq '. + {"url":"'"${API_URL}"'","status":"ok"}'
    else
        echo "$result" | jq -r '"Paperclip is healthy (status: \(.status // "unknown"))"' 2>/dev/null || echo "$result"
    fi
}

cmd_tasks() {
    local status="${1:-todo,in_progress,blocked}"
    local assignee="${2:-}"
    local project="${3:-}"
    
    local url="/api/companies/${COMPANY}/issues?status=${status}&limit=50"
    [[ -n "$assignee" ]] && url+="&assigneeAgentId=${assignee}"
    [[ -n "$project" ]] && url+="&projectId=${project}"
    
    local raw
    raw=$(api_get "$url")

    if $JSON_MODE; then
        safe_jq "$raw" '.'
    else
        safe_jq "$raw" -r '.[] | "[\(.identifier)] \(.title) — \(.status) (\(.priority // "none"))"'
    fi
}

cmd_task() {
    local id="${1:?Task ID required}"
    local raw
    raw=$(api_get "/api/issues/${id}")

    if $JSON_MODE; then
        safe_jq "$raw" '.'
    else
        safe_jq "$raw" '.'
    fi
}

cmd_checkout() {
    local id="${1:?Issue ID required}"
    local agent_id="${2:-}"
    
    if [[ -z "$agent_id" ]]; then
        warn "No agent ID specified. Checking out as system."
    fi
    
    local body='{}'
    [[ -n "$agent_id" ]] && body="{\"agentId\":\"${agent_id}\"}"
    
    local result
    result=$(api_post "/api/issues/${id}/checkout" "$body")
    
    if echo "$result" | jq -e '.error' >/dev/null 2>&1; then
        echo "$result" | jq -r '.error' | die
    else
        if $JSON_MODE; then
            echo "$result" | safe_jq /dev/stdin '.'
        else
            info "Checked out issue ${id}"
            echo "$result" | jq '{identifier, title, status}' 2>/dev/null
        fi
    fi
}

cmd_update() {
    local id="${1:?Issue ID required}"
    local status="${2:?Status required}"
    local comment="${3:-}"
    
    local body="{\"status\":\"${status}\"}"
    [[ -n "$comment" ]] && body=$(echo "$body" | jq --arg c "$comment" '. + {comment: $c}')
    
    local result
    result=$(api_patch "/api/issues/${id}" "$body")
    
    if echo "$result" | jq -e '.error' >/dev/null 2>&1; then
        echo "$result" | jq -r '.error' | die
    else
        if $JSON_MODE; then
            echo "$result" | safe_jq /dev/stdin '.'
        else
            info "Updated ${id} → ${status}"
            echo "$result" | jq '{identifier, title, status}' 2>/dev/null
        fi
    fi
}

cmd_comment() {
    local id="${1:?Issue ID required}"
    local text="${2:?Comment text required}"
    
    local result
    result=$(api_post "/api/issues/${id}/comments" "{\"body\":\"${text}\"}")
    
    if echo "$result" | jq -e '.error' >/dev/null 2>&1; then
        echo "$result" | jq -r '.error' | die
    else
        if $JSON_MODE; then
            echo "$result" | safe_jq /dev/stdin '.'
        else
            info "Commented on ${id}"
        fi
    fi
}

cmd_create() {
    local title="${1:?Title required}"
    local desc="${2:-}"
    local assignee="${3:-}"
    local project="${4:-}"
    
    local body="{\"title\":\"${title}\""
    [[ -n "$desc" ]] && body+=",\"description\":\"${desc}\""
    [[ -n "$assignee" ]] && body+=",\"assigneeAgentId\":\"${assignee}\""
    [[ -n "$project" ]] && body+=",\"projectId\":\"${project}\""
    body+="}"
    
    local result
    result=$(api_post "/api/companies/${COMPANY}/issues" "$body")
    
    if echo "$result" | jq -e '.error' >/dev/null 2>&1; then
        echo "$result" | jq -r '.error' | die
    else
        if $JSON_MODE; then
            echo "$result" | safe_jq /dev/stdin '.'
        else
            info "Created task"
            echo "$result" | jq '{identifier, title, status, assigneeAgentId}' 2>/dev/null
        fi
    fi
}

cmd_subtask() {
    local parent_id="${1:?Parent issue ID required}"
    local title="${2:?Title required}"
    local desc="${3:-}"
    local assignee="${4:-}"
    
    local body="{\"title\":\"${title}\""
    [[ -n "$desc" ]] && body+=",\"description\":\"${desc}\""
    [[ -n "$assignee" ]] && body+=",\"assigneeAgentId\":\"${assignee}\""
    body+=",\"parentId\":\"${parent_id}\""
    body+="}"
    
    local result
    result=$(api_post "/api/companies/${COMPANY}/issues" "$body")
    
    if echo "$result" | jq -e '.error' >/dev/null 2>&1; then
        echo "$result" | jq -r '.error' | die
    else
        if $JSON_MODE; then
            echo "$result" | safe_jq /dev/stdin '.'
        else
            info "Created subtask"
            echo "$result" | jq '{identifier, title, parentId, assigneeAgentId}' 2>/dev/null
        fi
    fi
}

cmd_agents() {
    local raw
    raw=$(api_get "/api/companies/${COMPANY}/agents")

    if $JSON_MODE; then
        safe_jq "$raw" '.'
    else
        safe_jq "$raw" -r '.[] | "[\(.role)] \(.name) — \(.status)"'
    fi
}

cmd_agent() {
    local name="${1:?Agent name required}"
    local raw
    raw=$(api_get "/api/companies/${COMPANY}/agents")

    if $JSON_MODE; then
        safe_jq "$raw" ".[] | select(.name == \"${name}\")"
    else
        safe_jq "$raw" ".[] | select(.name == \"${name}\")"
    fi
}

cmd_projects() {
    local raw
    raw=$(api_get "/api/companies/${COMPANY}/projects")

    if $JSON_MODE; then
        safe_jq "$raw" '.'
    else
        safe_jq "$raw" -r '.[] | "[\(.status)] \(.name) (id: \(.id))"'
    fi
}

cmd_workspaces() {
    local project_id="${1:-}"
    local url="/api/companies/${COMPANY}/execution-workspaces"
    [[ -n "$project_id" ]] && url+="?projectId=${project_id}"

    local raw
    raw=$(api_get "$url")

    if $JSON_MODE; then
        safe_jq "$raw" '.'
    else
        safe_jq "$raw" '.'
    fi
}

cmd_assign() {
    local issue_id="${1:?Issue ID required}"
    local agent_id="${2:?Agent ID required}"
    local result
    result=$(cmd_update "$issue_id" "todo" "Assigned to agent ${agent_id}")
    local patch_result
    patch_result=$(api_patch "/api/issues/${issue_id}" "{\"assigneeAgentId\":\"${agent_id}\"}")

    if $JSON_MODE; then
        echo "$patch_result" | safe_jq /dev/stdin '.'
    else
        echo "$patch_result" | jq '{identifier, title, assigneeAgentId}' 2>/dev/null
    fi
}

cmd_release() {
    local issue_id="${1:?Issue ID required}"
    local result
    result=$(api_post "/api/issues/${issue_id}/release" '{}')

    if $JSON_MODE; then
        echo "$result" | safe_jq /dev/stdin '.'
    else
        info "Released issue ${issue_id}"
        echo "$result" | jq '{identifier, title, status}' 2>/dev/null
    fi
}

cmd_costs() {
    local raw_dashboard raw_agents

    raw_dashboard=$(api_get "/api/companies/${COMPANY}/dashboard")
    raw_agents=$(api_get "/api/companies/${COMPANY}/agents")

    if $JSON_MODE; then
        # Output combined JSON
        echo "{\"costs\":$(safe_jq "$raw_dashboard" '.costs // .spending // "No cost data available"' 2>/dev/null || echo 'null'),\"agents\":$raw_agents}" | jq '.'
    else
        safe_jq "$raw_dashboard" '.costs // .spending // "No cost data available"' 2>/dev/null
        echo "---"
        safe_jq "$raw_agents" -r '.[] | "\(.name): spent=\(.spentMonthlyCents // 0)¢ budget=\(.budgetMonthlyCents // 0)¢"' 2>/dev/null
    fi
}

# ─── Agent name → ID resolver ──────────────────────────────────────────────

resolve_agent_id() {
    local name="$1"
    local raw
    raw=$(api_get "/api/companies/${COMPANY}/agents")
    safe_jq "$raw" -r ".[] | select(.name == \"${name}\") | .id" | head -1
}

# ─── Main ──────────────────────────────────────────────────────────────────

# Parse --json flag (must be before command)
if [[ "${1:-}" == "--json" ]]; then
    JSON_MODE=true
    shift
fi

# Run health check for all commands except 'health' and 'help'
if [[ "${1:-help}" != "health" && "${1:-help}" != "help" ]]; then
    health_check
fi

case "${1:-help}" in
    health)     shift; cmd_health "$@" ;;
    tasks)      shift; cmd_tasks "$@" ;;
    task)       shift; cmd_task "$@" ;;
    checkout)   shift; cmd_checkout "$@" ;;
    update)     shift; cmd_update "$@" ;;
    comment)    shift; cmd_comment "$@" ;;
    create)     shift; cmd_create "$@" ;;
    subtask)    shift; cmd_subtask "$@" ;;
    agents)     shift; cmd_agents "$@" ;;
    agent)      shift; cmd_agent "$@" ;;
    projects)   shift; cmd_projects "$@" ;;
    workspaces) shift; cmd_workspaces "$@" ;;
    assign)     shift; cmd_assign "$@" ;;
    release)    shift; cmd_release "$@" ;;
    costs)      shift; cmd_costs "$@" ;;
    resolve)    shift; resolve_agent_id "$@" ;;
    help|*)
        echo "Paperclip API Helper v1.1"
        echo ""
        echo "Usage: paperclip-api.sh [--json] <command> [args...]"
        echo ""
        echo "Flags:"
        echo "  --json   Output raw JSON (machine-readable)"
        echo ""
        echo "Commands:"
        echo "  health                                     Check API reachability"
        echo "  tasks [status] [assignee-id] [project-id]  List tasks"
        echo "  task <id>                                 Get task details"
        echo "  checkout <id> [agent-id]                   Checkout (lock) a task"
        echo "  update <id> <status> [comment]             Update task status"
        echo "  comment <id> <text>                        Add comment"
        echo "  create <title> [desc] [assignee] [project] Create task"
        echo "  subtask <parent-id> <title> [desc] [assignee] Create subtask"
        echo "  agents                                     List agents"
        echo "  agent <name>                               Get agent details"
        echo "  projects                                   List projects"
        echo "  workspaces [project-id]                    List workspaces"
        echo "  assign <issue-id> <agent-id>               Assign task to agent"
        echo "  release <issue-id>                         Release task"
        echo "  costs                                      View costs/budget"
        echo "  resolve <name>                             Resolve agent name → ID"
        echo ""
        echo "Env vars:"
        echo "  PAPERCLIP_API_URL   (default: http://localhost:3100)"
        echo "  PAPERCLIP_COMPANY   (default: e2ecd7ae-...)"
        echo "  PAPERCLIP_TIMEOUT   (default: 10 seconds)"
        ;;
esac
