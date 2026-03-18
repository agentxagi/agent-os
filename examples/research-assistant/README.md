# Research Assistant — AI Topic Monitor

An example of using Agent OS to set up an autonomous AI research assistant that monitors topics, synthesizes information, and generates reports.

## Overview

This configuration creates a team of AI agents that:
- Monitors specific topics across Twitter and the web
- Synthesizes findings into structured reports
- Tracks trends over time
- Alerts on significant developments

## Agent Team

| Agent | Role | Model | Responsibility |
|-------|------|-------|---------------|
| **Researcher** | Topic Scanner | gpt-4o | Search, filter, and collect relevant content |
| **Analyst** | Synthesizer | gpt-4o | Analyze findings, identify patterns, write reports |
| **Librarian** | Knowledge Base | gpt-4o | Maintain topic database, track history |

## Sprint Configuration

### Sprint 1: Morning Scan (08:00)

```yaml
type: research
tasks:
  - title: "Scan topic feeds for overnight developments"
    assignee: Researcher
    priority: high
    description: |
      Search for new developments in monitored topics.
      Topics: AI agents, LLMs, coding tools, AI regulation.
      Find 10+ relevant items from last 12 hours.
      Output: data/research/{date}-scan.md

  - title: "Synthesize findings into morning brief"
    assignee: Analyst
    priority: high
    depends_on: scan-task
    description: |
      Read scan results and create a structured morning brief.
      Sections: Key Developments, Trending Topics, Notable Voices, Action Items.
      Output: data/reports/{date}-morning-brief.md

  - title: "Update knowledge base with new findings"
    assignee: Librarian
    priority: medium
    depends_on: brief-task
    description: |
      Extract key facts and add to knowledge base.
      Update topic trend history.
      Output: data/knowledge/topics.json (append)
```

### Sprint 2: Deep Dive (14:00)

```yaml
type: deep-dive
tasks:
  - title: "Deep dive into top trending topic"
    assignee: Researcher
    priority: high
    description: |
      Take the #1 trending topic from morning scan.
      Find 20+ data points: tweets, articles, announcements, code releases.
      Output: data/research/{date}-deep-dive-raw.md

  - title: "Write analysis report"
    assignee: Analyst
    priority: high
    depends_on: deep-dive-task
    description: |
      Create a comprehensive analysis:
      - What happened
      - Why it matters
      - Key players involved
      - Historical context (from knowledge base)
      - Predictions
      Output: data/reports/{date}-analysis.md

  - title: "Cross-reference with historical data"
    assignee: Librarian
    priority: medium
    depends_on: analysis-task
    description: |
      Compare current findings with historical patterns.
      Flag if this is unprecedented or cyclical.
      Output: data/reports/{date}-historical-context.md
```

### Sprint 3: Evening Summary (20:00)

```yaml
type: summary
tasks:
  - title: "Collect all day's findings"
    assignee: Researcher
    priority: medium
    description: |
      Aggregate all outputs from morning and afternoon sprints.
      Check for any new developments since 14:00.
      Output: data/research/{date}-evening-scan.md

  - title: "Generate daily digest"
    assignee: Analyst
    priority: high
    depends_on: evening-task
    description: |
      Create a concise daily digest:
      - Top 3 developments
      - Emerging trends
      - Topics to watch tomorrow
      Output: data/reports/{date}-daily-digest.md
```

## Sprint Creator Adaptation

Modify `src/sprint/sprint-creator.sh` for research use:

```bash
case $HOUR in
    08) SPRINT="Morning Scan"; TYPE="research" ;;
    14) SPRINT="Afternoon Deep Dive"; TYPE="deep-dive" ;;
    20) SPRINT="Evening Summary"; TYPE="summary" ;;
    *)  exit 0 ;;
esac
```

## Circuit Breaker Configuration

Research needs different safety thresholds than social growth:

### Content Quality (Report Quality)

```yaml
content:
  closed_to_half_open:
    condition: "3+ reports with no actionable insights"
  half_open_to_closed:
    condition: "Reports contain novel, valuable findings"
  half_open_to_open:
    condition: "5+ reports are redundant or low-quality"
  open_to_half_open:
    cooldown_hours: 4
```

