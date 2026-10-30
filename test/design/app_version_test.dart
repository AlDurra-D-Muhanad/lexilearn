import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/app_version.dart';

import '../../tool/build.dart' as build;

/// The app's version, and the manifest it is read from.
///
/// **The point of the whole mechanism.** The app-info screen shows
/// `AppVersion.version`, which is a compile-time constant read out of the
/// environment; `tool/build.dart` fills that environment in from
/// `pubspec.yaml`. So there is exactly one copy of the version — the manifest
/// — and the screen cannot drift from it.
///
/// **These tests are what makes that true.** A `flutter test` run has no
/// `--dart-define`, so the constant falls back to its default, and the default
/// has to be the manifest's version. If somebody bumps `pubspec.yaml` and
/// forgets the default, this file goes red; and if somebody "fixes" the
/// default without bumping the manifest, it goes red the other way.
void main() {
  /// The manifest, read from disk.
  ///
  /// **Off disk and not from a constant**, because the manifest is the thing
  /// the test is about: a copy of the version inside the test would agree with
  /// itself and prove nothing.
  final String pubspec = File('pubspec.yaml').readAsStringSync();

  /// The version *name* out of the manifest: `2.0.2` out of `2.0.2+2`.
  ///
  /// The `+1` is Android's `versionCode` and the store's build number, not the
  /// version a person reads on the about screen, so it is not part of the
  /// name.
  final RegExpMatch? manifest = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$',
    multiLine: true,
  ).firstMatch(pubspec);

  test('the manifest carries a version, and the test found it', () {
    expect(manifest, isNotNull,
        reason: 'pubspec.yaml has no `version: x.y.z` line, so there is no '
            'version for the app to show');
  });

  test('the version the app shows is the manifest\'s version', () {
    expect(AppVersion.version, manifest!.group(1),
        reason: 'the app-info screen shows ${AppVersion.version} and the '
            'manifest says ${manifest.group(1)}; the two must be the same '
            'fact');
  });

  test('the fallback the tests see is the manifest\'s version', () {
    // **The safety net, pinned.** `tool/build.dart` passes the manifest's
    // version in at build time; this is what a run with no `--dart-define`
    // sees, and it has to be the same number or the drift is invisible until
    // a build.
    expect(AppVersion.defaultVersion, manifest!.group(1));
  });

  test('the version is 2.0.2', () {
    // **The user's own figure.** The app is 2.0.2, and this says so in a
    // place that goes red if it is ever changed by accident.
    expect(AppVersion.version, '2.0.2');
    expect(manifest!.group(1), '2.0.2');
  });

  test('the build script reads the same manifest, and the same version', () {
    // **The two ends of the seam.** `tool/build.dart` parses `pubspec.yaml`
    // with its own pattern, so the pattern is checked here against the real
    // manifest: if the two parsers ever disagree, one of them is wrong and
    // this says which.
    //
    // **The script's own function, imported rather than copied.** A copy of
    // the pattern would be a second copy of the rule — which is exactly what
    // `docs/engineering-standards.md` §1 is about — and a copy agrees with
    // itself and proves nothing.
    expect(build.versionNameOf(pubspec), manifest!.group(1));
  });
}
