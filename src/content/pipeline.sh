#!/bin/bash
# Content Engine Pipeline v2.1
# trending → hooks → article → publish
# Runs under cron, fully autonomous.
set -uo pipefail

# ═══════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════
ENGINE_DIR="/root/clawd/content-engine"
DATA_DIR="$ENGINE_DIR/data"
LOG_FILE="/root/clawd/logs/content-engine-cron.log"
LOCK_FILE="/tmp/content-engine-pipeline.lock"
MAX_RETRIES=3
RETRY_DELAY=15
TWITTER_ACCOUNT="@agentxagi"
LLM_CMD="gemini -p"  # Gemini CLI for content generation

# Search queries rotated per run (AI/agents focused)
QUERIES=(
  'AI agent OR LLM agent OR autonomous agent -boycott -concert'
  'launch OR release OR announce AI agent platform'
  'OpenClaw OR Claude Code OR Codex OR Cursor AI'
  'NVIDIA OR Anthropic OR Google AI agent'
  'build AI agent OR deploy AI agent startup'
  'AI automation workflow OR AI productivity solo'
  'AI startup funding OR AI tools 2026'
)

# Topic blacklist (avoid non-AI noise)
BLACKLIST_PATTERN='boycott|concert|crypto|trading|paramount|elon musk|muslim|fasting|midjourney|warner'

mkdir -p "$DATA_DIR" "$(dirname "$LOG_FILE")"

# ═══════════════════════════════════════════════════════════
# LOGGING
# ═══════════════════════════════════════════════════════════
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$$] $*" | tee -a "$LOG_FILE"; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$$] ERROR: $*" | tee -a "$LOG_FILE" >&2; }
die()  { err "$@"; cleanup 1; }

cleanup() {
  rm -f "$LOCK_FILE" "${TMP_FILES[@]}" 2>/dev/null
  exit "${1:-0}"
}

TMP_FILES=()

make_tmp() {
  local f
  f=$(mktemp)
  TMP_FILES+=("$f")
  echo "$f"
}

# ═══════════════════════════════════════════════════════════
# LOCK / CIRCUIT BREAKER
# ═══════════════════════════════════════════════════════════
acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local pid
    pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      die "Another pipeline instance (PID $pid) is running. Aborting."
    fi
    log "Stale lock from PID $pid. Removing."
    rm -f "$LOCK_FILE"
  fi
  echo $$ > "$LOCK_FILE"
  trap cleanup EXIT INT TERM
}

circuit_check() {
  local last_line
  last_line=$(grep "PIPELINE COMPLETE" "$LOG_FILE" 2>/dev/null | tail -1)
  if [[ -n "$last_line" ]]; then
    local last_ts
    last_ts=$(echo "$last_line" | grep -oP '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' | head -1)
    if [[ -n "$last_ts" ]]; then
      local last_epoch now_epoch diff_h
      last_epoch=$(date -d "$last_ts" +%s 2>/dev/null || echo 0)
      now_epoch=$(date +%s)
      diff_h=$(( (now_epoch - last_epoch) / 3600 ))
      if (( diff_h < 2 )); then
        log "Circuit breaker: last success ${diff_h}h ago (< 2h). Skipping."
        exit 0
      fi
    fi
  fi
}

# ═══════════════════════════════════════════════════════════
# RETRY WRAPPER
# ═══════════════════════════════════════════════════════════
retry() {
  local name="$1"; shift
  local attempt=0
  while (( attempt <= MAX_RETRIES )); do
    log "[$name] attempt $((attempt+1))/$((MAX_RETRIES+1))..."
    if "$@"; then
      return 0
    fi
    attempt=$((attempt+1))
    if (( attempt <= MAX_RETRIES )); then
      log "[$name] failed, retrying in ${RETRY_DELAY}s..."
      sleep "$RETRY_DELAY"
    fi
  done
  err "[$name] exhausted attempts."
  return 1
}

# ═══════════════════════════════════════════════════════════
# LLM HELPER
# ═══════════════════════════════════════════════════════════
# Sanitize text: remove emojis and special Unicode that breaks gemini CLI
sanitize() {
  python3 -c "
import sys, re
text = sys.stdin.read()
# Remove @ mentions (they break gemini CLI) - replace with AT_MENTION
text = re.sub(r'@[a-zA-Z0-9_]+', 'AT_MENTION', text)
# Remove emoji ranges and zero-width characters
emoji_pattern = re.compile(
    '[\U0001F300-\U0001F9FF\U0001FA00-\U0001FA6F\U0001FA70-\U0001FAFF'
    '\U00002600-\U000026FF\U00002700-\U000027BF\U0000FE00-\U0000FE0F'
    '\U0000200D\U000020E3\U0001F000-\U0001F02F\U0001F0A0-\U0001F0FF'
    '\U0001F100-\U0001F64F\U0001F680-\U0001F6FF\U00002300-\U000023FF'
    '\U000025A0-\U000025FF\U00002640-\U0000267F\U0001F900-\U0001F9FF'
    '\U00002702-\U000027B0\U0001F980-\U0001F9EF]+'
)
print(emoji_pattern.sub('', text), end='')
"
}

