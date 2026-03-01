# CLAUDE.md

Flow: macOS digest viewer. YouTube + Hacker News -> Claude CLI triage -> SQLite -> SwiftUI app.

## When to Read Agent Docs

| Task | Read |
|------|------|
| Architecture, data flow, DB schema, key paths | `agent_docs/architecture.md` |
| Build commands, run scripts, dependencies | `agent_docs/build.md` |
| LaunchAgent scheduler (cron), plist lifecycle, UI | `agent_docs/scheduler.md` |

## Rules

### Think Before Coding
- State assumptions explicitly; if uncertain, use the `AskUserQuestion` tool rather than guess
- When ambiguity exists, present multiple interpretations via `AskUserQuestion` -- don't pick silently
- Push back if a simpler approach exists; stop and ask via `AskUserQuestion` when confused

### Simplicity First
- No features, abstractions, or error handling beyond what was asked
- No speculative "flexibility" or "configurability"
- If 200 lines could be 50, rewrite it
- Only create an abstraction if it's actually needed

### Surgical Changes
- Touch only what you must; don't "improve" adjacent code, comments, or formatting
- Match existing style, even if you'd do it differently

### Goal-Driven Execution
- Define verifiable success criteria before implementing
- Write or run tests first to confirm the change works
- Every action should trace back to the user's stated goal

### General
- ALWAYS read and understand relevant files before proposing edits
- Before writing new code, check for existing related methods/classes and reuse them
- Prefer clear function/variable names over inline comments
- Don't use emojis

## Bash Guidelines

- Do NOT pipe output through `head`, `tail`, `less`, or `more`
- Do NOT use `| head -n X` or `| tail -n X` to truncate output
- Run commands directly without pipes when possible
- Use command-specific flags to limit output (e.g., `git log -n 10` instead of `git log | head -10`)
