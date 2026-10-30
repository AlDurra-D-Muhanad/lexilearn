// Builds the app, with the version taken out of `pubspec.yaml` and passed in.
//
//   dart run tool/build.dart apk --release
//   dart run tool/build.dart appbundle --release --split-per-abi
//
// **Why this script exists.** The app-info screen shows the version, and the
// version is a fact about the app rather than a string a screen may write for
// itself. `lib/design/app_version.dart` reads it from the environment:
//
//   const String appVersion = String.fromEnvironment('APP_VERSION', …);
//
// so somebody has to pass it in, and the only place that knows the version is
// `pubspec.yaml`. This script reads it from there and hands it to
// `flutter build` as a `--dart-define`. **There is exactly one source of
// truth, and it is the manifest.**
//
// **No dependency.** `pubspec.yaml` is read with a regular expression rather
// than with a YAML parser, because the line this script needs is a plain
// `version: 2.0.2+2` at the top of the file and a YAML package would be a
// dependency the app does not otherwise need. The pattern is anchored to the
// start of a line so a `version:` inside a comment or under another key
// cannot be mistaken for it, and the script **fails loudly** when it cannot
// find the line rather than building an app with an empty version.
//
// Everything after `--` is passed through to `flutter build` untouched, so the
// ordinary flags (`--release`, `--target-platform`, `--split-per-abi`) work as
// they always did.

import 'dart:io';

/// The name of the define the app reads the version from.
///
/// The same string as `appVersionDefine` in `lib/design/app_version.dart`.
/// It is written twice because a build script and a Dart constant are two
/// different compilation units, and a test asserts that `pubspec.yaml` and
/// the constant agree — this one is the only place the two could disagree
/// silently, so it is checked by `test/design/app_version_test.dart` too.
const String defineName = 'APP_VERSION';

/// The version name out of `pubspec.yaml`, without the build number.
///
/// `2.0.2+2` becomes `2.0.2`: the `+2` is Android's `versionCode` and the
/// store's build number, not the version a person reads on the app-info
/// screen.
String versionNameOf(String pubspec) {
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw StateError(
      'pubspec.yaml has no `version: x.y.z` line, so there is no version to '
      'pass to the build. Fix the manifest rather than building an app whose '
      'about screen lies about its own version.',
    );
  }
  return match.group(1)!;
}

Future<int> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/build.dart <flutter build target> [flags…]\n'
      '   e.g. dart run tool/build.dart apk --release',
    );
    return 64;
  }

  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version = versionNameOf(pubspec);
  stdout.writeln('pubspec.yaml says the version is $version');

  final result = await Process.run(
    'flutter',
    <String>[
      'build',
      ...arguments,
      '--dart-define=$defineName=$version',
    ],
    runInShell: true,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  return result.exitCode;
}
