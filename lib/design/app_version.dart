/// The app's version, and the one place it is written down in Dart.
///
/// **A compile-time constant, injected at build time.** The value comes from
/// `pubspec.yaml` and is passed in by `tool/build.dart` as
/// `--dart-define=APP_VERSION=…`, so there is exactly one source of truth:
/// the manifest. A screen that wrote the version out for itself would be a
/// second copy of a fact that changes, and the two would drift.
///
/// **The default is the safety net, and it is pinned by a test.** A `flutter
/// test` run has no `--dart-define`, so the constant falls back to
/// [defaultVersion]. `test/design/app_version_test.dart` reads
/// `pubspec.yaml` off disk and fails if the two disagree — which is what
/// stops somebody bumping the manifest and forgetting the constant.
///
/// The version *name* only: `pubspec.yaml` carries `2.0.0+1`, where `+1` is
/// the build number Android uses as `versionCode` and the store, not the
/// version a user reads.
library;

/// The app's version, as the app-info screen shows it.
class AppVersion {
  const AppVersion._();

  /// The name of the `--dart-define` the build script passes.
  ///
  /// Written down because the build script and the constant have to agree, and
  /// a string that appears in two files is a string that can drift.
  static const String define = 'APP_VERSION';

  /// The version shown on the app-info screen.
  ///
  /// **Read from the environment, with a default that a test pins.** The
  /// default is what a `flutter test` run sees, and it must match
  /// `pubspec.yaml`'s version name.
  static const String version = String.fromEnvironment(
    define,
    defaultValue: '2.0.0',
  );

  /// The version this source tree falls back to.
  ///
  /// Named so the test can read it rather than write the string again.
  static const String defaultVersion = '2.0.0';
}
