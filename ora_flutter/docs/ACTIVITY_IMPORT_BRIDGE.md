# ORA Activity Import Bridge

## Architecture

All entry points normalize into `ActivitySharePayload` and use the same parser, validator, duplicate pre-check, preview, and existing activity save/sync pipeline:

```text
Android native share ─┐
Android PWA share ────┼─> ActivityImportInbox -> ORA IMPORT -> existing ActivityStore/sync
iPhone Shortcut token ┤
Manual screenshot ────┘
```

The parser detects the source and extracts portable URL/text data first. Image handling is an OCR abstraction/fallback: the current PWA build reports `OCR_NOT_AVAILABLE` and keeps distance, duration, date, and time editable. It does not add a heavy browser OCR dependency.

## Routes and resume behavior

- Apple Shortcut entry: `/#/import?t=<opaque-token>`.
- Android PWA GET share target: `./?share_target=1&title=...&text=...&url=...`.
- Manual entry: **You / Settings → SHARE ACTIVITY → IMPORT ACTIVITY**.

The pending launch is persisted in web `sessionStorage` as `ora_pending_activity_import`. Authentication remains authoritative; a logged-out user sees login first, then the authenticated app consumes the pending import and opens its preview. Reloading the same browser tab also preserves it.

## Temporary backend payload

Apps Script actions:

- `createImportToken`: anonymous POST of share input; returns an unpredictable opaque token.
- `getImportPayload`: fetches the private temporary payload for preview.
- `consumeImportToken`: deletes the Drive payload and leaves a short-lived `CONSUMED` marker.

TTL is 600 seconds. Script Properties store only hashed token metadata; payload JSON is stored in a private Drive folder. Temporary input never calls `submitActivity`. The backend deployment must be updated and authorized for Drive access before the bridge is live. Run `testImportTokenLifecycle` from the Apps Script editor after deployment authorization.

## PWA share-target limitation

The current ORA host is static GitHub Pages. A manifest `POST`/`multipart/form-data` file share target requires a request handler at the target URL, which GitHub Pages cannot provide. The manifest therefore uses a relative `GET` target for text and URL. This keeps the PWA installable and base-href safe, but Android PWA image sharing is a platform/hosting limitation in this deployment. Users can select a screenshot inside ORA or use the token bridge.

## Build configuration

Feature flags default to enabled:

- `ACTIVITY_IMPORT_ENABLED`
- `ACTIVITY_IMPORT_WEB_ENABLED`
- `IOS_SHORTCUT_IMPORT_ENABLED`

The official Shortcut distribution link is supplied as `ORA_IOS_SHORTCUT_URL`. The production web command remains:

```powershell
flutter build web --release --base-href /ora-development/ `
  --dart-define=ORA_IOS_SHORTCUT_URL=https://www.icloud.com/shortcuts/REPLACE_ME
```

To disable an entry point for rollback, pass the corresponding flag as `false` with `--dart-define`.

## Device acceptance checks

Android PWA and iPhone Share Sheet behavior must be verified on real installed PWAs; a desktop build cannot prove that the OS lists the share target. For both paths, verify DECLINE creates no backend Activity, then repeat with SAVE and verify exactly one Activity enters the existing sync pipeline. Native Android should additionally be tested with both Strava text and image shares.
