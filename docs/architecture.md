# Architecture

Agent OS orchestrates autonomous multi-agent teams using a sprint-based workflow, circuit breakers for safety, and real-time monitoring. This document describes the system in detail.

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                             AGENT OS                                    │
│                                                                         │
│  ┌───────────────┐     ┌───────────────┐     ┌──────────────────────┐  │
│  │  CRON SCHEDULER│────▶│   SPRINT      │────▶│   PAPERCLIP          │  │
│  │  (4x / day)    │     │   CREATOR     │     │   TASK BOARD         │  │
│  └───────────────┘     │               │     │   (REST API)         │  │
│                        │ Creates tasks  │     └──────────┬───────────┘  │
│                        │ per sprint type│                │              │
│                        └───────┬───────┘                │              │
│                                │                        │              │
│  ┌───────────────┐             │             ┌──────────▼───────────┐  │
│  │  CIRCUIT      │◀──── safety gate ────────▶│   OPENCLAW AGENTS    │  │
│  │  BREAKER      │     (pre-creation check)  │   (heartbeat-based)  │  │
│  │  SYSTEM       │                            │                      │  │
│  │               │     ┌───────────────┐      │  - Business Analyst  │  │
│  │ ┌───────────┐ │     │  COORDINATOR  │      │  - CTO               │  │
│  │ │ Content   │ │     │  (15 min loop)│◀────▶│  - Product Manager   │  │
│  │ ├───────────┤ │     │               │      │  - Data Engineer     │  │
│  │ │Engagement │ │     │ - Health check│      │  - Designer          │  │
│  │ ├───────────┤ │     │ - Agent status│      │                      │  │
│  │ │ Following  │ │     │ - Mentions    │      └──────────┬───────────┘  │
│  │ └───────────┘ │     │ - Escalation  │                 │              │
│  └───────┬───────┘     └───────────────┘                 │              │
│          │                                                │              │
│          │              ┌───────────────┐                 │              │
│          └─────────────▶│ CONTENT       │◀────────────────┘              │
│                         │ PIPELINE      │                                │
│                         │               │                                │
│                         │ 1. Scan trends│                                │
│                         │ 2. Gen hooks  │                                │
│                         │ 3. Build thread│                               │
│                         │ 4. Publish    │                                │
│                         └───────────────┘                                │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components

### Sprint Creator (`src/sprint/sprint-creator.sh`)

The brain of the system. Runs on a cron schedule (4 times per day) and generates task batches for the agent team.

**Schedule:**

| Hour (BRT) | Sprint Type | Focus |
|-------------|-------------|-------|
| 08:00 | Morning Research | Trend analysis, content ideation |
| 12:00 | Midday Engagement | Replies, follows, community building |
| 16:00 | Afternoon Content | Thread creation, publishing |
| 20:00 | Evening Analytics | Metrics, circuit breaker updates |