# Sanitize variable (use: var=$(sanitize_var "$var"))
sanitize_var() {
  printf '%s' "$1" | sanitize
}

call_llm() {
  local prompt="$1"
  # Run gemini directly, capture stdout
  $LLM_CMD "$prompt" 2>&1
}

# ═══════════════════════════════════════════════════════════
# STEP 1: SCAN TRENDS
# ═══════════════════════════════════════════════════════════
step1_scan_trends() {
  log "═══ STEP 1: SCANNING TRENDS ═══"

  # Rotate query based on time
  local idx
  idx=$(( ($(date +%j) * 3 + $(date +%H) / 6) % ${#QUERIES[@]} ))
  local query="${QUERIES[$idx]}"
  log "Query #$idx: $query"

  local tmp_search
  tmp_search=$(make_tmp)

  if ! twitter search "$query" --max 20 --json -o "$tmp_search" 2>/dev/null; then
    err "twitter search failed"
    return 1
  fi

  # Analyze with python — filter, score, select
  python3 << PYEOF
import json, datetime, re, sys

with open("$tmp_search") as f:
    raw = json.load(f)

items = raw if isinstance(raw, list) else raw.get("data", raw.get("tweets", []))

if not items:
    print("NO_RESULTS", file=sys.stderr)
    sys.exit(1)

blacklist = re.compile(r'$BLACKLIST_PATTERN', re.IGNORECASE)
trends = []

for i, t in enumerate(items[:20]):
    text = t.get("text", t.get("full_text", ""))
    metrics = t.get("metrics", t.get("engagement", {}))

    # Extract metrics from flat or nested structure
    likes    = int(metrics.get("likes", t.get("likeCount", 0)) or 0)
    rts      = int(metrics.get("retweets", t.get("retweetCount", 0)) or 0)
    views    = max(int(metrics.get("views", t.get("viewCount", 0)) or 1), 1)
    bkms     = int(metrics.get("bookmarks", t.get("bookmarkCount", 0)) or 0)
    replies  = int(metrics.get("replies", t.get("replyCount", 0)) or 0)

    # Skip blacklisted topics
    if blacklist.search(text):
        continue

    # Skip low-engagement tweets
    if likes + rts + bkms < 5:
        continue

    heat = (bkms * 3) + (rts * 2) + likes
    norm = min((heat / views * 10000), 100)

    author = t.get("user", {}).get("screenName", t.get("author", {}).get("username", "unknown"))
    tid = str(t.get("id", t.get("id_str", i)))

    trends.append({
        "id": f"trend-{i+1:03d}",
        "topic": text[:120].strip(),
        "signal": f"tweet by @{author}",
        "heat": round(norm, 1),
        "engagement": {"likes": likes, "retweets": rts, "views": views, "bookmarks": bkms},
        "keyTweets": [tid],
        "context": text[:500].strip(),
        "keywords": [w for w in text.split()[:10] if len(w) > 3][:6],
        "angle": "",
        "selected": False
    })

if not trends:
    print("NO_VALID_TRENDS", file=sys.stderr)
    sys.exit(1)

trends.sort(key=lambda x: x["heat"], reverse=True)
trends[0]["selected"] = True

output = {
    "lastScan": datetime.datetime.now().isoformat(),
    "source": "twitter",
    "trends": trends[:5],
    "selectedTrend": trends[0]["id"]
}

with open("$DATA_DIR/trends.json", "w") as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

print(f"OK: {len(trends)} trends. Top: {trends[0]['topic'][:60]}... (heat={trends[0]['heat']})")
PYEOF
}

# ═══════════════════════════════════════════════════════════
# STEP 2: GENERATE HOOKS (via Gemini)
# ═══════════════════════════════════════════════════════════
step2_generate_hooks() {
  log "═══ STEP 2: GENERATING HOOKS ═══"

  local trend_json selected_topic selected_context trend_id
  trend_json=$(cat "$DATA_DIR/trends.json")

  selected_topic=$(python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d['trends']:
    if t.get('selected'):
        print(t['topic'][:200])
        break
" <<< "$trend_json")

  selected_context=$(python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d['trends']:
    if t.get('selected'):
        print(t['context'][:500])
        break
" <<< "$trend_json")

  trend_id=$(python3 -c "
import json, sys
print(json.load(sys.stdin)['selectedTrend'])
" <<< "$trend_json")

  # Sanitize: remove emojis that break gemini CLI
  selected_topic=$(sanitize_var "$selected_topic")
  selected_context=$(sanitize_var "$selected_context")

  log "Generating hooks for: ${selected_topic:0:80}..."

  # Write prompt to file (handles multiline safely)
  local prompt_file
  prompt_file=$(make_tmp)
  cat > "$prompt_file" << PROMPT
You are a viral Twitter/X content writer for @agentxagi, an AI agent growth account.

TREND TOPIC: ${selected_topic}

CONTEXT: ${selected_context}

TASK: Generate exactly 3 viral hooks for a Twitter thread about this trend.

RULES:
- Each hook MUST be under 280 characters
- Use specific details from the context (names, numbers)
- No filler words (great, amazing, exciting)
- Create curiosity gap
- Write in English

HOOK FORMULAS (use one per hook):
1. Contrarian - challenge common belief
2. Authority/signal - big player did X
3. Hidden detail - what nobody noticed

OUTPUT ONLY VALID JSON, NOTHING ELSE:
{"hooks":[{"text":"hook 1","formula":"contrarian","score":8},{"text":"hook 2","formula":"authority","score":9},{"text":"hook 3","formula":"hidden","score":7}],"selected":1}

"selected" is 0-based index of the best hook.
PROMPT

  local llm_output
  llm_output=$(gemini -p "$(cat "$prompt_file")" 2>&1)

  # Remove the "Loaded cached credentials" line
  llm_output=$(echo "$llm_output" | sed '/^Loaded cached credentials$/d')

  if [[ -z "$llm_output" ]]; then
    err "Empty LLM output for hooks"
    return 1
  fi

  # Parse and validate
  local parse_result
  parse_result=$(python3 << PYEOF
import json, sys, re

raw = sys.stdin.read()

# Extract JSON from output
json_match = re.search(r'\{[\s\S]*"hooks"[\s\S]*\}', raw)
if not json_match:
    # Try code block
    json_match = re.search(r'\`\`\`(?:json)?\s*(\{[\s\S]*?\})\s*\`\`\`', raw)
    if json_match:
        raw = json_match.group(1)
    else:
        print("NO_JSON", file=sys.stderr)
        sys.exit(1)
else:
    raw = json_match.group(0)

data = json.loads(raw)
hooks = data.get("hooks", [])
if len(hooks) != 3:
    print(f"WRONG_COUNT:{len(hooks)}", file=sys.stderr)
    sys.exit(1)

for i, h in enumerate(hooks):
    if "text" not in h:
        print(f"MISSING_TEXT:{i}", file=sys.stderr)
        sys.exit(1)
    if len(h["text"]) > 280:
        # Truncate to 280
        h["text"] = h["text"][:277] + "..."
    if "formula" not in h:
        h["formula"] = "unknown"
    if "score" not in h:
        h["score"] = 5

sel = data.get("selected", 0)
if not (0 <= sel < 3):
    sel = 0

output = {
    "trendId": "$trend_id",
    "trend": """$(echo "$selected_topic" | head -c 100)""".strip(),
    "hooks": hooks,
    "selected": sel,
    "selectedHook": hooks[sel]["text"]
}

with open("$DATA_DIR/hooks.json", "w") as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

print(f"OK: 3 hooks. Best=#{sel+1} score={hooks[sel]['score']}")
PYEOF
)

  if [[ $? -ne 0 ]]; then
    err "Hook parsing failed: $parse_result"
    # Try to output the raw LLM for debugging
    log "Raw LLM output: ${llm_output:0:200}"
    return 1
  fi

  log "Step 2 result: $parse_result"
  log "Step 2 complete. Hooks saved."
  return 0
}

# ═══════════════════════════════════════════════════════════
# STEP 3: BUILD ARTICLE / THREAD (via Gemini)
# ═══════════════════════════════════════════════════════════
step3_build_article() {
  log "═══ STEP 3: BUILDING THREAD ═══"

  local trend_context selected_hook trend_id trend_topic
  selected_hook=$(python3 -c "import json; print(json.load(open('$DATA_DIR/hooks.json'))['selectedHook'])")
  trend_context=$(python3 -c "
import json
d = json.load(open('$DATA_DIR/trends.json'))
for t in d['trends']:
    if t.get('selected'):
        print(t['context'][:500])
        break
")
  trend_id=$(python3 -c "import json; print(json.load(open('$DATA_DIR/trends.json'))['selectedTrend'])")
  trend_topic=$(python3 -c "
import json
d = json.load(open('$DATA_DIR/trends.json'))
for t in d['trends']:
    if t.get('selected'):
        print(t['topic'][:100])
        break
")

  # Sanitize: remove emojis that break gemini CLI
  selected_hook=$(sanitize_var "$selected_hook")
  trend_context=$(sanitize_var "$trend_context")
  trend_topic=$(sanitize_var "$trend_topic")

  log "Expanding hook into 5-tweet thread..."

  # Write prompt to file (handles multiline safely)
  local prompt_file
  prompt_file=$(make_tmp)
  cat > "$prompt_file" << PROMPT
You are a viral Twitter/X thread writer for @agentxagi, an AI agent growth account.

HOOK (Tweet 1 - use EXACTLY as-is, add a thread emoji and "👇" at end): ${selected_hook}

CONTEXT: ${trend_context}

Write a 5-tweet thread:

Tweet 1: The hook above EXACTLY as-is with a thread emoji and "👇" at the end
Tweet 2: CONTEXT - What happened, why it matters. Specific facts.
Tweet 3: INSIGHT - Your unique take. Why most miss this.
Tweet 4: EXAMPLE - Concrete demo or use case.
Tweet 5: PREDICTION/CTA - What happens next. End with a question.

RULES:
- Each tweet standalone valuable
- Short sentences, max 15 words each
- One idea per tweet
- Specific numbers and names
- Active voice only
- No hedging
- Each tweet under 280 characters
- No hashtags in tweets
- Write in English

OUTPUT ONLY VALID JSON:
{"tweets":["tweet1","tweet2","tweet3","tweet4","tweet5"],"hashtags":["AI","agents"]}
PROMPT

  local llm_output
  llm_output=$(gemini -p "$(cat "$prompt_file")" 2>&1)

  # Remove the "Loaded cached credentials" line
  llm_output=$(echo "$llm_output" | sed '/^Loaded cached credentials$/d')

  if [[ -z "$llm_output" ]]; then
    err "Empty LLM output for article"
    return 1
  fi

  local parse_result
  parse_result=$(python3 << PYEOF
import json, sys, re

raw = sys.stdin.read()

json_match = re.search(r'\{[\s\S]*"tweets"[\s\S]*\}', raw)
if not json_match:
    json_match = re.search(r'\`\`\`(?:json)?\s*(\{[\s\S]*?\})\s*\`\`\`', raw)
    if json_match:
        raw = json_match.group(1)
    else:
        print("NO_JSON", file=sys.stderr)
        sys.exit(1)
else:
    raw = json_match.group(0)

data = json.loads(raw)
tweets = data.get("tweets", [])
if len(tweets) != 5:
    print(f"WRONG_COUNT:{len(tweets)}", file=sys.stderr)
    sys.exit(1)

for i, t in enumerate(tweets):
    if len(t) > 280:
        tweets[i] = t[:277] + "..."

hashtag_list = data.get("hashtags", ["AI", "agents"])

output = {
    "trendId": "$trend_id",
    "trend": "$trend_topic".strip(),
    "hook": tweets[0],
    "tweets": tweets,
    "hashtags": hashtag_list,
    "readyToPost": True
}

with open("$DATA_DIR/article.json", "w") as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

for i, t in enumerate(tweets):
    print(f"  Tweet {i+1}: {len(t)} chars")
print("OK: Thread ready.")
PYEOF
)

  if [[ $? -ne 0 ]]; then
    err "Article parsing failed: $parse_result"
    log "Raw LLM output: ${llm_output:0:300}"
    return 1
  fi

  echo "$parse_result" | tee -a "$LOG_FILE"
  log "Step 3 complete. Thread saved."
  return 0
}

# ═══════════════════════════════════════════════════════════
# STEP 4: PUBLISH THREAD
# ═══════════════════════════════════════════════════════════
step4_publish() {
  log "═══ STEP 4: PUBLISHING THREAD ═══"

  if [[ ! -f "$DATA_DIR/article.json" ]]; then
    die "No article.json found."
  fi

  local tweet_count
  tweet_count=$(python3 -c "import json; print(len(json.load(open('$DATA_DIR/article.json'))['tweets']))")

  log "Posting thread ($tweet_count tweets)..."

  # Post tweet 1
  local tweet1
  tweet1=$(python3 -c "import json; print(json.load(open('$DATA_DIR/article.json'))['tweets'][0])")

  log "Posting tweet 1: ${tweet1:0:80}..."

  local post_result
  post_result=$(twitter post "$tweet1" --json 2>&1) || {
    err "Failed to post tweet 1: $post_result"
    return 1
  }

  local first_tweet_id
  first_tweet_id=$(echo "$post_result" | python3 -c "
import json, sys, re
raw = sys.stdin.read()
try:
    d = json.loads(raw)
    print(d.get('id', d.get('data', {}).get('id', '')))
except:
    m = re.search(r'\"id\":\s*\"?(\d{15,})', raw)
    if m:
        print(m.group(1))
" 2>/dev/null)

  if [[ -z "$first_tweet_id" ]]; then
    err "Could not extract tweet ID: $post_result"
    return 1
  fi

  log "Tweet 1 posted: ID=$first_tweet_id"

  # Post tweets 2-5 as replies
  local reply_to_id="$first_tweet_id"
  for i in $(seq 2 5); do
    local tweet_text
    tweet_text=$(python3 -c "import json; print(json.load(open('$DATA_DIR/article.json'))['tweets'][$((i-1))])")

    log "Posting tweet $i (reply to $reply_to_id)..."
    sleep 3  # Rate limit buffer

    local reply_result
    reply_result=$(twitter post "$tweet_text" --reply-to "$reply_to_id" --json 2>&1) || {
      err "Failed to post tweet $i: $reply_result"
      break
    }

    local reply_id
    reply_id=$(echo "$reply_result" | python3 -c "
import json, sys, re
raw = sys.stdin.read()
try:
    d = json.loads(raw)
    print(d.get('id', d.get('data', {}).get('id', '')))
except:
    m = re.search(r'\"id\":\s*\"?(\d{15,})', raw)
    if m:
        print(m.group(1))
" 2>/dev/null)

    if [[ -n "$reply_id" ]]; then
      log "Tweet $i posted: ID=$reply_id"
      reply_to_id="$reply_id"
    else
      err "Could not extract ID for tweet $i."
      break
    fi
  done

  # Update article.json with published status
  python3 << PYEOF
import json, datetime
with open("$DATA_DIR/article.json") as f:
    d = json.load(f)

d["publishedAt"] = datetime.datetime.now().isoformat()
d["account"] = "$TWITTER_ACCOUNT"
d["status"] = "published"
d["threadUrl"] = f"https://x.com/i/status/$first_tweet_id"

with open("$DATA_DIR/article.json", "w") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)

print(f"Thread URL: https://x.com/i/status/$first_tweet_id")
PYEOF

  log "Step 4 complete. Thread published."
  return 0
}

# ═══════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════
FORCE=false
case "${1:-}" in
  --force|-f) FORCE=true ;;
esac

main() {
  log "════════════════════════════════════════════"
  log "CONTENT ENGINE PIPELINE v2.1 STARTING"
  log "════════════════════════════════════════════"

  # Pre-flight checks
  command -v twitter >/dev/null 2>&1 || die "twitter CLI not found"
  command -v gemini >/dev/null 2>&1 || die "gemini CLI not found"
  command -v python3 >/dev/null 2>&1 || die "python3 not found"

  # Auth check
  local auth_status
  auth_status=$(twitter status 2>&1 | head -1)
  log "Twitter auth: $auth_status"

  acquire_lock

  if [[ "$FORCE" != "true" ]]; then
    circuit_check
  else
    log "Force mode: skipping circuit breaker."
  fi

  retry "SCAN_TRENDS" step1_scan_trends || die "Pipeline failed at step 1"
  retry "GENERATE_HOOKS" step2_generate_hooks || die "Pipeline failed at step 2"
  retry "BUILD_ARTICLE" step3_build_article || die "Pipeline failed at step 3"
  retry "PUBLISH" step4_publish || die "Pipeline failed at step 4"

  log "════════════════════════════════════════════"
  log "PIPELINE COMPLETE ✓"
  log "════════════════════════════════════════════"

  # Show result
  python3 -c "
import json
with open('$DATA_DIR/article.json') as f:
    d = json.load(f)
print(f'Thread: {d.get(\"threadUrl\", \"N/A\")}')
print(f'Trend: {d.get(\"trend\", \"N/A\")}')
print(f'Published: {d.get(\"publishedAt\", \"N/A\")}')
" 2>&1 | tee -a "$LOG_FILE"
}

main "$@"
