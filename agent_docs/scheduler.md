# Scheduler (LaunchAgent Cron)

## Overview
The app can schedule automatic digest runs via macOS `launchd`. A LaunchAgent plist is written to disk and loaded/unloaded with `launchctl`.

## Components

| File | Role |
|------|------|
| `flow/Services/SchedulerService.swift` | Manages plist lifecycle (install/uninstall/update) and holds schedule state |
| `flow/Views/Schedule/ScheduleSettingsView.swift` | Popover UI for adding/removing time entries and toggling the schedule |
| `flow/ContentView.swift` | Toolbar clock button opens the popover |
| `flow/flowApp.swift` | Creates `SchedulerService` and injects it via `.environment()` |
| `run_digests.sh` | Wrapper script executed by launchd; runs both Python scripts in parallel |

## How It Works

1. **Install** (`install()`): writes `run_digests.sh`, builds a plist dict with `StartCalendarInterval` (array of `{Hour, Minute}` dicts), writes it to `~/Library/LaunchAgents/`, runs `launchctl load`.
2. **Uninstall** (`uninstall()`): runs `launchctl unload`, deletes the plist file.
3. **Update** (`updateSchedule(with:)`): if currently scheduled, does uninstall then install with new entries.
4. **Init**: reads the existing plist back on launch (`loadScheduleFromPlist`). Supports both single-dict and array formats for backward compat.

## Key Paths
- **Plist**: `~/Library/LaunchAgents/com.berkaycit.flow.digest.plist`
- **Logs**: `<projectDir>/logs/digest-stdout.log`, `<projectDir>/logs/digest-stderr.log`
- **Wrapper script**: `run_digests.sh` (project root)

## Data Model

`ScheduleEntry` -- simple struct with `hour` and `minute`. Equality and hashing are based on these two fields (not the UUID). Default entries: 06:00, 12:00, 18:00.

`SchedulerService` (`@Observable`) -- holds `isScheduled: Bool` and `entries: [ScheduleEntry]`.

## UI Flow
Toolbar clock icon (filled when active) -> `ScheduleSettingsView` popover:
- Toggle to activate/deactivate the LaunchAgent
- List of current time entries with remove buttons
- Hour/minute pickers to add new entries (5-min increments, duplicates blocked)
- "Apply" button calls `updateSchedule(with:)` and dismisses
