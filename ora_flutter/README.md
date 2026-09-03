# ORA Flutter

Production client for OTO Runners Adventure. Supported targets are Android and
Web/PWA.

## Local development

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

For Android development, use a physical device or emulator with API 26 or
newer. Local SDK paths, signing keys, generated builds, and credentials must not
be committed.

## Production PWA

```sh
flutter build web --release --base-href /ora-development/
```

Deployment is handled by the repository-level GitHub Pages workflow.
