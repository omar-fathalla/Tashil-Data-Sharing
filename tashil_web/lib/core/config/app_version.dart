/// Deploy version injected at build time by `scripts/deploy_web.sh`
/// via `--dart-define=APP_VERSION=<n>`. Local runs show 'dev'.
class AppVersion {
  AppVersion._();

  static const String raw = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// Label shown in the sidebar, e.g. 'v3' or 'dev'.
  static String get label => labelFor(raw);

  static String labelFor(String value) =>
      int.tryParse(value) != null ? 'v$value' : value;
}
