# Flow

**Your YouTube, Hacker News, and Reddit feeds — triaged by Claude, read in a native macOS app.**

You subscribe to 60 channels. You open HN three times a day. You lurk in five subreddits. You see everything and read nothing.

Flow fixes that.

On a schedule you set, Flow pulls the new stuff from every source, hands it to Claude for triage — `High` / `Medium` / `Low` priority plus a one-line summary — and drops it into a fast SwiftUI app. Sources and a calendar on the left, the list in the middle, a reading pane on the right.

One click sends any item to NotebookLM. Audio Overview generation starts in the background; the notebook opens in your browser.

## What's in the box

- **Sources** — YouTube channels (RSS), Hacker News front page (Algolia), your subreddits
- **Triage** — Claude CLI with `--json-schema` structured output; priority and summary per item
- **Storage** — local SQLite (`~/Library/Application Support/Flow/flow.db`)
- **App** — SwiftUI + GRDB, live updates via `ValueObservation`
- **Scheduler** — macOS `launchd` configured from inside the app; never touch the terminal
- **NotebookLM** — one-click "send to NotebookLM" + Audio Overview; URL is cached so the next click opens instantly

## Why it's different

- **Local-first.** The DB is a file on your disk. Your data doesn't leave the machine except for the Claude triage call.
- **Native.** No Electron. No browser tab. Cmd+Tab and it's there.
- **Hackable.** ~50 lines of Python per source. Add a new source in an afternoon.

## Quick start

```bash
# Dependencies
pip3 install -r python-yt-digest/requirements.txt
pip3 install -r python-hn-digest/requirements.txt
pip3 install -r python-reddit-digest/requirements.txt

# Configure your sources
$EDITOR python-yt-digest/channels.json
$EDITOR python-reddit-digest/subreddits.json

# Run triage once
./run_digests.sh

# Open and build the Mac app (Cmd+B)
open flow.xcodeproj
```

Once the app is running, use the clock icon in the top bar to set automatic triage times.

## Requirements

- macOS + Xcode
- Python 3.10+
- [Claude CLI](https://docs.claude.com/en/docs/claude-code/overview) — `claude` command on PATH
- Optional: a Chrome session signed into `notebooklm.google.com` for the NotebookLM export

## Architecture

Details in `agent_docs/`:
- `architecture.md` — data flow, DB schema, key paths
- `build.md` — build & run commands
- `scheduler.md` — LaunchAgent / cron lifecycle
- `notebooklm.md` — NotebookLM integration and auth
