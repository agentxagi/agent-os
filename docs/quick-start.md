# Quick Start: One-Person AI Company in 15 Minutes

This guide walks you through setting up Agent OS to run an autonomous AI agent team — your own one-person AI company.

## Prerequisites

- A machine that runs 24/7 (VPS, dedicated server, or always-on desktop)
- Bash 4.0+, curl, jq, python3
- A Twitter/X account (for social automation)
- API keys for an LLM provider (OpenAI, Google, etc.)

## Step 1: Install OpenClaw (2 min)

[OpenClaw](https://openclaw.dev) is the agent runtime that powers your AI team.

```bash
# Install OpenClaw
curl -fsSL https://openclaw.dev/install.sh | bash

# Configure your LLM provider
openclaw config set provider openai
openclaw config set apiKey sk-your-key-here

# Verify installation
openclaw --version
```

OpenClaw manages agent sessions, heartbeats, cron jobs, and tool access. Each agent is a persona with its own workspace, SOUL.md, and tools.

## Step 2: Install Paperclip (3 min)

[Paperclip](https://paperclip.dev) is the task coordination system — your team's Kanban board.

```bash
# Install Paperclip
npm install -g @paperclip/cli

# Start the server
paperclip serve --port 3100

# Verify it's running
curl http://localhost:3100/api/health
```

Paperclip provides:
- Task board with status tracking (todo → in_progress → done)
- Agent assignment and workload management
- Comment threads for inter-agent communication
- Project and workspace organization

## Step 3: Clone Agent OS (1 min)

```bash
git clone https://github.com/agentxagi/agent-os.git
cd agent-os
```

## Step 4: Configure Agents (5 min)

Define your agent team. Each agent has a role, model, and schedule.

### Create Agent Personas in OpenClaw

Each agent needs a workspace with a `SOUL.md` defining its behavior:

```bash
# Create workspace directories
mkdir -p ~/.openclaw/workspace-{ba,cto,pm,de,designer}

# Example: CTO agent SOUL.md
cat > ~/.openclaw/workspace-cto/SOUL.md << 'EOF'
# CTO Agent

You are the CTO of an autonomous AI company. Your job is to create high-quality
technical content about AI agents, LLMs, and developer tools.

## Responsibilities
- Create Twitter threads about AI/tech topics
- Write hot takes and contrarian opinions
- Review technical accuracy of content

## Style
- Direct, opinionated, technical
- Use specific numbers and examples
- No filler words, no hedging
- Max 280 chars per tweet
EOF
```

### Register Agents in Paperclip

```bash
# Using the Paperclip API helper
PAPERCLIP_API_URL=http://localhost:3100 \
bash src/api/paperclip-api.sh create "Configure CTO agent" "Set up CTO persona for content creation" "<agent-id>"
```

### Configure Sprint Schedule

Set up cron jobs for automated sprint creation:

```bash
# Edit crontab
crontab -e

# Add sprint creator (4x per day at 8h, 12h, 16h, 20h)
0 8,12,16,20 * * * /path/to/agent-os/src/sprint/sprint-creator.sh >> /path/to/logs/sprint.log 2>&1

# Add coordinator (every 15 min)
*/15 * * * * /path/to/agent-os/src/coordinator/paperclip-coordinator.sh >> /path/to/logs/coordinator.log 2>&1

# Add circuit breaker check (every 30 min)
*/30 * * * * /path/to/agent-os/src/circuit-breaker/circuit-breaker-check.sh >> /path/to/logs/circuit-breaker.log 2>&1
```

## Step 5: Configure Circuit Breaker (2 min)

The circuit breaker is your safety net. It automatically stops operations when things go wrong.

Edit the state file to set initial thresholds:

```bash
# Create initial state
cat > /path/to/logs/sprint-creator-state.json << 'EOF'
{
  "circuitBreakers": {
    "content": {
      "state": "CLOSED",
      "consecutiveLow": 0,
      "lastCheck": ""
    },
    "engagement": {
      "state": "CLOSED",
      "consecutiveLow": 0,
      "lastCheck": ""
    },
    "following": {
      "state": "CLOSED",
      "consecutiveLow": 0,
      "lastCheck": ""
    }
  }
}
EOF
```

**What each breaker does:**
- **Content Quality** — Stops posting if your content gets low views (prevents wasting effort on bad content)
- **Engagement Signals** — Detects if you're being ignored or shadowbanned
- **Following Growth** — Prevents aggressive following that could get you flagged

## Step 6: Create Your First Sprint (1 min)

```bash
# Run sprint creator manually to test
bash src/sprint/sprint-creator.sh

# Check the log
tail -20 /path/to/logs/sprint.log
```

You should see something like:
```
[2026-03-18 08:00:01] Creating sprint: 2026-03-18 Morning Research
[2026-03-18 08:00:02] Sprint '2026-03-18 Morning Research' created with 4 tasks: AGOS-1, AGOS-2, AGOS-3, AGOS-4
```

## Step 7: Monitor Everything (1 min)

```bash
# Check circuit breaker state
bash src/circuit-breaker/circuit-breaker-check.sh
tail -5 /path/to/logs/circuit-breaker.log

# Check coordinator status
bash src/coordinator/paperclip-coordinator.sh
tail -10 /path/to/logs/coordinator.log

# Check Paperclip task board
PAPERCLIP_API_URL=http://localhost:3100 bash src/api/paperclip-api.sh tasks
```

## What Happens Next

Once configured, the system runs autonomously:

```
08:00  ──── Sprint: Research topics → Create content → Engage
12:00  ──── Sprint: Heavy engagement → Strategic follows
16:00  ──── Sprint: Content creation → Review → Publish
20:00  ──── Sprint: Analytics → Circuit breaker update → Report

Every 15 min ──── Coordinator checks agent health and task progress
Every 30 min ──── Circuit breaker validates metrics
```

Agents pick up tasks from Paperclip via heartbeats, execute them, and update status. The coordinator monitors for problems. The circuit breaker protects against quality degradation.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Sprint creator says "Circuit breaker OPEN" | Check `circuit-breaker.log` for which breaker tripped. Wait for cooldown or fix the underlying issue. |
| Agents not picking up tasks | Check OpenClaw gateway status. Verify agent heartbeats are running. |
| Paperclip unreachable | Check `paperclip serve` is running on port 3100. |
| Twitter rate limited | Circuit breaker should catch this. Check following breaker state. |
| Duplicate sprints | Check `sprint-creator-state.json` for `lastSprint` value. |

## Next Steps

- **Customize sprint types** — Edit `src/sprint/sprint-creator.sh` to match your goals
- **Add platforms** — Extend the content pipeline for LinkedIn, newsletters, etc.
- **Adjust thresholds** — Tune circuit breaker values for your audience size
- **Add agents** — Create new personas for specialized tasks
- **Read the architecture doc** — `docs/architecture.md` for deeper understanding

---

*Your AI company is now running. Check logs daily for the first week, then weekly. The circuit breaker handles most issues automatically.*
