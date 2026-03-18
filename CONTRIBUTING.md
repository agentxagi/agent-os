# Contributing to Agent OS

Thanks for your interest in contributing! Agent OS is an open framework for autonomous multi-agent teams. This guide will help you get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Commit Convention](#commit-convention)
- [Pull Request Process](#pull-request-process)
- [Project Structure](#project-structure)
- [Reporting Issues](#reporting-issues)

## Code of Conduct

Be respectful, constructive, and inclusive. We're building tools that help people work with AI — let's model the collaboration we want to see.

- **Be kind** — Assume good intent
- **Be constructive** — Critique ideas, not people
- **Be inclusive** — Welcome contributors of all backgrounds and skill levels
- **Be focused** — Stay on topic in issues and PRs

## Getting Started

1. **Fork** the repository
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/agent-os.git
   cd agent-os
   ```
3. **Create a branch** for your work:
   ```bash
   git checkout -b feature/my-feature
   ```
4. **Make changes**, test thoroughly
5. **Commit** using our convention (see below)
6. **Push** to your fork and open a Pull Request

## Development Setup

### Prerequisites

- **Bash 4.0+** — All scripts are written in bash
- **jq** — JSON processing
- **Python 3.8+** — Used for data parsing and metrics
- **curl** — API interactions
- **OpenClaw** — Agent runtime ([openclaw.dev](https://openclaw.dev))
- **Paperclip** — Task coordination ([paperclip.dev](https://paperclip.dev))

### Local Testing

Scripts can be tested independently without the full stack:

```bash
# Test circuit breaker logic (reads state file)
bash src/circuit-breaker/circuit-breaker-check.sh

# Test sprint creator (dry run — no Paperclip required for logic inspection)
cat src/sprint/sprint-creator.sh | shellcheck

# Test API helper
PAPERCLIP_API_URL=http://localhost:3100 bash src/api/paperclip-api.sh health
```

### Linting

We recommend [ShellCheck](https://www.shellcheck.net/) for bash scripts:

```bash
# Install
apt install shellcheck  # or: brew install shellcheck

# Lint all scripts
find src -name '*.sh' -exec shellcheck {} \;
```

## Commit Convention

We use **Conventional Commits** (based on [conventionalcommits.org](https://www.conventionalcommits.org/)):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, whitespace (no logic change) |
| `refactor` | Code restructuring without behavior change |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Maintenance, tooling, dependencies |
| `ci` | CI/CD configuration changes |

### Scopes

| Scope | Description |
|-------|-------------|
| `sprint` | Sprint creator (`src/sprint/`) |
| `circuit-breaker` | Circuit breaker system (`src/circuit-breaker/`) |
| `coordinator` | Paperclip coordinator (`src/coordinator/`) |
| `api` | Paperclip API helper (`src/api/`) |
| `content` | Content pipeline (`src/content/`) |
| `docs` | Documentation |

### Examples

```
feat(sprint): add nightly analytics sprint type
fix(circuit-breaker): correct ratio comparison for following breaker
docs: add architecture and quick-start guides
refactor(api): extract retry logic into shared function
```

## Pull Request Process

1. **Keep it small** — One concern per PR. Large changes should be split into sequential PRs.
2. **Update docs** — If you add a component or change behavior, update the relevant documentation.
3. **Test your changes** — Run scripts locally to verify they work.
4. **Write a clear description** — Explain *what* changed and *why*. Link related issues.
5. **Pass ShellCheck** — All bash scripts should pass `shellcheck` with no errors.
6. **One review required** — At least one maintainer approval before merge.

### PR Template

```markdown
## Summary
Brief description of changes.

## Changes
- Change 1
- Change 2

## Testing
How was this tested?

## Related Issues
Closes #123
```

## Project Structure

```
agent-os/
├── src/
│   ├── api/              # Paperclip REST API wrapper
│   ├── circuit-breaker/  # Safety system (content, engagement, following)
│   ├── content/          # Content generation pipeline
│   ├── coordinator/      # Task monitoring and agent coordination
│   └── sprint/           # Sprint creation and task generation
├── docs/                 # Architecture, guides
├── examples/             # Ready-to-use configurations
├── .github/              # Issue templates, CI
└── package.json
```

## Reporting Issues

When reporting bugs, please include:

- **What happened** — The unexpected behavior
- **What you expected** — The expected behavior
- **Steps to reproduce** — How to trigger the issue
- **Environment** — OS, bash version, OpenClaw version
- **Logs** — Relevant output from `logs/` directory

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) when possible.

---

*Questions? Open a [discussion](https://github.com/agentxagi/agent-os/discussions) or reach out on [X/Twitter](https://x.com/agentxagi).*
