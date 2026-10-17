import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
// `PackSummary` is what `VocabRepository.packs()` returns, and it lives in the
// DAO. `quiz_setup_screen.dart` imports it from the same place, so this file
// follows the precedent rather than re-exporting it from the repository — which
// would be tidier and would make that existing import redundant, i.e. an
// analyzer issue in a file this task has no business editing.
import 'package:lexilearn/data/pack_dao.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Reads one `.json` file and hands back its text, or null if the user backed
/// out.
///
/// **This typedef is the whole reason the tests never touch a file dialog.**
/// The real implementation opens the system document picker; a test injects
/// `() async => someJsonString` and the entire import/restore path — decode,
/// validation, the write, the error sentence — runs with no platform at all.
/// `docs/engineering-standards.md` §5's spirit: the awkward environment sits
/// behind one named seam, and every test past it is plain `Future` work.
typedef PickJsonFile = Future<String?> Function();

/// The packs list, and the three things a user can do with a file.
///
/// **Every notification goes through [_notifyIfAlive]**, for the same reason
/// `StatsController`, `SearchController` and `QuizController` each carry one:
/// `load()` is fired from a widget's `initState`, so a read is still in flight
/// when the user switches destination and that destination is torn down.
/// `ChangeNotifier` asserts on `notifyListeners()` after `dispose()` rather than
/// doing nothing.
class PacksController extends ChangeNotifier {
  /// [repository] and [pickJsonFile] are initializing formals, which
  /// `prefer_initializing_formals` asks for and which changes no call site: on a
  /// **named** parameter Dart exposes `this._x` publicly as `x`, so every
  /// `PacksController(repository: …, pickJsonFile: …)` still names it the same
  /// way. The same choice, and the same reason, as `StatsController`.
  PacksController({
    required this._repository,
    PickJsonFile? pickJsonFile,
  }) : _pick = pickJsonFile ?? _pickFromDevice;

  final VocabRepository _repository;
  final PickJsonFile _pick;

  List<PackSummary> _packs = const <PackSummary>[];
  bool _isBusy = false;
  Object? _error;
  String? _message;

  /// Set in [dispose]. See [_notifyIfAlive].
  bool _disposed = false;

  /// Every pack on the device, bundled first then newest.
  ///
  /// `PackDao.listPacks`'s own order, passed straight through rather than
  /// re-sorted here, so there is exactly one ordering rule in the app.
  List<PackSummary> get packs => _packs;

  /// True while a pick, a write or a share sheet is in flight.
  ///
  /// Rendered as a line of words and as disabled buttons, **never a spinner**:
  /// an indeterminate `CircularProgressIndicator` schedules frames forever, so
  /// `pumpAndSettle` never returns while one is on screen. See
  /// `stats_screen.dart` → `_AccuracyCard` for the same decision.
  bool get isBusy => _isBusy;

  /// The last failure, as a **sentence**, or null.
  ///
  /// Typed `Object?` by the interface and deliberately holding a `String`: the
  /// screen renders it verbatim, so putting the raw exception here is how a user
  /// ends up reading `MissingPluginException(No implementation found for method
  /// MethodChannel#path_provider)` instead of what actually went wrong. Every
  /// catch below converts before it assigns.
  Object? get error => _error;

  /// The last thing that worked, as a sentence, or null.
  ///
  /// Kept apart from [error] so a failure never erases the fact that the list
  /// behind it is the real one — the same reasoning as `StatsController.error`.
  String? get message => _message;

  /// Re-reads the pack list.
  ///
  /// A failure leaves the previous list standing: a screen that blanked to an
  /// error would read as "you have no packs", which is a different and much
  /// worse claim.
  Future<void> load() async {
    try {
      _packs = await _repository.packs();
      _notifyIfAlive();
    } on Object catch (error) {
      _error = 'تعذّر قراءة قائمة الحزم. ($error)';
      _notifyIfAlive();
    }
  }

