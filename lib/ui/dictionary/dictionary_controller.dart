import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lexilearn/data/dictionary/dictionary_database.dart';
import 'package:lexilearn/data/dictionary/dictionary_engine.dart';
import 'package:lexilearn/data/dictionary/dictionary_installer.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/data/dictionary/dictionary_schema.dart';
import 'package:lexilearn/data/dictionary/morphology_table.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:sqflite/sqflite.dart';

/// Where the dictionary is in its own life.
enum DictionaryStatus {
  /// Nothing has been asked of it yet.
  idle,

  /// The copy onto the device is running.
  installing,

  /// The dictionary is on the device and open.
  ready,

  /// The copy or the open failed.
  failed,
}

/// The dictionary, as the app sees it: a copy on the device, a progress
/// figure, and an engine once it is there.
///
/// **Everything here happens off the UI path.** [start] is fired and not
/// awaited; the app opens, navigates and shows the home screen while the copy
/// runs, and the home screen says what is happening rather than showing an
/// empty search with no explanation.
///
/// **The controller is a `ChangeNotifier` because the progress is a number the
/// screen draws**, and a number that changes has to redraw. The engine itself
/// is not a listener: it is a plain object behind a query.
class DictionaryController extends ChangeNotifier {
  DictionaryController({
    this.repository,
    this.onEngineReady,
    this.installer = const DictionaryInstaller(),
    this.loadAsset,
    this.loadMorphology,
    this.targetPath,
    this.databaseFactory,
    this.assetPath = dictionaryAssetPath,
  });

  /// A controller that never starts.
  ///
  /// **For a screen mounted on its own and for a test.** The app itself
  /// always builds a real one; this is the shape a widget test can mount
  /// without a device, a bundle or a file system.
  factory DictionaryController.idle() => DictionaryController();

  /// A controller that already has its engine.
  ///
  /// **For a test that has one.** The shipped artefact is a committed file, so
  /// a test can open it and hand the engine over — which is how a screen that
  /// needs the dictionary is exercised without a 26 MB copy.
  factory DictionaryController.ready(DictionaryEngine engine) {
    final controller = DictionaryController();
    controller._engine = engine;
    controller._status = DictionaryStatus.ready;
    controller._progress = 1;
    controller._ready.complete(engine);
    return controller;
  }

  /// The repository the engine is attached to, when there is one.
  final VocabRepository? repository;

  /// Called with the engine once the dictionary is open.
  ///
  /// **A callback and not the repository itself**, so a controller can exist
  /// without a database — which is what makes the idle one possible and what
  /// lets a widget test mount a screen that reads this controller without
  /// standing up a repository it does not need.
  final void Function(DictionaryEngine engine)? onEngineReady;

  final DictionaryInstaller installer;

  /// Reads the dictionary out of the bundle. Null means "there is nothing to
  /// install", and the controller stays idle.
  final Future<ByteData> Function(String key)? loadAsset;

  /// Reads the morphology table out of the bundle.
  final Future<String> Function(String key)? loadMorphology;

  /// Where the finished dictionary lives on the device.
  final String? targetPath;

  /// The SQLite factory the dictionary is opened with.
  final DatabaseFactory? databaseFactory;

  /// The asset path inside the bundle.
  final String assetPath;

  DictionaryStatus _status = DictionaryStatus.idle;
  double _progress = 0;
  Object? _error;
  DictionaryEngine? _engine;
  bool _disposed = false;

  /// Completed when the engine is there.
  ///
  /// **A completer rather than a poll**, so a screen that needs the
  /// dictionary can wait for it instead of being told "not yet" and having to
  /// ask again.
  final Completer<DictionaryEngine> _ready = Completer<DictionaryEngine>();

  /// The attribution, read once out of `meta`.
  Future<DictionaryAttribution>? _attribution;

  /// Where the dictionary is in its own life.
  DictionaryStatus get status => _status;

  /// How far the copy has got, between 0 and 1.
  double get progress => _progress;

  /// The last failure, as an object. The screen renders a sentence of its own.
  Object? get error => _error;

  /// The engine, or null until the dictionary is ready.
  DictionaryEngine? get engine => _engine;

  /// Whether the dictionary can be searched.
  bool get isReady => _engine != null;

  /// Whether the copy is running.
  bool get isInstalling => _status == DictionaryStatus.installing;

  /// The dictionary's attribution, read out of `meta`.
  ///
  /// **The licence obligation, and it is read once.** The attribution screen
  /// needs the licence, its URL and the three upstream sources, and they do
  /// not change while the app is running.
  Future<DictionaryAttribution> attribution() {
    final engine = _engine;
    if (engine == null) {
      return _ready.future.then((ready) => ready.attribution());
    }
    return _attribution ??= engine.attribution();
  }

  /// Installs the dictionary, if the seams for it are there.
  ///
  /// **Never throws.** A failure lands in [error] and the app carries on with
  /// the starter pack, because an app that will not open because a 26 MB
  /// asset could not be copied is worse than an app with no dictionary in it.
  Future<void> start() async {
    final load = loadAsset;
    final morphologyLoader = loadMorphology;
    final target = targetPath;
    final factory = databaseFactory;
    if (load == null || morphologyLoader == null || target == null ||
        factory == null) {
      return;
    }
    _status = DictionaryStatus.installing;
    _progress = 0;
    _error = null;
    _notifyIfAlive();
    try {
      await installer.install(
        load: load,
        targetPath: target,
        assetPath: assetPath,
        onProgress: (value) {
          _progress = value.fraction;
          _notifyIfAlive();
        },
      );
      final morphology =
          MorphologyTable.parse(await morphologyLoader(morphologyAssetPath));
      final engine = await openDictionaryEngine(
        factory: factory,
        path: target,
        morphology: morphology,
      );
      _engine = engine;
      repository?.attachDictionary(engine);
      onEngineReady?.call(engine);
      if (!_ready.isCompleted) _ready.complete(engine);
      _status = DictionaryStatus.ready;
      _progress = 1;
      _notifyIfAlive();
    } on Object catch (error) {
      _error = error;
      _status = DictionaryStatus.failed;
      _notifyIfAlive();
    }
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
