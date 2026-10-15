import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('creates every table on a fresh install', () async {
    final db = await openAppDatabase(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
    final names = rows.map((r) => r['name']).toSet();
    expect(names, containsAll(<String>{
      'packs',
      'entries',
      'word_progress',
      'quiz_sessions',
    }));
    await db.close();
  });

  test('enables foreign keys so cascade deletes fire', () async {
    final db = await openAppDatabase(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final result = await db.rawQuery('PRAGMA foreign_keys');
    expect(result.first.values.first, 1);
    await db.close();
  });

  test('does not throw when opened at the current version', () async {
    final db = await openAppDatabase(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    expect(await db.getVersion(), databaseSchemaVersion);
    await db.close();
  });
}