  /// Picks a file and installs it as a **vocabulary pack**.
  ///
  /// Rejects a backup document with the codec's own sentence naming the other
  /// action, because the two file kinds are both `.json` and a user has no way
  /// to tell them apart before handing one over. See [restoreFromPicker].
  Future<void> importFromPicker() async {
    await _guard(() async {
      final json = await _pick();
      if (json == null) {
        _message = _nothingChosen;
        return;
      }
      final pack = await _repository.importPack(json);
      _message = 'تم استيراد «${pack.title}» — ${pack.entryCount} كلمة.';
    });
    await load();
  }

  /// Picks a file and restores it as a **backup**: packs, progress and sessions.
  ///
  /// Separate from [importFromPicker] on purpose. A restore *replaces* every
  /// pack on the device, so it is not the same act as adding one, and the two
  /// buttons say which one they are before the file dialog is even open. The
  /// dialog itself is the same [PickJsonFile] seam, so a test drives this path
  /// with a string exactly as it drives the import path.
  ///
  /// Not in the plan's interface list, and it has to be: `restoreBackup` takes
  /// the text as a parameter, so without this there is no way for a user to
  /// reach a backup file at all.
  ///
  /// **One `_guard` for this one action, not a `_guard` inside a `_guard`.** The
  /// first version called `restoreBackup` from inside its own guarded body. What
  /// that actually cost: the inner guard's `finally` cleared `isBusy` while the
  /// outer action was still unwinding, so `isBusy` was briefly false with work
  /// still in flight, and there were two `finally` blocks whose interaction was
  /// invisible from either call site. The restore's work is inlined here instead,
  /// so there is exactly one place that catches and one place that restores
  /// `isBusy`.
  ///
  /// **The collapse changed no sentence the user can read.** The old comment on
  /// this method claimed it recovered a device-specific failure message, and that
  /// was false: neither guard passed `deviceFailure`, so both catch clauses
  /// produced the same strings before and after — `_unexpected` for a plain
  /// `Object`, `_unavailableHere` for a `MissingPluginException`. `deviceFailure`
  /// exists for exactly one caller, [exportBackup], which is the only method whose
  /// failure is about the device rather than about a file the user chose.
  ///
  /// **[restoreBackup] therefore still reports the generic sentence on purpose**:
  /// no restore-specific failure is distinguished anywhere in this class. If one
  /// ever is — a backup that is unreadable because of storage, say — it belongs
  /// in a `deviceFailure` passed from here and from [restoreBackup] together, and
  /// then this method stops being identical to its own message table.
  Future<void> restoreFromPicker() async {
    await _guard(() async {
      final json = await _pick();
      if (json == null) {
        _message = _nothingChosen;
        return;
      }
      final count = await _repository.importBackupJson(json);
      _message = 'تمت الاستعادة — $count حزمة.';
      await load();
    });
  }

  /// Restores [jsonText], returning how many packs came back, or null on failure.
  ///
  /// The text is a parameter rather than something this class fetches, so the
  /// restore path is testable without a dialog and so the same bytes can be
  /// replayed: a user who restores twice must get the same device twice.
  ///
  /// The one duplicated line with [restoreFromPicker] is the `importBackupJson`
  /// call and its message. It is duplicated rather than shared through a private
  /// helper precisely so that neither path can end up nesting a guard in a guard;
  /// the alternative — a `_restore` helper that both call — is one line shorter
  /// and reintroduces the nesting when someone adds a second guard to it. Both
  /// report failures identically, and [restoreFromPicker] says why that is
  /// deliberate.
  Future<int?> restoreBackup(String jsonText) => _guard(() async {
        final count = await _repository.importBackupJson(jsonText);
        _message = 'تمت الاستعادة — $count حزمة.';
        await load();
        return count;
      });

  /// Removes one imported pack and everything recorded against it.
  ///
  /// A bundled pack is not deletable: the app seeds it on first launch and
  /// re-seeds it on the next start, so a "delete" control on it would promise a
  /// change the next launch silently undoes. The screen hides the control rather
  /// than this method refusing, so the promise is never made in the first place.
  Future<void> deletePack(String packKey) async {
    await _guard(() async {
      await _repository.deletePack(packKey);
      _message = 'تم حذف الحزمة.';
    });
    await load();
  }

