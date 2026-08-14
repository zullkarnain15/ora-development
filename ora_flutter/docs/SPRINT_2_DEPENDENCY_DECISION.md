# Sprint 2 Dependency Decision - Local Activity Database

## Decision

Use `sqflite` with `path` for the Android/iOS runtime database and `sqflite_common_ffi` as a test-only dependency.

## Rationale

- Preserves the Android `ora.db` SQLite schema and conflict behavior without creating separate persistence rules per platform.
- Supports owner-filtered queries directly in SQL so another NIK's activities are never returned by repository methods.
- Allows a real Android-version-1 migration fixture to execute on the Windows test host.
- Keeps database details behind `ActivityStore`; Sprint 3 tracking repositories remain separate interfaces.

## Schema decision

- Database filename remains `ora.db`.
- Android table and field names remain unchanged.
- Schema version 2 preserves all version-1 activity rows and adds only `schema_metadata` plus idempotent owner indexes.
- `activityId` remains the global primary key with conflict-ignore semantics.
- Sync states remain `LOCAL_ONLY`, `PENDING`, and `SYNCED`.

No tracking, location, route, or map dependency was added.
