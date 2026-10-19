import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_installer.dart';

/// The first-launch copy of the dictionary, and the rules that make it safe.
///
/// **A half-written database must never be mistaken for a good one.** That is
/// the whole of the safety argument, and it is tested here against a real
/// file system rather than against a mock: the bytes are written, the
/// interruption is simulated, and the file that is left behind is inspected.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lexilearn_dictionary_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// A fake asset: [bytes] of deterministic content.
  Future<ByteData> Function(String key) loader(List<int> bytes) =>
      (String key) async => ByteData.view(Uint8List.fromList(bytes).buffer);

  group('a first launch', () {
    test('the file lands on the device, byte for byte', () async {
      final target = '${root.path}/dictionary/en_ar.db';
      final bytes = List<int>.generate(200000, (i) => i % 251);
      final progress = <DictionaryInstallProgress>[];

      final outcome = await DictionaryInstaller().install(
        load: loader(bytes),
        targetPath: target,
        assetPath: 'assets/dictionary/en_ar.db',
        expectedBytes: bytes.length,
        onProgress: progress.add,
      );

      expect(outcome, DictionaryInstallOutcome.installed);
      final file = File(target);
      expect(await file.exists(), isTrue);
      expect(await file.length(), bytes.length);
      expect(await file.readAsBytes(), bytes,
          reason: 'the copy has to be the asset, not a prefix of it');
    });

    test('the progress is reported, and it ends at one', () async {
      final target = '${root.path}/dictionary/en_ar.db';
      final bytes = List<int>.generate(600000, (i) => i % 251);
      final progress = <DictionaryInstallProgress>[];

      await DictionaryInstaller().install(
        load: loader(bytes),
        targetPath: target,
        assetPath: 'assets/dictionary/en_ar.db',
        expectedBytes: bytes.length,
        onProgress: progress.add,
      );

      expect(progress, isNotEmpty);
      expect(progress.first.bytesWritten, 0);
      expect(progress.last.fraction, 1.0);
      // **Monotonic**, because a progress bar that goes backwards is a bar
      // nobody trusts.
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].bytesWritten,
            greaterThanOrEqualTo(progress[i - 1].bytesWritten));
      }
    });

    test('the version marker is written beside it', () async {
      final target = '${root.path}/dictionary/en_ar.db';
      final bytes = List<int>.generate(1000, (i) => i % 251);
      await DictionaryInstaller().install(
        load: loader(bytes),
        targetPath: target,
        assetPath: 'assets/dictionary/en_ar.db',
        expectedBytes: bytes.length,
      );
      final marker = File('$target${DictionaryInstaller.markerSuffix}');
      expect(await marker.exists(), isTrue);
      expect((await marker.readAsString()).trim(),
          DictionaryInstaller.expectedVersion);
    });
  });

  group('a second launch', () {
    test('the copy is skipped', () async {
      final target = '${root.path}/dictionary/en_ar.db';
      final bytes = List<int>.generate(1000, (i) => i % 251);
      final installer = DictionaryInstaller();

      await installer.install(
        load: loader(bytes),
        targetPath: target,
        assetPath: 'assets/dictionary/en_ar.db',
        expectedBytes: bytes.length,
      );
      // A loader that would fail the test if it were called: the second
      // launch must not read the asset at all.
      final outcome = await installer.install(
        load: (String key) async => fail('the asset must not be read twice'),
        targetPath: target,
        assetPath: 'assets/dictionary/en_ar.db',
        expectedBytes: bytes.length,
      );
      expect(outcome, DictionaryInstallOutcome.alreadyInstalled);
    });

    test('a file of the wrong size is copied again', () async {
      final target = '${root.path}/dictionary/en_ar.db';
      await File(target).parent.create(recursive: true);
      await File(target).writeAsBytes(<int>[1, 2, 3]);
      await File('$target${DictionaryInstaller.markerSuffix}')
          .writeAsString(DictionaryInstaller.expectedVersion);

      final bytes = List<int>.generate(1000, (i) => i % 251);
      final outcome = await DictionaryInstaller().install(
        load: loader(bytes),
        targetPath: target,
        assetPath: 'assets/dictionary/en_ar.db',
        expectedBytes: bytes.length,
      );
      expect(outcome, DictionaryInstallOutcome.installed);
      expect(await File(target).readAsBytes(), bytes);
    });

    test('a file with no marker is copied again', () async {
      // **The interruption this covers.** A copy that was interrupted between
      // the rename and the marker leaves a file of the right size and no
      // marker. Without the marker the file is not trusted.
      final target = '${root.path}/dictionary/en_ar.db';
      final bytes = List<int>.generate(1000, (i) => i % 251);
      await File(target).parent.create(recursive: true);
      await File(target).writeAsBytes(bytes);

      final outcome = await DictionaryInstaller().install(
        load: loader(bytes),
        targetPath: target,
        assetPath: 'assets/dictionary/en_ar.db',
        expectedBytes: bytes.length,
      );
      expect(outcome, DictionaryInstallOutcome.installed);
    });
  });

  group('an interruption', () {
    test('a partial file from a dead run is thrown away, not continued',
        () async {
      final target = '${root.path}/dictionary/en_ar.db';
      final partial = File('$target${DictionaryInstaller.partialSuffix}');
      await partial.parent.create(recursive: true);
      await partial.writeAsBytes(<int>[9, 9, 9, 9]);

      final bytes = List<int>.generate(1000, (i) => i % 251);
      await DictionaryInstaller().install(
        load: loader(bytes),
        targetPath: target,
        assetPath: 'assets/dictionary/en_ar.db',
        expectedBytes: bytes.length,
      );

      expect(await File(target).readAsBytes(), bytes,
          reason: 'the dead run\'s bytes must not be in the file');
      expect(await partial.exists(), isFalse,
          reason: 'the partial file is renamed into place, not left behind');
    });

    test('a failure while reading the asset leaves no file behind', () async {
      final target = '${root.path}/dictionary/en_ar.db';
      await expectLater(
        DictionaryInstaller().install(
          load: (String key) async => throw StateError('the bundle is broken'),
          targetPath: target,
          assetPath: 'assets/dictionary/en_ar.db',
          expectedBytes: 1000,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await File(target).exists(), isFalse,
          reason: 'a failed copy must not leave a dictionary-shaped file');
    });

    test('a bundle of the wrong size is refused', () async {
      final target = '${root.path}/dictionary/en_ar.db';
      await expectLater(
        DictionaryInstaller().install(
          load: loader(<int>[1, 2, 3]),
          targetPath: target,
          assetPath: 'assets/dictionary/en_ar.db',
          expectedBytes: 1000,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await File(target).exists(), isFalse);
    });

    test('the file at the real path is never a partial one', () async {
      // **The atomicity, watched rather than asserted.** The bytes are
      // written to a `.part` file and only become the dictionary by a
      // rename, so the file at the real path either does not exist or is
      // complete. There is no instant in which it holds half of the copy.
      //
      // **The observation is synchronous.** `onProgress` is a `void`
      // callback, so an `async` closure inside it would be fire-and-forget
      // and its `await` would never complete inside the test's fake-async
      // zone — the observer would see nothing and the assertion below would
      // pass on an empty set. `lengthSync` is the only way to look at the
      // file from inside a `void` callback.
      final target = '${root.path}/dictionary/en_ar.db';
      final bytes = List<int>.generate(400000, (i) => i % 251);
      final seen = <int>{};
      await DictionaryInstaller().install(
        load: loader(bytes),
        targetPath: target,
        assetPath: 'assets/dictionary/en_ar.db',
        expectedBytes: bytes.length,
        onProgress: (_) {
          if (File(target).existsSync()) {
            seen.add(File(target).lengthSync());
          }
        },
      );
      // Whatever the observer saw, the file was never a short one.
      for (final length in seen) {
        expect(length, bytes.length);
      }
      expect(seen, isNotEmpty,
          reason: 'the observer has to have seen the file at least once, or '
              'the assertion above proved nothing');
    });
  });
}