  /// Writes the whole backup into the app's documents directory and hands it to
  /// the system share sheet, which is how it reaches Drive, Dropbox or a cable.
  ///
  /// Returns the path it wrote, or null if it got no further.
  ///
  /// **Two platform seams live here and neither is reachable in a test:**
  /// `path_provider` has no implementation under `flutter_test` and `share_plus`
  /// needs a platform view. So what a test can pin is the behaviour that *is*
  /// reachable — the controller stays alive, `isBusy` returns to false, and the
  /// user gets a sentence rather than a stack trace — and the JSON that would
  /// have been written is pinned directly against
  /// `VocabRepository.exportBackupJson` in `test/data/vocab_repository_test.dart`
  /// rather than through a file this platform cannot create.
  Future<String?> exportBackup() => _guard(
        () async {
          final json = await _repository.exportBackupJson();
          final directory = await getApplicationDocumentsDirectory();
          // Wall clock on purpose, and the only place this app uses one: a
          // filename is not data, it is never read back, and injecting a clock
          // for it would mean pinning a string that no assertion can depend on.
          final stamp =
              DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
          final file =
              File(p.join(directory.path, 'lexilearn-backup-$stamp.json'));
          await file.writeAsString(json, encoding: utf8);
          await SharePlus.instance.share(
            ShareParams(
              files: <XFile>[XFile(file.path, mimeType: 'application/json')],
              text: 'نسخة احتياطية من LexiLearn',
            ),
          );
          _message = 'تم إنشاء النسخة الاحتياطية ${p.basename(file.path)}.';
          return file.path;
        },
        // The export's two failures are about the *device*, not about a file
        // the user chose, so they get their own sentence.
        deviceFailure: 'تعذّر إنشاء النسخة الاحتياطية على هذا الجهاز.',
      );

  /// Runs one action with the busy flag and the error capture every public
  /// method here shares.
  ///
  /// `null` comes back when the action failed, which is how [exportBackup] and
  /// [restoreBackup] tell "wrote a file" from "said a sentence".
  Future<T?> _guard<T>(
    Future<T> Function() action, {
    String? deviceFailure,
  }) async {
    _clear();
    _isBusy = true;
    _notifyIfAlive();
    try {
      return await action();
    } on PackDecodeException catch (error) {
      // The one failure with a sentence somebody already wrote for a person.
      _error = error.message;
      return null;
    } on FileSystemException {
      _error = _cannotReadFile;
      return null;
    } on MissingPluginException {
      // `path_provider` or `share_plus` on a platform that has no implementation
      // for them. A real phone always has one; a test or an unsupported desktop
      // does not, and neither is a reason to crash the destination.
      _error = deviceFailure ?? _unavailableHere;
      return null;
    } on Object {
      _error = deviceFailure ?? _unexpected;
      return null;
    } finally {
      _isBusy = false;
      _notifyIfAlive();
    }
  }

  static const String _nothingChosen = 'لم تختر ملفاً.';
  static const String _cannotReadFile = 'تعذّر قراءة الملف.';
  static const String _unavailableHere = 'هذه الميزة غير متاحة على هذا الجهاز.';
  static const String _unexpected = 'حدث خطأ غير متوقع.';

  void _clear() {
    _error = null;
    _message = null;
  }

  /// Opens the system document picker and reads the chosen file as UTF-8.
  ///
  /// **The plan's version of this does not compile against
  /// `file_picker 13.1.0`.** It was written for `file_picker 5`, where
  /// `FilePicker.platform.pickFiles(…)` returned a `FilePickerResult?` whose
  /// `.files.single.bytes` carried the content. In 13.1.0, read out of
  /// `file_picker-13.1.0/lib/src/file_picker.dart`:
  ///
  /// * `pickFiles` is a **static** method on `FilePicker` — there is no
  ///   `FilePicker.platform` any more;
  /// * it returns `Future<List<PlatformFile>>`, **not** a nullable result, and
  ///   a cancelled pick is an **empty list**;
  /// * `PlatformFile` has no `bytes` field at all — the bytes come from
  ///   `readAsBytes()`.
  ///
  /// Reading the bytes rather than opening `path` is also the behaviour that
  /// works for a content-URI pick, which has no filesystem path to open.
  static Future<String?> _pickFromDevice() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty) return null;
    return utf8.decode(await picked.single.readAsBytes());
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}