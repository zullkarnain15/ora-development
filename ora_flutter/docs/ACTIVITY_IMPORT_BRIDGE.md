# ORA Share Activity Bridge

## User flow

```text
Strava -> Share -> Send to ORA -> Activity Preview -> Decline / Save Activity
```

There is deliberately no import, upload, or Shortcut menu in Settings/You. `IMPORT ACTIVITY` is an internal preview route opened only after ORA receives shared content.

## Shared engine

All supported entry points normalize into `ActivitySharePayload` and use the same parser, validation, duplicate pre-check, preview, and existing `ActivityStore`/sync pipeline:

```text
Android native share --+
Android PWA share -----+-> ActivityImportInbox -> Activity Preview
iPhone Shortcut token -+                           |
                                                   +-> existing save/sync
```

Parsing order is shared text, shared URL, then screenshot OCR fallback. ORA never scrapes Strava and does not use the Strava API. The current web OCR implementation reports `OCR_NOT_AVAILABLE` when text/URL is incomplete and keeps the required preview fields editable.

## Entry routes and login resume

- iPhone Shortcut: `/#/import?t=<opaque-token>`.
- Android PWA share target: `./?share_target=1&title=...&text=...&url=...`.
- Android native: `ACTION_SEND` or `ACTION_SEND_MULTIPLE` through `ora/activity_share`.

A bare `/#/import` route is ignored. A pending share is retained through login, and web token/text launches are persisted in per-tab `sessionStorage` until preview is declined or saved.

## Temporary token backend

Apps Script provides `createImportToken`, `getImportPayload`, and `consumeImportToken`. Tokens are opaque, short-lived (600 seconds), and consumable. Hashed token metadata is stored in Script Properties; temporary payload JSON is kept in a private Drive folder. Creating or fetching a token never calls `submitActivity`.

Redeploy and authorize the Apps Script web app before publishing the official iPhone Shortcut. Run `testImportTokenLifecycle` from the Apps Script editor after authorization.

## Android PWA limitation

GitHub Pages is static and cannot receive a multipart POST share target. The installed Android PWA can therefore receive shared text and URL through its relative GET share target, but direct PWA screenshot sharing is a hosting/platform limitation. Screenshot input remains supported by Android native and the iPhone token bridge.

Feature rollback flags:

- `ACTIVITY_IMPORT_ENABLED`
- `ACTIVITY_IMPORT_WEB_ENABLED`

Production web build:

```powershell
flutter build web --release --base-href /ora-development/
```

Share Sheet visibility and cold/background/foreground delivery must be confirmed on real devices. For DECLINE, verify that no Activity or reward changes. For SAVE, verify exactly one Activity enters the existing sync flow.