**Key behaviors:**
- Checks circuit breaker state before creating tasks (won't create content tasks if content breaker is OPEN)
- Deduplicates — won't create the same sprint twice
- Checks open task count — won't flood the board (skips if >5 open tasks)
- Creates tasks with dependencies (e.g., Designer reviews CTO's content)

### Circuit Breaker (`src/circuit-breaker/circuit-breaker-check.sh`)

Three independent breakers that can halt operations to prevent damage. Each operates on its own state machine.

| Breaker | What It Protects | Runs |
|---------|-----------------|------|
| **Content Quality** | Stops posting if content gets low views | After sprint creation + every 30min |
| **Engagement Signals** | Monitors reply engagement for shadowban detection | After sprint creation + every 30min |
| **Following Growth** | Halts follow tactics if ratio degrades | After sprint creation + every 30min |

### Coordinator (`src/coordinator/paperclip-coordinator.sh`)

Lightweight monitor that runs every 15 minutes. Detects problems but doesn't act directly — it logs alerts for the OpenClaw main agent to handle.

**Checks:**
1. **Paperclip health** — Is the API reachable?
2. **Agent status** — Any agents in error state? How many idle?
3. **Agent mentions** — Scans task comments for agent name mentions
4. **Critical blocked** — Alerts on high-priority tasks blocked >1 hour

### API Helper (`src/api/paperclip-api.sh`)

CLI wrapper around the Paperclip REST API. Used by all agents and scripts to interact with the task board.

**Capabilities:**
- CRUD operations on tasks (create, read, update, comment)
- Agent management (list, assign, release)
- Project and workspace queries
- Health checks and cost tracking
- Machine-readable (`--json`) and human-readable output modes

### Content Pipeline (`src/content/pipeline.sh`)

Fully autonomous content generation pipeline. Four-step process:

1. **Scan Trends** — Searches Twitter for trending AI topics, scores by engagement heat
2. **Generate Hooks** — Uses Gemini to create 3 viral hooks from the selected trend
3. **Build Thread** — Expands the best hook into a 5-tweet thread
4. **Publish** — Posts the thread to Twitter with proper reply threading

**Safety features:**
- Topic blacklist (boycott, crypto, trading, etc.)
- 2-hour circuit breaker between successful publishes
- 3-retry logic per step
- Lock file to prevent concurrent runs

## Data Flow

```
┌────────────┐    ┌──────────────┐    ┌────────────────┐    ┌─────────────┐
│   TWITTER   │    │   SPRINT     │    │   PAPERCLIP    │    │   OPENCLAW  │
│   API       │◀──▶│   CREATOR    │───▶│   TASK BOARD   │───▶│   AGENTS    │
│             │    │              │    │                │    │             │
│ - Search    │    │ - Read state │    │ - Store tasks  │    │ - Consume   │
│ - Post      │    │ - Check CB   │    │ - Track status │    │   tasks     │
│ - Profile   │    │ - Gen tasks  │    │ - Comments     │    │ - Execute   │
│ - Follow    │    │ - Push tasks │    │ - Assignments  │    │ - Comment   │
└────────────┘    └──────┬───────┘    └───────┬────────┘    └──────┬──────┘
                         │                    │                     │
                         │    ┌───────────────┘                     │
                         │    │                                     │
                    ┌────▼────▼────┐                          ┌─────▼──────┐
                    │  CIRCUIT      │                          │  CONTENT   │
                    │  BREAKER      │◀─────────────────────────│  PIPELINE  │
                    │              │     (metrics feedback)    │            │
                    │ - Check metrics│                          │ - Generate │
                    │ - Update state│                          │ - Publish  │
                    │ - Alert      │                          │ - Log      │
                    └──────────────┘                          └────────────┘
```

### State Files

| File | Purpose |
|------|---------|
| `sprint-creator-state.json` | Circuit breaker states, last sprint info |
| `paperclip-coordinator-state.json` | Coordinator run state, alert tracking |
| `content-engine/data/trends.json` | Current trend analysis |
| `content-engine/data/hooks.json` | Generated hook options |
| `content-engine/data/article.json` | Latest thread ready to publish |

## Circuit Breaker State Machine

Each of the three breakers follows this state machine:

```
                    ┌──────────────────────────┐
                    │                          │
            ┌───────│     CLOSED (normal ops)   │───────┐
            │       │                          │       │
            │       │  Everything is healthy   │       │
            │       │  Agents operate normally │       │
            │       └──────────┬───────────────┘       │
            │                  │                       │
            │         Threshold breached              │
            │         (degraded signal)               │
            │                  │                       │
            │                  ▼                       │
            │       ┌──────────────────────┐          │
            │       │                      │          │
            │       │   HALF-OPEN (warning) │          │
            │       │                      │          │
            │       │  Reduced operations   │          │
            │       │  Monitoring closely   │          │
            │       └──────────┬───────────┘          │
            │                  │                       │
            │         ┌────────┴────────┐              │
            │         │                 │              │
            │    Still failing     Recovering         │
            │    (no improvement)  (signal OK)        │
            │         │                 │              │
            │         ▼                 │              │
            │  ┌──────────────────┐     │              │
            │  │                  │     │              │
            │  │  OPEN (halted)   │     │              │
            │  │                  │     │              │
            │  │  All operations  │     │              │
            │  │  suspended       │     │              │
            │  │                  │     │              │
            │  └────────┬─────────┘     │              │
            │           │               │              │
            │    Cooldown expires       │              │
            │    (2h / 4h / 6h)         │              │
            │           │               │              │
            └───────────┘               │              │
                                        │              │
                    Recovery confirmed ◀─┘              │
                    (metrics back to normal)           │
                                                          │
                    ◀─────────────────────────────────────┘
```

### Breaker Thresholds

#### Content Quality Breaker

| Transition | Condition |
|------------|-----------|
| CLOSED → HALF_OPEN | 3+ of last 5 posts have < 50 views |
| HALF_OPEN → CLOSED | 3+ of last 5 posts have > 100 views |
| HALF_OPEN → OPEN | 5+ of last 5 posts have < 20 views |
| OPEN → HALF_OPEN | 2-hour cooldown elapsed |

#### Engagement Signals Breaker

| Transition | Condition |
|------------|-----------|
| CLOSED → HALF_OPEN | 0 likes on last 10 replies |
| HALF_OPEN → OPEN | Rate limited or shadowbanned |
| HALF_OPEN → CLOSED | Getting engagement again |
| OPEN → HALF_OPEN | 4-hour cooldown elapsed |

#### Following Growth Breaker

| Transition | Condition |
|------------|-----------|
| CLOSED → HALF_OPEN | Following/follower ratio < 1.5 |
| HALF_OPEN → OPEN | Ratio < 1.2 OR receiving 429 errors |
| HALF_OPEN → CLOSED | Ratio > 2.0 |
| OPEN → HALF_OPEN | 6-hour cooldown elapsed |

## Sprint Lifecycle

```
  CRON TRIGGER (08:00 / 12:00 / 16:00 / 20:00)
                  │
                  ▼
        ┌─────────────────┐
        │ Determine Sprint │
        │ Type by Hour     │
        └────────┬────────┘
                 │
                 ▼
        ┌─────────────────┐     ┌──────────────┐
        │ Check Circuit   │────▶│  CB is OPEN  │
        │ Breaker State   │     │  Skip sprint │
        └────────┬────────┘     └──────────────┘
                 │ CB is CLOSED
                 ▼
        ┌─────────────────┐     ┌──────────────┐
        │ Check Open Task │────▶│  >5 open     │
        │ Count           │     │  Skip sprint │
        └────────┬────────┘     └──────────────┘
                 │ Team available
                 ▼
        ┌─────────────────┐
        │ Check Sprint    │     ┌──────────────┐
        │ Already Created │────▶│  Duplicate   │
        │ (dedup check)   │     │  Skip sprint │
        └────────┬────────┘     └──────────────┘
                 │ New sprint
                 ▼
        ┌─────────────────┐
        │ Generate Tasks  │
        │ (type-specific) │
        └────────┬────────┘
                 │
                 ▼
        ┌─────────────────┐
        │ Push to Paperclip│
        │ (with deps)     │
        └────────┬────────┘
                 │
                 ▼
        ┌─────────────────┐
        │ Notify Agents   │
        │ (via heartbeat) │
        └─────────────────┘
```

## Agent Heartbeat Mechanism

Agents in Agent OS are powered by **OpenClaw** and operate on a heartbeat model:

```
  ┌─────────────────────────────────────────────────┐
  │                HEARTBEAT LOOP                    │
  │                                                  │
  │   1. Agent wakes up (OpenClaw session start)     │
  │                     │                            │
  │                     ▼                            │
  │   2. Read HEARTBEAT.md for task checklist        │
  │                     │                            │
  │                     ▼                            │
  │   3. Check Paperclip for assigned tasks          │
  │      (via paperclip-api.sh)                      │
  │                     │                            │
  │                     ▼                            │
  │   4. Execute task                               │
  │      - Generate content                          │
  │      - Engage on Twitter                         │
  │      - Analyze metrics                           │
  │                     │                            │
  │                     ▼                            │
  │   5. Update task status + comment on Paperclip   │
  │                     │                            │
  │                     ▼                            │
  │   6. If more tasks → go to step 3                │
  │      If no tasks   → reply HEARTBEAT_OK          │
  └─────────────────────────────────────────────────┘
```

**Key design decisions:**
- Agents don't poll constantly — they wake on heartbeat intervals
- Task state lives in Paperclip (not in agent memory)
- Coordinator detects agent mentions in comments for inter-agent coordination
- Failed tasks are retried 3x, then escalated
- Stale tasks (>1h idle) are reassigned automatically

## Monitoring and Observability

| Mechanism | Interval | What It Checks |
|-----------|----------|---------------|
| Sprint Creator | 4x/day | Task generation, circuit breaker |
| Circuit Breaker | 30 min | Content, engagement, following metrics |
| Coordinator | 15 min | API health, agent status, mentions, blocked tasks |
| Content Pipeline | On-demand (with 2h cooldown) | Full publish cycle |
| Agent Heartbeat | ~30 min (configurable) | Task consumption, execution |

**Log files:**
- `logs/circuit-breaker.log` — State transitions and alerts
- `logs/sprint-creator.log` — Sprint creation events
- `logs/paperclip-coordinator.log` — Coordination events
- `logs/content-engine-cron.log` — Content pipeline execution