### Engagement (Alert Relevance)

```yaml
engagement:
  closed_to_half_open:
    condition: "Alerts are all noise (no actionable items)"
  half_open_to_open:
    condition: "0 relevant findings in 3 consecutive sprints"
  open_to_half_open:
    cooldown_hours: 6
```

### Following (Search Budget)

```yaml
following:
  closed_to_half_open:
    condition: "API budget >80% consumed before noon"
  half_open_to_open:
    condition: "API rate limited"
  half_open_to_closed:
    condition: "Budget usage normal (<60% by end of day)"
  open_to_half_open:
    cooldown_hours: 4
```

## Output Examples

### Morning Brief

```markdown
# Morning Brief — 2026-03-18

## Key Developments
1. **Claude Code v2.2 released** — New multi-file editing, improved context window
   - Source: @anthropic announcement, 2.4K likes
   - Impact: Could change coding agent landscape

2. **OpenAI launches GPT-5 API** — Generally available, pricing $15/M input tokens
   - Source: OpenAI blog, trending #1 on HN
   - Impact: Price war with Anthropic expected

3. **EU AI Act enforcement begins** — First compliance deadlines hit
   - Source: Reuters, EU Commission press release
   - Impact: European AI startups face new requirements

## Trending Topics
- Coding agents (+340% mentions vs last week)
- AI regulation (+120% mentions)
- Agent orchestration frameworks (new, emerging)

## Notable Voices
- @karpathy: "The coding agent era is just beginning"
- @swyx: "Agent OS patterns are crystallizing"
- @alexalbert__: "Claude Code is my most used tool"

## Action Items
- [ ] Monitor Claude Code adoption metrics
- [ ] Track GPT-5 pricing impact on startup costs
- [ ] Prepare EU compliance brief for portfolio companies
```

### Daily Digest

```markdown
# Daily Digest — 2026-03-18

## Top 3 Developments
1. Claude Code v2.2 — Major update to coding agent capabilities
2. GPT-5 GA — Pricing competitive with Claude, quality benchmarks TBD
3. EU AI Act — Enforcement begins, first compliance deadline

## Emerging Trends
- **Agent-to-agent communication** — Multiple projects exploring agent protocols
- **Local-first AI** — Growing interest in on-device agent runtimes
- **AI safety tooling** — New startups focused on agent guardrails

## Topics to Watch Tomorrow
- GPT-5 benchmark results (expected from third parties)
- Anthropic response to OpenAI pricing
- Senate hearing on AI regulation (scheduled 10am ET)
```

## Customization

### Adding Topics

Edit the search queries in your sprint creator:

```bash
QUERIES=(
  'YOUR TOPIC 1 announcement OR release OR launch'
  'YOUR TOPIC 2 news OR update OR breakthrough'
  'YOUR TOPIC 3 discussion OR debate OR analysis'
)
```

### Changing Output Format

Modify the Analyst agent's SOUL.md to change report format:

```markdown
# Analyst Agent

## Output Format
- Markdown with headers
- Bullet points, not paragraphs
- Include source links
- Lead with impact, not chronology
- Max 500 words per report
```

### Adding Alert Channels

Use OpenClaw's messaging tools to send reports:

```bash
# Send digest to Telegram
# In agent SOUL.md or heartbeat:
# "After creating daily digest, send summary to @your-telegram-id"
```

## Cron Schedule

```cron
# Research sprints (3x/day)
0 8,14,20 * * * /path/to/src/sprint/sprint-creator.sh >> /path/to/logs/research.log 2>&1

# Coordinator (every 30 min — research is less time-sensitive)
*/30 * * * * /path/to/src/coordinator/paperclip-coordinator.sh >> /path/to/logs/coordinator.log 2>&1

# Circuit breaker (every hour — research has lower urgency)
0 * * * * /path/to/src/circuit-breaker/circuit-breaker-check.sh >> /path/to/logs/cb.log 2>&1
```

---

*Start with 2-3 topics and expand as the knowledge base grows. Quality of research improves over time as the Librarian builds historical context.*
