# Architecture

## Data Flow
```
YouTube RSS / HN Algolia API
        |
  Python scripts (fetch + extract content)
        |
  Claude CLI (--json-schema structured triage)
        |
  SQLite (~/Library/Application Support/Flow/flow.db)
        |
  SwiftUI app (GRDB ValueObservation -> reactive UI)
```

## Shared Database Contract
The SQLite schema is defined identically in **three places** that must stay in sync:
- `python-yt-digest/yt_digest.py` -> `ensure_schema()`
- `python-hn-digest/hn_digest.py` -> `ensure_schema()`
- `flow/Services/DatabaseService.swift` -> GRDB `DatabaseMigrator`

All use `CREATE TABLE IF NOT EXISTS` / migrations, so they coexist safely. But adding a column requires editing all three.

## Swift App (flow/)
- **Concurrency model**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` -- all types default to MainActor. Mark methods `nonisolated` explicitly for off-main work.
- **Database**: GRDB.swift (v7+) with `DatabasePool` (WAL mode). `ValueObservation` provides live updates when Python scripts write new data.
- **State**: `@Observable` classes injected via `.environment()`. `DigestViewModel` is the main state holder. `ScriptRunnerService` manages subprocess execution.
- **Views**: `NavigationSplitView` with sidebar (source picker + calendar), item list, and detail panel.
- **File sync**: The project uses `PBXFileSystemSynchronizedRootGroup` -- files added to `flow/` are automatically included in the build. No manual pbxproj edits needed for new Swift files.

## Python Scripts
Both scripts follow the same pattern: fetch -> extract content -> build prompt -> Claude CLI triage (with `--json-schema` for guaranteed structured output) -> write to SQLite -> print summary to stdout/stderr.

Deduplication uses the DB's `UNIQUE(source, external_id)` constraint with `INSERT OR IGNORE`.

## Priority Sort
Priority values in the DB are strings (`high`, `medium`, `low`). Alphabetical sort gives wrong order. The Swift app uses a SQL `CASE` expression for correct ordering: high -> medium -> low.

## Key Paths
- **Database**: `~/Library/Application Support/Flow/flow.db`
- **LaunchAgent**: `~/Library/LaunchAgents/com.berkaycit.flow.digest.plist`
- **YT channels config**: `python-yt-digest/channels.json`
- **App sandbox**: Disabled (needed for Process execution and file system access)
