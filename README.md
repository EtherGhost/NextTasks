# NextTasks

Native but simple Ubuntu Touch client for Nextcloud Tasks.

This project follows the same Ubuntu Touch development approach as NextNotes and NextNews.

NextTasks is not affiliated with, endorsed by, or sponsored by Nextcloud GmbH or the Nextcloud project.

## Current Status

Shared Ubuntu Touch application shell is in place: hamburger/search/sync-status/avatar top bar, released-suite-style hamburger navigation, settings, language selection, about page, Online Accounts/AppArmor declarations, icons, translation scaffold, desktop dark debug support, and desktop test-account support.

Translations are available for Swedish plus AI-assisted starter translations for Danish, German, Spanish, Finnish, French, Italian, Norwegian Bokmål, Dutch, Polish, Russian, and Ukrainian. Starter translations are intended to be improved by native speakers.

The account page discovers Ubuntu Touch Nextcloud/ownCloud accounts, guides the user to allow NextTasks in OS account settings when needed, keeps the selected account while the user grants OS permission, verifies automatically after the user returns, serializes verification while running, clears stale in-memory credentials when switching accounts, ignores delayed auth/CalDAV responses from the previous account, offers contextual OS account settings prompts only when needed, and keeps technical diagnostics out of the normal UI.

CalDAV task-calendar discovery, My Tasks default filtering, task sort modes, per-list sort preferences, server-backed manual order using `X-APPLE-SORT-ORDER`, task-list sections, polished task cards with checkbox controls, status-tinted backgrounds, NextNotes-style sync badges, a Details/Notes task detail view, per-list VTODO task listing, manual task complete/open toggling, optional completed-task visibility, reopening all completed tasks in the current view, NextNotes-style multi-select bulk delete, and task move-to-list actions are implemented.

New tasks can be created from a selected list directly, or from My Tasks after choosing the target task list. The task detail view supports autosaved title, status, start date, due date, priority, progress, location, URL, tags, and notes editing, with a top-bar sync status indicator. Tags are stored in VTODO `CATEGORIES`.

A SQLite cache stores task lists, task metadata, raw VTODO data, ETags, local dirty edits, new local task drafts, pending deletes, and manual sort order per selected account. Startup is cache-first, then server refresh; local edits are saved before upload and retried on later refresh if networking fails. Task create/update/delete, bulk delete, and manual reorder now use a delayed controller-owned dirty-sync queue, so changes can sync automatically without manual refresh. Successful autosync uploads refresh the written task/ETag without forcing a full server reload. Moving a synced task to another list uses WebDAV `MOVE` and updates the local cache after server success. CalDAV list discovery now asks the server for the current user's calendar home before using the legacy username-based fallback path.

Conflicts fetch the latest server VTODO, show local/server versions, and let the user keep local changes or use the server version. Automatic merge and complete background sync are not implemented yet.

## Authentication

NextTasks will always use Ubuntu Touch Online Accounts only. Users should add a Nextcloud or ownCloud account in Ubuntu Touch System Settings > Accounts. If the selected account has not allowed NextTasks yet, the app opens a guided prompt to the OS account settings, keeps the account selected, and verifies access automatically when the user returns. Credentials are kept only in memory.

## Build

```bash
~/.local/bin/clickable build --arch amd64
~/.local/bin/clickable build --arch arm64
```

## Run

```bash
~/.local/bin/clickable desktop --arch amd64
~/.local/bin/clickable script desktop-dark
scripts/desktop-test.sh
```

`scripts/desktop-test.sh` reads `.env.test.local` if present, otherwise the existing sibling NextNews/NextNotes test env files. It maps the test account into `NEXTTASKS_*` variables at runtime and does not commit credentials.

## Test

```bash
~/.local/bin/clickable script test
```

## License

MIT License

Copyright (c) 2026 Etherghost
