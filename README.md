# ORA — OTO Runners Adventure

Production monorepo for ORA:

- `ORA/backend/`: Google Apps Script backend and its Node regression tests.
- `ora_flutter/`: Flutter application for Android and Web/PWA.
- `.github/workflows/deploy-pwa.yml`: validation and GitHub Pages deployment.

Legacy Android source, unsupported Flutter platform scaffolds, generated builds,
local workspaces, credentials, and signing keys are intentionally excluded from
version control.

## Validation

Run backend regression tests from the repository root:

```sh
node ORA/backend/shared_activity_import_test.cjs
node ORA/backend/strava_sync_test.cjs
```

Run Flutter validation from `ora_flutter/`:

```sh
flutter pub get
flutter analyze
flutter test
```

## Web/PWA development

Run locally from `ora_flutter/`:

```sh
flutter pub get
flutter run -d chrome
```

Create the GitHub Pages production build:

```sh
flutter build web --release --base-href /ora-development/
```

Deployment uses `.github/workflows/deploy-pwa.yml`. It can be run manually once
the workflow exists on the default branch, or automatically by pushing reviewed
code to the dedicated `pwa-pages` branch. After setting **Settings → Pages →
Source** to **GitHub Actions**, the expected URL is
`https://zullkarnain15.github.io/ora-development/`.

Browser and iOS background GPS are not guaranteed. Locking the screen can stop
location callbacks; keep ORA visible during a Web run for best accuracy.

Never put PINs, tokens, API secrets, signing material, or other credentials in
Flutter Web source, build arguments, GitHub Pages, or committed configuration.

## Backend valid-run configuration

`TOTAL_RUNS` counts unique completed activities that meet
`MIN_DISTANCE_VALID_RUN_KM`. The backend fallback is `1.0` km when this Config
key is missing, blank, non-numeric, zero, or negative. This setting is separate
from `MIN_DISTANCE_XP_KM`; changing the XP eligibility threshold does not change
which activities count toward `TOTAL_RUNS`.

Run `setupValidRunConfig()` once from the bound Apps Script editor to add or
repair the Config row. It preserves an existing positive value and documents it
in the sheet as: "Jarak minimum agar satu activity dianggap sebagai valid run
untuk aturan berbasis jumlah run. Contoh: 1.0 = minimum 1 km."
