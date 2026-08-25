abstract final class ActivityImportConfig {
  static const enabled = bool.fromEnvironment(
    'ACTIVITY_IMPORT_ENABLED',
    defaultValue: true,
  );
  static const webEnabled = bool.fromEnvironment(
    'ACTIVITY_IMPORT_WEB_ENABLED',
    defaultValue: true,
  );
}
