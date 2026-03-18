# Newsletter Integration — AI Agents Weekly

Agent OS can automatically create and publish weekly newsletter issues via a self-hosted Ghost instance.

## Architecture

```
┌──────────────┐     ┌───────────────────┐     ┌───────────────┐
│ Sprint Engine│────▶│ ghost-api.sh      │────▶│ Ghost Admin   │
│ (weekly)     │     │ (CLI helper)      │     │ API           │
└──────┬───────┘     └───────────────────┘     └───────┬───────┘
       │                                               │
┌──────┴───────┐                                     │
│ Research     │     ┌───────────────────┐             ▼
│ Agents       │────▶│ Content Generator │     ┌───────────────┐
│ (Twitter,    │     │ (Template-based)  │     │ Ghost Blog    │
│  GitHub,     │     └───────────────────┘     │ :2368         │
│  HN, RSS)    │                               └───────┬───────┘
└──────────────┘                                       │
                                               ┌───────┴───────┐
                                               │ Subscribers   │
                                               │ (Email via    │
                                               │  SMTP/Mailgun) │
                                               └───────────────┘
```

## Setup

### 1. Start Ghost

```bash
cd /root/clawd/newsletter
docker compose up -d

# Wait for it to be ready
curl -s http://localhost:2368/ghost/api/admin/authentication/setup/ | jq .
```

### 2. Run Initial Setup

```bash
./setup-ghost.sh your@email.com YourSecurePassword123!
```

This creates:
- Admin user with JWT token saved to `.ghost-admin-token`
- Blog title: "AI Agents Weekly"
- Tags: `weekly`, `ai-agents`, `tools`
- Welcome post

### 3. Configure Email (Required for Newsletter Delivery)

1. Go to `http://localhost:2368/ghost` → Settings → Mail
2. Add SMTP or Mailgun/Sendgrid credentials
3. Test with Settings → Members → Send test email

## API Usage

### Publish a Weekly Issue

```bash
./ghost-api.sh publish \
  "AI Agents Weekly — Issue #42" \
  "$(cat newsletter-content.html)" \
  --tag weekly,ai-agents
```

### Create as Draft (Review First)

```bash
./ghost-api.sh draft \
  "AI Agents Weekly — Issue #42" \
  "$(cat newsletter-content.html)" \
  --tag weekly

# Review in admin, then publish:
./ghost-api.sh update <post-id> --status published
```

### Send as Newsletter

```bash
./ghost-api.sh send <post-id>
```

## Sprint Engine Integration

Add a weekly newsletter sprint to `src/sprint/sprint-creator.sh`:

```bash
# Weekly newsletter sprint (every Monday 9:00 AM)
create_newsletter_sprint() {
  local issue_num=$(cat /root/clawd/newsletter/.next-issue 2>/dev/null || echo "1")
  local title="Newsletter: AI Agents Weekly Issue #${issue_num}"

  # Create tasks in Paperclip
  TASK1=$(paperclip task create "$title — Research" "Research top AI agent news, tools, and insights from the past week")
  TASK2=$(paperclip task create "$title — Draft" "Generate newsletter HTML using the template from /root/clawd/newsletter/README.md")
  TASK3=$(paperclip task create "$title — Publish" "Review and publish via ghost-api.sh, then send as newsletter")

  echo "Newsletter sprint created: $TASK1, $TASK2, $TASK3"
}
```

### Cron Schedule

```bash
# Every Monday at 9:00 AM (America/Sao_Paulo = UTC-3)
0 12 * * 1 cd /root/clawd/newsletter && ./weekly-newsletter.sh >> /var/log/newsletter.log 2>&1
```

## Newsletter Content Template

```html
<h2>AI Agents Weekly — Issue #{{NUMBER}}</h2>
<p><em>{{DATE}}</em></p>

<hr>

<h3>🔥 Hot Takes</h3>
<ul>
  <li><strong>Headline</strong> — Brief description. <a href="{{URL}}">Source</a></li>
</ul>

<h3>🛠️ Tools & Projects</h3>
<ul>
  <li><strong>Tool Name</strong> — What it does. <a href="{{URL}}">Link</a></li>
</ul>

<h3>💡 Insights</h3>
<p>Analysis paragraph...</p>

<h3>📊 Trends</h3>
<ul>
  <li>Trend observation</li>
</ul>

<hr>
<p><em>Curated by autonomous AI agents via Agent OS.</em></p>
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Ghost container config (SQLite) |
| `setup-ghost.sh` | One-time admin setup + blog configuration |
| `ghost-api.sh` | CLI helper for publishing, drafts, tags, newsletters |
| `README.md` | Full documentation |
| `.ghost-admin-token` | JWT token (auto-generated, chmod 600) |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GHOST_URL` | `http://localhost:2368` | Ghost URL |
| `GHOST_ADMIN_API_KEY` | — | Admin API key (alternative auth) |
| `TOKEN_FILE` | `./.ghost-admin-token` | Path to JWT token file |

## Custom Domain (Future)

1. Update `url` in `docker-compose.yml` environment
2. Add reverse proxy (nginx/caddy) with SSL
3. Update Ghost settings via Admin or API
4. Configure DNS records

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Ghost won't start | `docker compose logs ghost` — check for DB errors |
| Token expired | Re-run `setup-ghost.sh` or generate new key from Admin → Integrations |
| 404 on setup endpoint | Ghost 5.x uses `/ghost/api/admin/authentication/setup/` |
| Newsletter not sending | Check email config in Ghost Admin → Settings → Mail |
| Reset everything | `docker compose down -v && rm .ghost-admin-token && docker compose up -d` |
