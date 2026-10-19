import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_engine.dart';
import 'package:lexilearn/data/dictionary/dictionary_schema.dart';
import 'package:lexilearn/data/dictionary/dictionary_store.dart';
import 'package:lexilearn/data/dictionary/morphology_table.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The shipped dictionary, opened for reading.
///
/// **The tests read the artefact that ships.** Not a fixture, not a copy, not a
/// database built inside the test: `assets/dictionary/en_ar.db`, exactly as
/// committed. A test that builds its own database tests the test's builder;
/// this one tests the file a user would get.
///
/// The file is opened **read-only**, through the same
/// `openDictionaryDatabase` the app uses, so the read-only guarantee and the
/// schema-version check are both exercised by every test that uses this
/// fixture.
class DictionaryFixture {
  DictionaryFixture._(this.database, this.store, this.morphology, this.engine);

  final Database database;
  final DictionaryStore store;
  final MorphologyTable morphology;
  final DictionaryEngine engine;

  /// Opens the shipped dictionary.
  static Future<DictionaryFixture> open() async {
    sqfliteFfiInit();
    // `flutter test` runs with the package root as the working directory. If
    // that ever stops being true the path below silently becomes wrong, so it
    // is checked rather than assumed.
    if (!File('pubspec.yaml').existsSync()) {
      fail('the tests are not running from the package root; the dictionary '
          'artefact could not be found');    }
    final artifact = File(dictionaryAssetPath);
    if (!artifact.existsSync()) {
      fail('$dictionaryAssetPath is missing. Build it with '
          '`dart run tool/build_dictionary_db.dart`.');
    }
    final database = await databaseFactoryFfi.openDatabase(
      artifact.absolute.path,
      options: OpenDatabaseOptions(
        readOnly: true,
        singleInstance: false,
      ),
    );
    final store = DictionaryStore(database);
    final morphology = MorphologyTable.parse(
      await File(morphologyAssetPath).readAsString(),
    );
    final engine = DictionaryEngine(store: store, morphology: morphology);
    return DictionaryFixture._(database, store, morphology, engine);
  }

  Future<void> close() => database.close();
}

/// The morphology table exactly as it ships, parsed from the shipped asset.
///
/// **The asset, not the source.** The file in `assets/dictionary/` is what the
/// app reads, so that is what the tests read; a difference between the two
/// would be a bug the app would ship.
MorphologyTable shippedMorphologyTable() =>
    MorphologyTable.parse(File(morphologyAssetPath).readAsStringSync());
