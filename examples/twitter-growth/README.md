# Twitter Growth Agent — @agentxagi

A real-world example of using Agent OS to run a fully autonomous Twitter/X growth account. This is the exact configuration that powers [@agentxagi](https://x.com/agentxagi).

## Overview

@agentxagi is an AI agent that autonomously grows a Twitter audience by:
- Researching trending AI topics
- Creating threads and hot takes
- Engaging with the AI community
- Monitoring metrics and self-correcting

**Zero human intervention** — the system plans, creates, publishes, and adjusts strategy on its own.

## Agent Team

| Agent | Role | Model | Responsibility |
|-------|------|-------|---------------|
| **Business Analyst** | Researcher | gpt-4o | Trend analysis, metrics reporting |
| **CTO** | Content Creator | gpt-4o | Thread writing, hot takes |
| **Product Manager** | Engagement | gpt-4o | Replies, community building |
| **Data Engineer** | Analytics | gpt-4o | Metrics collection, reporting |
| **Designer** | Quality Gate | gpt-4o | Content review, publishing |

## Sprint Configuration

Four sprints per day, each with a different focus:

### Sprint 1: Morning Research (08:00 BRT)

```yaml
type: research
tasks:
  - title: "Research Sprint — Find top 5 trending AI/agent topics"
    assignee: Business Analyst
    priority: high
    description: |
      Search Twitter for trending AI/agent topics.
      Find 5 topics with active discussion (50+ likes threads).
      Output: data/trends/{date}-sprint.md

  - title: "Create 2 threads based on sprint research"
    assignee: CTO
    priority: high
    depends_on: research-task
    description: |
      Write 2 threads (5-8 tweets each).
      Structure: Hook → Context → Insight → Example → Prediction → Takeaway
      DO NOT POST — Designer will review.

  - title: "Reply to 15 AI/agent discussions"
    assignee: Product Manager
    priority: high
    description: |
      Find and reply to 15 relevant discussions.
      Target: 5K-100K followers, active (last 24h).
      Add genuine insight. NO generic replies.

  - title: "Review and post approved threads"
    assignee: Designer
    priority: high
    depends_on: cto-task
    description: |
      Review for quality. Post if passes.
      Checklist: English, technical, <280 chars, opinionated.
```

### Sprint 2: Midday Engagement (12:00 BRT)

```yaml
type: engagement
tasks:
  - title: "Engagement sprint — Reply to 25 relevant discussions"
    assignee: Product Manager
    priority: high
    description: |
      10 replies to large accounts (10K+)
      10 replies to mid-size accounts (1K-10K)
      5 replies to small accounts (<1K)

  - title: "Strategic follows — Follow 20 relevant AI accounts"
    assignee: Business Analyst
    priority: medium
    description: |
      Find and follow 20 accounts posting about AI agents.
      Criteria: 1K+ followers, active (last 7 days).
```

### Sprint 3: Afternoon Content (16:00 BRT)

```yaml
type: content
tasks:
  - title: "Create 1 standalone hot take tweet"
    assignee: CTO
    priority: medium
    description: |
      Max 280 chars, bold opinion, specific data point.

  - title: "Create 1 thread (6-8 tweets)"
    assignee: CTO
    priority: high
    description: |
      Structure: Hook → Context → Insight → Example → Prediction → Takeaway.

  - title: "Review and post content"
    assignee: Designer
    priority: high
    depends_on: cto-tasks
    description: Review quality, post if passes.

  - title: "Reply to 10 relevant discussions"
    assignee: Product Manager
    priority: medium
```

### Sprint 4: Evening Analytics (20:00 BRT)

```yaml
type: analytics
tasks:
  - title: "Daily metrics snapshot and report"
    assignee: Data Engineer
    priority: medium
    description: |
      Collect @agentxagi metrics.
      Report: follower/following ratio, posts today, avg views, best/worst content.

  - title: "Update circuit breaker state"
    assignee: Business Analyst
    priority: medium
    depends_on: metrics-task
    description: |
      Analyze metrics and update circuit breaker thresholds.
```

## Circuit Breaker Thresholds

### Content Quality

```yaml
content:
  closed_to_half_open:
    condition: "3+ of last 5 posts have < 50 views"
  half_open_to_closed:
    condition: "3+ of last 5 posts have > 100 views"
  half_open_to_open:
    condition: "5+ of last 5 posts have < 20 views"
  open_to_half_open:
    cooldown_hours: 2
```

### Engagement Signals

```yaml
engagement:
  closed_to_half_open:
    condition: "0 likes on last 10 replies"
  half_open_to_open:
    condition: "Rate limited or shadowbanned"
  half_open_to_closed:
    condition: "Getting engagement again"
  open_to_half_open:
    cooldown_hours: 4
```

### Following Growth

```yaml
following:
  closed_to_half_open:
    condition: "Following/follower ratio < 1.5"
  half_open_to_open:
    condition: "Ratio < 1.2 OR 429 errors"
  half_open_to_closed:
    condition: "Ratio > 2.0"
  open_to_half_open:
    cooldown_hours: 6
```

## Topic Blacklist

The system avoids controversial or off-topic content:

```
boycott, concert, crypto, trading, paramount, elon musk, muslim, fasting, midjourney, warner
```

## Content Pipeline

Beyond sprint-based creation, there's a standalone content pipeline:

```
1. SCAN TRENDS  →  Search Twitter, score by engagement heat
2. GEN HOOKS    →  Gemini creates 3 viral hooks
3. BUILD THREAD →  Expand best hook into 5-tweet thread
4. PUBLISH      →  Post to Twitter with reply threading
```

**Safety:** 2-hour cooldown between publishes, 3-retry per step, topic blacklist.

## Cron Schedule

```cron
# Sprint creator (4x/day)
0 8,12,16,20 * * * /path/to/src/sprint/sprint-creator.sh >> /path/to/logs/sprint.log 2>&1

# Coordinator (every 15 min)
*/15 * * * * /path/to/src/coordinator/paperclip-coordinator.sh >> /path/to/logs/coordinator.log 2>&1

# Circuit breaker (every 30 min)
*/30 * * * * /path/to/src/circuit-breaker/circuit-breaker-check.sh >> /path/to/logs/cb.log 2>&1
```

## Actual Metrics

| Metric | Value |
|--------|-------|
| Agents running | 12+ |
| Uptime | 24/7 |
| Sprints per day | 4 |
| Monitoring interval | 15 minutes |
| Circuit breakers | 3 independent |
| Human intervention | Near-zero |
| Content pipeline cooldown | 2 hours |

## Key Learnings

1. **Circuit breaker is essential** — Without it, the system will spam low-quality content during bad periods
2. **Quality gates matter** — Having a "Designer" agent review before publishing prevents embarrassing mistakes
3. **Dedup is critical** — Without sprint dedup, you'll get duplicate tasks flooding the board
4. **Blacklist saves you** — One crypto tweet can alienate your AI audience permanently
5. **Cooldown prevents bans** — The 2-hour publish cooldown and rate limit buffers keep the account safe

## Adapting This for Your Account

1. **Change the handle** — Replace `@agentxagi` in all scripts
2. **Adjust sprint focus** — Change topic queries to match your niche
3. **Tune thresholds** — Start with conservative thresholds and tighten over time
4. **Add your blacklist** — Add topics relevant to your audience
5. **Scale agents** — Start with 3 agents (creator, reviewer, engager), add more as needed

---

*This configuration runs in production. The code in `src/` is the actual running version.*
