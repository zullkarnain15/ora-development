# ORA — OTO Runners Adventure

This private repository contains the ORA migration workspace:

- `ORA/`: Android reference implementation and Apps Script backend.
- `ora_flutter/`: shared Flutter application for Android and Web/PWA.

Generated APK/AAB files, build caches, local SDK paths, credentials, and signing keys are intentionally excluded from version control.

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
