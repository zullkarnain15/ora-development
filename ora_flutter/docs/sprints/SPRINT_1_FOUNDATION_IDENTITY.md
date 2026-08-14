# Sprint 1 Execution Brief - Foundation, ORA Identity, and Authentication

Status: **ready for execution after explicit approval**  
Project: `D:\ORA-Development\ora_flutter`  
Behavior reference: `D:\ORA-Development\ORA`  
Architecture reference: `docs/ANDROID_TO_FLUTTER_MIGRATION_ANALYSIS.md`

## Objective

Replace the default Flutter demo with a stable ORA application foundation and complete identity gate: ORA theme/assets, root navigation, login, first-time nickname activation, session restore/expiry, and logout.

The Sprint must leave Android and iOS hosts buildable. Do not implement Quest, Guild, tracking, activity sync, or route drawing.

## Locked rules

- Android business behavior remains the parity source.
- Use Flutter Navigator and built-in `ChangeNotifier`, `ValueNotifier`, or `InheritedWidget` unless a package is separately approved.
- Use `dart:io` and `dart:convert` for the Apps Script API.
- Do not add a map, location, router, or state-management package.
- Do not expose nickname rename. The current backend only supports first activation.
- Do not modify the Android reference project.
- Keep all secrets/tokens out of logs and committed fixtures.

## Deliverables

### 1. App foundation

- Create `lib/app`, `lib/core`, `lib/shared`, and `lib/features/auth` layers.
- Add app bootstrap, root error boundary, session gate, and authenticated shell.
- Add five shell destinations: Home, Quest, Run, Guild, You. Non-Sprint screens may be explicit ORA placeholders only.
- Preserve the emphasized Run destination and Settings-without-bottom-navigation behavior.
- Remove all visible Flutter counter/demo content.

### 2. ORA design system

- Import the approved Android ORA assets and `press_start_2p.ttf`.
- Implement forest/gold color tokens and reusable typography.
- Implement lightweight shared widgets: ORA card, screen title, icon/image wrapper, pixel badge, stat line, and loading/error/empty panel.
- Retain pixel/RPG identity while supporting safe areas, text scaling, and accessibility semantics.
- Do not reproduce critical text at an unreadable fixed 8 sp size.

### 3. API foundation

- Implement one Apps Script client with explicit connect/read timeout behavior equivalent to the Android 15 s/20 s baseline.
- Support standard `{ok,data}` responses and existing successful flat-root responses.
- Normalize invalid JSON, empty responses, backend error codes, timeouts, and connection failures.
- Add a central path for `UNAUTHORIZED` and `SESSION_EXPIRED`.
- Preserve exact action and payload names for login and activation.

### 4. Authentication

- Port PIN validation: required, exactly four digits, numeric only.
- Port nickname behavior: trim, required, maximum eight-character client baseline, alphanumeric, canonical uppercase.
- Implement login branching to activation when backend nickname is blank.
- Implement nickname activation and participant/session creation.
- Store session through a `SessionStore` interface, including token, NIK, nickname, division, status, and expiry.
- Restore only a non-expired session. Clear an expired/malformed session safely.
- Logout clears the local session and returns to Login.
- Decide secure native storage versus another implementation through a documented dependency decision; do not add a package silently.

## Required tests

- PIN empty/short/long/non-numeric/valid.
- Nickname empty/whitespace/8/9 characters/alphanumeric/canonical uppercase.
- Login invalid credentials, inactive account, activation required, returning user.
- Activation success, nickname taken, invalid nickname, already activated, expired session.
- Nested success, flat success, backend error, invalid JSON, and timeout fixtures.
- Session restore before expiry, clearing after expiry, logout, and centralized expiry routing.
- Widget tests for login/activation loading, error, keyboard submission, and shell navigation.

## Acceptance criteria

- Fresh install opens the ORA Login screen.
- A valid returning user reaches the authenticated shell with the correct identity.
- A first-time user cannot enter the shell before successful nickname activation.
- An expired session always returns to Login instead of appearing as a generic offline feature error.
- ORA font, palette, crest/wordmark, cards, and bottom navigation are visibly established.
- `flutter analyze` and all Sprint tests pass.
- Android debug build passes.
- iOS build/configuration is validated on a Mac before Sprint acceptance.
- No Android reference file is changed.

## Verification commands

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Run the iOS build gate on macOS:

```bash
flutter build ios --debug --no-codesign
```

## Stop condition

Stop after the Sprint 1 acceptance report. Do not begin Sprint 2 without explicit approval.
