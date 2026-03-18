<div align="center">

# 🤖 Agent OS

**Open Source Multi-Agent Framework**

Run autonomous AI agent teams 24/7. Circuit breakers, sprint automation, task delegation — build your own one-person AI company.

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-green.svg)](https://github.com/agentxagi/agent-os/releases)
[![OpenClaw](https://img.shields.io/badge/powered%20by-OpenClaw-purple.svg)](https://openclaw.dev)

[Getting Started](#-quick-start) · [Architecture](#-architecture) · [Components](#-components) · [Case Study](#-real-world-example--agentxagi)

</div>

---

## What is Agent OS?

Agent OS is a framework for orchestrating autonomous multi-agent teams. It provides the primitives to run AI agents that plan, execute, monitor, and self-correct — all without human intervention.

Inspired by real-world patterns from running [Ralph's autonomous agent system](https://x.com/ralphchristant) (circuit breaker, exit detection, response analysis), Agent OS packages these battle-tested ideas into a reusable, extensible framework.

Built on top of **[OpenClaw](https://openclaw.dev)** (agent runtime) and **[Paperclip](https://paperclip.dev)** (task coordination).

## Why?

We built a one-person AI company — **[@agentxagi](https://x.com/agentxagi)** — that runs 12+ agents around the clock, posting content, engaging with audiences, and growing a following on autopilot.

This is the framework that makes it possible.

Most "multi-agent" setups are demos. Agent OS is production code — scripts that have been running 24/7 for weeks, with circuit breakers, quality gates, and self-healing baked in.

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AGENT OS                                 │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │    SPRINT     │───▶│   TASK BOARD  │───▶│     AGENTS       │  │
│  │   CREATOR     │    │  (Paperclip)  │    │   (heartbeat)    │  │
│  │  (4x / day)   │    │              │    │                  │  │
│  └──────────────┘    └──────────────┘    └────────┬─────────┘  │
│                                                     │            │
│                                                     ▼            │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │   METRICS &  │◀───│   QUALITY    │◀───│   EXECUTION      │  │
│  │   ANALYTICS  │    │    GATES     │    │   ENGINE         │  │
│  └──────┬───────┘    └──────────────┘    └──────────────────┘  │
│         │                                                      │
│         ▼                                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  CIRCUIT BREAKER                          │  │
│  │  ┌──────────┐  ┌─────────────┐  ┌────────────────────┐  │  │
│  │  │ CONTENT  │  │ ENGAGEMENT  │  │    FOLLOWING       │  │  │
│  │  │ QUALITY  │  │   SIGNALS   │  │    GROWTH          │  │  │
│  │  └──────────┘  └─────────────┘  └────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ✨ Features

### 🛡 Circuit Breaker System
Three independent circuit breakers that can halt operations automatically:
- **Content Quality** — Stops posting if content isn't meeting engagement thresholds
- **Engagement Signals** — Monitors likes, retweets, replies for anomaly detection
- **Following Growth** — Halts growth tactics if following/follower ratio degrades

Each breaker has configurable thresholds, cooldown periods, and auto-recovery.

### 🏃 Sprint Automation
- Automatic sprint creation (4x per day)
- Task generation based on goals and historical performance
- Priority queuing and dependency management

### 📋 Task Delegation
- Paperclip-powered task board
- Agent assignment with skill matching
- 15-minute monitoring loops
- Status tracking and escalation

### 🔒 Quality Gates
- Pre-execution content review
- Engagement prediction scoring
- Automated approval/rejection workflow

### ⏰ 24/7 Operation
- Cron-based scheduling
- Heartbeat monitoring
- Self-healing on failure
- Graceful degradation

### 🌐 Multi-Platform
- Twitter/X (primary)
- LinkedIn (planned)
- Newsletter (planned)
- Extensible adapter system

---

## 🚀 Quick Start

### 1. Install

```bash
git clone https://github.com/agentxagi/agent-os.git
cd agent-os
npm install
```

### 2. Configure Agents

Edit `config/agents.yaml` to define your agent team:

```yaml
agents:
  - name: content-creator
    model: gpt-4o
    schedule: "0 */6 * * *"
    platforms: [twitter]
    
  - name: engagement-bot
    model: gpt-4o
    schedule: "*/15 * * * *"
    platforms: [twitter]
```

### 3. Run

```bash
# Start the sprint engine
npm run sprint

# Monitor agent status
npm run status

# Check circuit breaker state
npm run circuit-breaker
```

---

## 📦 Components

| Module | Path | Description |
|--------|------|-------------|
| **Circuit Breaker** | `src/circuit-breaker/` | Independent breakers for content, engagement, and growth |
| **Sprint Creator** | `src/sprint/` | Automated sprint generation and task planning |
| **Coordinator** | `src/coordinator/` | Paperclip integration, 15min monitoring loops |
| **API Helper** | `src/api/` | Paperclip REST API wrapper |
| **Content Pipeline** | `src/content/` | Content generation, review, and publishing pipeline |
| **Templates** | `templates/` | Ready-to-use agent configurations |

---

## ⚙️ How It Works

### Sprint Flow

```
Sprint Creator (cron: 4x/day)
    │
    ├─▶ Analyze current metrics
    ├─▶ Generate tasks based on goals
    ├─▶ Push tasks to Paperclip board
    └─▶ Notify agents via heartbeat
```

### Task Lifecycle

```
Created → Assigned → In Progress → Review → Done
                │           │
                │           └─▶ Failed → Retry (3x) → Escalate
                └─▶ Stale (>1h idle) → Reassign
```

### Circuit Breaker States

```
CLOSED ──▶ OPEN (threshold breached)
              │
              └─▶ HALF-OPEN (cooldown expired)
                    │
                    ├─▶ CLOSED (recovery successful)
                    └─▶ OPEN (still failing)
```

---

## 📊 Real-World Example: @agentxagi

Agent OS powers [@agentxagi](https://x.com/agentxagi), a fully autonomous AI growth agent running on Twitter/X.

| Metric | Value |
|--------|-------|
| **Agents running** | 12+ |
| **Uptime** | 24/7 |
| **Sprints per day** | 4 |
| **Monitoring interval** | 15 minutes |
| **Circuit breakers** | 3 (content, engagement, following) |
| **Platforms** | Twitter/X |
| **Human intervention** | Near-zero |

The system creates content, monitors engagement, adjusts strategy, and self-corrects — all autonomously. The circuit breaker ensures quality: if engagement drops, it stops posting and recalibrates before resuming.

---

## 🗺 Roadmap

- [ ] **v0.2** — CLI tool (`agent-os init`, `agent-os deploy`)
- [ ] **v0.3** — NPM package (`@agent-os/core`)
- [ ] **v0.4** — Agent templates (newsletter, research, sales)
- [ ] **v0.5** — Web dashboard for monitoring
- [ ] **v1.0** — Hosted version (deploy your own AI company in 5 minutes)

---

## 🤝 Contributing

We welcome contributions! Here's how to get started:

1. **Fork** the repository
2. **Create a branch** (`git checkout -b feature/my-feature`)
3. **Make changes** and test thoroughly
4. **Commit** with clear messages (`git commit -m "Add X for Y"`)
5. **Push** to your fork (`git push origin feature/my-feature`)
6. **Open a Pull Request**

### Guidelines

- Keep scripts portable (bash, no exotic dependencies)
- Add comments explaining non-obvious logic
- Update this README if adding new components
- Test circuit breaker logic carefully — it's the safety net

---

## 📄 License

MIT License — use it, modify it, ship it. Build your own AI company.

---

<div align="center">

**Built with [OpenClaw](https://openclaw.dev) + [Paperclip](https://paperclip.dev)**

Made with 🧠 by humans and agents working together.

</div>
