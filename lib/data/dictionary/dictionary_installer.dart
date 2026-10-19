import 'dart:io';
import 'dart:typed_data';

import 'package:lexilearn/data/dictionary/dictionary_artifact.dart';

/// How far the first-launch copy has got.
final class DictionaryInstallProgress {
  const DictionaryInstallProgress({
    required this.bytesWritten,
    required this.totalBytes,
  });

  /// How many bytes are on disk.
  final int bytesWritten;

  /// How many bytes there will be.
  final int totalBytes;

  /// The fraction done, between 0 and 1.
  double get fraction =>
      totalBytes <= 0 ? 0 : (bytesWritten / totalBytes).clamp(0.0, 1.0);

  @override
  String toString() => 'DictionaryInstallProgress($bytesWritten/$totalBytes)';
}

/// What one installation did.
enum DictionaryInstallOutcome {
  /// The dictionary was already on disk and was correct.
  alreadyInstalled,

  /// The dictionary was copied onto the device.
  installed,
}

/// The first-launch copy of the dictionary, and the rules that make it safe.
///
/// **Three properties, and each one is a failure the brief names.**
///
/// * **It happens off the UI path.** [install] is asynchronous throughout and
///   every step yields, so the first frame is never waiting on 26 MB. The
///   caller fires it and forgets it; the app opens, navigates and shows the
///   home screen while it runs.
/// * **A half-written database is never mistaken for a good one.** The bytes
///   are written to a `.part` file and only ever become the dictionary by an
///   atomic rename, so the file at the real path is either absent or
///   complete. A **version marker** is written beside it, and the check that
///   decides "already installed" requires the marker *and* the right length:
///   an interrupted copy leaves no marker, so the next launch copies again
///   rather than opening a truncated file.
/// * **It reports progress.** Every chunk written updates the progress, and
///   the app shows it.
class DictionaryInstaller {
  const DictionaryInstaller();

  /// The suffix of the file the bytes are written to first.
  static const String partialSuffix = '.part';

  /// The suffix of the file that records **which** dictionary is installed.
  static const String markerSuffix = '.version';

  /// The version this build of the app expects.
  ///
  /// **The artefact's own SHA-256**, read out of the generated
  /// `dictionary_artifact.dart` rather than typed by hand. A build that
  /// shipped a different database and forgot to change the number would
  /// otherwise keep the old copy on every device forever.
  static const String expectedVersion = dictionaryArtifactSha256;

  /// Copies the dictionary onto the device, if it is not already there.
  ///
  /// [load] reads the asset out of the bundle and [targetPath] is where the
  /// finished file has to live. [onProgress] is called as the bytes land.
  ///
  /// **The copy is skipped when it is already correct.** The expected size and
  /// the expected version both come from the generated constants, so the check
  /// is against the artefact itself and not against a number somebody typed. A
  /// 26 MB copy on every launch would be indefensible; a copy only when the
  /// file is missing or the wrong build is one copy per app version.
  Future<DictionaryInstallOutcome> install({
    required Future<ByteData> Function(String key) load,
    required String targetPath,
    required String assetPath,
    int expectedBytes = dictionaryArtifactBytes,
    void Function(DictionaryInstallProgress progress)? onProgress,
  }) async {
    final target = File(targetPath);
    final marker = File('$targetPath$markerSuffix');
    final partial = File('$targetPath$partialSuffix');

    if (await _isAlreadyInstalled(
      target: target,
      marker: marker,
      expectedBytes: expectedBytes,
    )) {
      onProgress?.call(DictionaryInstallProgress(
        bytesWritten: expectedBytes,
        totalBytes: expectedBytes,
      ));
      return DictionaryInstallOutcome.alreadyInstalled;
    }

    // **A partial file from an interrupted copy is thrown away, not
    // continued.** Continuing it would mean the file on disk is a mixture of
    // two bundles, and nothing downstream could tell.
    if (await partial.exists()) await partial.delete();

    final data = await load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length != expectedBytes) {
      throw StateError(
        'the bundled dictionary asset is ${bytes.length} bytes, and the build '
        'recorded $expectedBytes. The bundle and the code are from different '
        'builds.',
      );
    }

    await target.parent.create(recursive: true);
    final sink = partial.openSync(mode: FileMode.writeOnly);
    try {
      var written = 0;
      onProgress?.call(DictionaryInstallProgress(
        bytesWritten: 0,
        totalBytes: bytes.length,
      ));
      while (written < bytes.length) {
        final end = (written + chunkBytes).clamp(0, bytes.length);
        // `writeFromSync`'s third argument is an **absolute end index**, not a
        // count. Passing the count there writes the wrong number of bytes and
        // throws as soon as the chunk is not the last one.
        sink.writeFromSync(bytes, written, end);
        written = end;
        // **The yield is the point.** The write is chunked and every chunk
        // ends with an await, so the event loop gets a turn and the frame
        // scheduler can run: the copy is 26 MB and a single synchronous write
        // of it would be a visible stall.
        await Future<void>.delayed(Duration.zero);
        onProgress?.call(DictionaryInstallProgress(
          bytesWritten: written,
          totalBytes: bytes.length,
        ));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // **The atomic rename.** The dictionary only exists at its real path once
    // it is complete. `rename` is atomic on the same file system, so there is
    // no instant at which the path holds a partly-written database.
    //
    // The old file is removed first because `rename` will not overwrite on
    // every platform, and the window between the two is harmless: the next
    // launch finds no dictionary and copies it again.
    if (await target.exists()) await target.delete();
    await partial.rename(targetPath);

    // **The marker last.** The check that decides "already installed" needs
    // the marker *and* the length, so a copy interrupted between the rename
    // and the marker is simply redone. The reverse order would be the bug: a
    // marker with no dictionary behind it.
    await _writeMarker(marker);

    onProgress?.call(DictionaryInstallProgress(
      bytesWritten: bytes.length,
      totalBytes: bytes.length,
    ));
    return DictionaryInstallOutcome.installed;
  }

  /// Whether the dictionary on disk is the one this build expects.
  Future<bool> _isAlreadyInstalled({
    required File target,
    required File marker,
    required int expectedBytes,
  }) async {
    if (!await target.exists()) return false;
    if (!await marker.exists()) return false;
    if (await target.length() != expectedBytes) return false;
    final recorded = (await marker.readAsString()).trim();
    return recorded == expectedVersion;
  }

  Future<void> _writeMarker(File marker) async {
    final partial = File('${marker.path}$partialSuffix');
    await partial.writeAsString(expectedVersion, flush: true);
    if (await marker.exists()) await marker.delete();
    await partial.rename(marker.path);
  }

  /// How many bytes are written between two yields.
  ///
  /// **256 KB, and the number is a judgement about the frame, not about the
  /// disk.** A chunk too large and the write itself is a visible stall; a
  /// chunk too small and the copy spends its time yielding. 256 KB is
  /// 104 chunks for this artefact.
  static const int chunkBytes = 256 * 1024;
}
