# NotebookLM Integration

One-click export of digest items (YouTube videos, HN articles) to Google NotebookLM notebooks.

Uses [notebooklm-py](https://github.com/teng-lin/notebooklm-py) (unofficial Python API for consumer NotebookLM). There is no official consumer API -- the Enterprise API requires a GCP organization + paid licensing.

## How It Works

```
User clicks "NotebookLM" button in DetailView
        |
NotebookLMService (Swift)
        |
   [cached notebook_url in DB?] --yes--> open URL in browser (no Python)
        |
   [venv exists?] --no--> setup.sh (creates venv, installs deps)
        |
   [auth exists?] --no--> exit code 2 -> UI shows "Cookie'leri Oku"
        |                                        |
        |                               login_notebooklm.py
        |                         (reads cookies from Chrome via pycookiecheat)
        |                                        |
        |                               ~/.notebooklm/storage_state.json
        |
   open_in_notebooklm.py
        |
   notebooklm-py creates notebook + adds URL source
        |
   Notebook URL printed to stdout + flushed
        |
   Swift reads first line via readabilityHandler, opens browser immediately
        |
   Audio Overview generation starts (fire-and-forget)
        |
   Swift saves notebook URL to DB (notebook_url column)
        |
   Process continues in background until audio generation finishes
```

## File Layout

| File | Purpose |
|------|---------|
| `flow/Services/NotebookLMService.swift` | `@Observable` service, runs Python scripts via `Process`, caches notebook URLs |
| `flow/Services/DatabaseService.swift` | `saveNotebookURL(itemId:url:)` for caching; v3 migration adds `notebook_url` column |
| `flow/Models/DigestItem.swift` | `notebookUrl: String?` property mapped to `notebook_url` column |
| `flow/Views/Detail/DetailView.swift` | Button + status UI (`notebookLMButton`, `notebookLMStatusView`) |
| `python-notebooklm/open_in_notebooklm.py` | Creates notebook, adds source, prints URL, triggers Audio Overview |
| `python-notebooklm/login_notebooklm.py` | Extracts Chrome cookies via `pycookiecheat`, saves as `storage_state.json` |
| `python-notebooklm/setup.sh` | Auto-creates venv with Python 3.10+, installs `notebooklm-py` + `pycookiecheat` |
| `python-notebooklm/requirements.txt` | `notebooklm-py`, `pycookiecheat` |
| `python-notebooklm/.venv/` | Isolated Python 3.12 venv (gitignored, auto-created by `setup.sh`) |

## Authentication

Consumer NotebookLM has no OAuth/API key flow. Authentication works through Google session cookies:

1. User must be logged into `notebooklm.google.com` in Chrome
2. `login_notebooklm.py` reads cookies directly from Chrome's local SQLite database using `pycookiecheat` (no Playwright, no separate browser window)
3. Cookies are saved to `~/.notebooklm/storage_state.json` in Playwright format (what `notebooklm-py` expects)
4. Google sessions expire after 1-2 weeks -- user needs to click "Cookie'leri Oku" again when this happens

## Exit Code Contract (Python -> Swift)

| Exit code | Meaning | Swift status |
|-----------|---------|-------------|
| 0 | Success (notebook URL on stdout) | `.done(notebookURL:)` |
| 1 | General error (message on stderr) | `.error(String)` |
| 2 | Auth missing or expired | `.authRequired` |

## URL Cache

Notebook URLs are persisted in the `notebook_url` column of `digest_items` (added in DB migration v3). On button click:

1. `NotebookLMService.openInNotebookLM` checks `db.fetchItem(id:)` for a cached URL
2. If found, opens the URL directly in the browser -- no Python script runs
3. If not found, runs `open_in_notebooklm.py`, saves the returned URL via `db.saveNotebookURL(itemId:url:)`

Python `ensure_schema` in both `yt_digest.py` and `hn_digest.py` also adds the `notebook_url` column.

## Audio Overview

On first notebook creation, `open_in_notebooklm.py` triggers Audio Overview generation via `client.artifacts.generate_audio(nb.id)` after printing the notebook URL. This is fire-and-forget: the URL is flushed to stdout immediately so Swift can open the browser without waiting. Audio generation failure is silently ignored (notebook is still usable).

## NotebookLMService Status Enum

```
idle -> running -> done(notebookURL)
  |        |
  |        +----> error(String)
  |        +----> authRequired
  |
  +---> settingUp (venv creation) -> running / error
  +---> loggingIn (cookie read) -> idle / error
```

`Status.isBusy` returns `true` for `settingUp`, `running`, `loggingIn` -- used by both the service guards and the UI.

## Auto-Setup

On first use, `NotebookLMService` checks if `.venv/bin/python3` exists. If not, it runs `setup.sh` which:

1. Searches for Python 3.10+ (`python3.12`, `python3.13`, `python3.11`, `python3.10`, then `python3`)
2. Creates a venv at `python-notebooklm/.venv/`
3. Installs `notebooklm-py` and `pycookiecheat` via pip

The check result is cached (`venvVerified` flag) so `fileExists` only runs once per app session.

## Fragility Notes

- `notebooklm-py` uses undocumented Google RPC endpoints -- can break anytime Google changes their frontend
- `pycookiecheat` depends on Chrome's cookie storage format -- Chrome keyring changes can break it
- Session cookies expire every 1-2 weeks
