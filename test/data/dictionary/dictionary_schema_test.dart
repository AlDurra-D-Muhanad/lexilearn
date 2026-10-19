import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_artifact.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';
import 'package:lexilearn/data/dictionary/dictionary_schema.dart';
import 'package:lexilearn/data/dictionary/dictionary_store.dart';
import 'package:lexilearn/data/dictionary/trigrams.dart';

import 'dictionary_test_env.dart';

/// The committed artefact, and the schema it must have.
///
/// **This file is the guard against a stale dictionary shipping.** The database
/// is a build artefact that is committed to the repository, and nothing in the
/// app's start-up would notice a database built against an older schema - the
/// app would open it, read it, and answer queries against columns that are not
/// there. So the schema is checked here, against the file on disk, with the
/// same declaration the build tool executed.
void main() {
  late DictionaryFixture fixture;

  setUpAll(() async {
    fixture = await DictionaryFixture.open();
  });

  tearDownAll(() async {
    await fixture.close();
  });

  group('the artefact on disk', () {
    test('is the one the build recorded', () {
      // **The build tool writes `dictionary_artifact.dart` from the file it
      // just produced.** If the two ever disagree, the file on disk is not the
      // file the code was written against, and that is exactly the failure
      // this test exists to catch.
      final bytes = File(dictionaryAssetPath).readAsBytesSync();
      expect(bytes.length, dictionaryArtifactBytes);
      expect(sha256.convert(bytes).toString(), dictionaryArtifactSha256);
    });

    test('has no journal or write-ahead log beside it', () {
      // A stray `-wal` beside a committed artefact means the committed bytes
      // are not the whole database.
      for (final suffix in <String>['-journal', '-wal', '-shm']) {
        expect(File('$dictionaryAssetPath$suffix').existsSync(), isFalse,
            reason: '$dictionaryAssetPath$suffix should not be committed');
      }
    });
  });

  group('the schema on disk', () {
    test('is the schema the code declares', () async {
      final rows = await fixture.store.query(
        "SELECT name, sql FROM sqlite_master "
        "WHERE name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final onDisk = <String, String>{
        for (final row in rows) row['name']! as String: row['sql']! as String,
      };

      expect(
        onDisk.keys.toSet(),
        dictionarySchemaObjects.toSet(),
        reason: 'the object list changed; a stale artefact would still have '
            'the old one',
      );

      dictionarySchemaSql.forEach((name, sql) {
        final onDiskSql = onDisk[name];
        expect(onDiskSql, isNotNull, reason: '$name is missing from the file');
        expect(
          _normaliseSql(onDiskSql!),
          _normaliseSql(sql),
          reason: 'the DDL of $name on disk is not the DDL in '
              'dictionary_schema.dart',
        );
      });
    });

    test('has the columns the code declares, in order', () async {
      for (final table in dictionaryColumns.keys) {
        final rows = await fixture.store.query('PRAGMA table_info($table)');
        final actual = <(String, String, bool)>[
          for (final row in rows)
            (
              row['name']! as String,
              row['type']! as String,
              (row['notnull']! as int) != 0,
            ),
        ];
        expect(actual, dictionaryColumns[table], reason: table);
      }
    });

    test('has the indices the code declares', () async {
      final rows = await fixture.store.query(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final names = rows.map((row) => row['name']! as String).toList();
      expect(names, <String>[
        'idx_examples_sense_id',
        'idx_senses_entry_id',
        'idx_senses_norm_ar',
        'idx_trigrams_t',
      ]);
    });

    test('stamps the schema version the code expects', () async {
      final rows = await fixture.store.query('PRAGMA user_version');
      expect(rows.first.values.first, dictionarySchemaVersion);
      final meta = await fixture.store.meta();
      expect(meta['schemaVersion'], '$dictionarySchemaVersion');
    });

    test('holds no morphology table, because the table stays JSON', () async {
      // **Ruling D.** The morphology table is 8.5 KB. In SQLite it would be
      // read on nearly every keystroke; as a JSON asset it is read once at
      // start-up and then lives in memory. A table would also be a second
      // copy of the truth, and the source of a drift between the shipped JSON
      // and the shipped database.
      expect(File(morphologyAssetPath).existsSync(), isTrue);
      final rows = await fixture.store.query(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = rows.map((row) => row['name']! as String).toList();
      expect(tables, isNot(contains('morphology')));
      expect(tables, isNot(contains('irregulars')));
      expect(tables, isNot(contains('suffix_rules')));
      expect(tables, isNot(contains('prefixes')));
      // And the table that *is* there holds the attribution, not the rules.
      expect(tables, contains('meta'));
    });
  });

  group('the contents on disk', () {
    test('are the counts the build recorded', () async {
      Future<int> count(String table) async =>
          (await fixture.store.query('SELECT COUNT(*) AS n FROM $table'))
              .first['n']! as int;

      expect(await count('entries'), dictionaryEntryCount);
      expect(await count('senses'), dictionarySenseCount);
      expect(await count('examples'), dictionaryExampleCount);
      expect(await count('trigrams'), dictionaryTrigramCount);
      expect(await count('meta'), greaterThanOrEqualTo(20));
    });

    test('are the counts the meta table records', () async {
      final meta = await fixture.store.meta();
      expect(int.parse(meta['entryCount']!), dictionaryEntryCount);
      expect(int.parse(meta['senseCount']!), dictionarySenseCount);
      expect(int.parse(meta['arabicSenseCount']!), dictionaryArabicSenseCount);
      expect(int.parse(meta['exampleCount']!), dictionaryExampleCount);
      expect(int.parse(meta['ipaEntryCount']!), dictionaryIpaEntryCount);
      expect(int.parse(meta['arabicKeyCount']!), dictionaryArabicKeyCount);
      expect(int.parse(meta['trigramCount']!), dictionaryTrigramCount);
      expect(int.parse(meta['sourceEntryCount']!), dictionarySourceEntryCount);
      expect(int.parse(meta['mergedCaseVariantCount']!), 851);
    });

    test('hold every key the meta table is required to have', () async {
      final meta = await fixture.store.meta();
      for (final key in requiredMetaKeys) {
        expect(meta.containsKey(key), isTrue, reason: key);
      }
    });

    test('have one entry per normalised headword', () async {
      // The `UNIQUE(norm)` constraint is what makes the case-variant merge
      // possible at all, and this is the assertion that says it held.
      final rows = await fixture.store.query(
        'SELECT COUNT(*) AS n, COUNT(DISTINCT norm) AS d FROM entries',
      );
      expect(rows.first['n'], rows.first['d']);
    });

    test('store the English key the app would compute', () async {
      // **The database and the app must agree about what a key is.** Every
      // `norm` in the file is re-normalised here with the app's own function;
      // if the build had used a different normalisation, this fails.
      final rows = await fixture.store.query('SELECT word, norm FROM entries');
      expect(rows, hasLength(dictionaryEntryCount));
      for (final row in rows) {
        final word = row['word']! as String;
        final norm = row['norm']! as String;
        expect(normalizeEnglish(word), norm, reason: word);
      }
    });

    test('store the Arabic key the app would compute', () async {
      final rows = await fixture.store.query(
        'SELECT ar, norm_ar FROM senses WHERE ar IS NOT NULL',
      );
      expect(rows, hasLength(dictionaryArabicSenseCount));
      for (final row in rows) {
        final arabic = row['ar']! as String;
        final normArabic = row['norm_ar']! as String?;
        expect(normalizeArabic(arabic), normArabic, reason: arabic);
      }
    });

    test('mark has_ar only where a sense really carries Arabic', () async {
      final rows = await fixture.store.query(
        'SELECT e.id AS id, e.has_ar AS has_ar, '
        '(SELECT COUNT(*) FROM senses s '
        ' WHERE s.entry_id = e.id AND s.ar IS NOT NULL AND s.ar <> \'\') AS n '
        'FROM entries e',
      );
      for (final row in rows) {
        expect((row['has_ar']! as int) != 0, (row['n']! as int) > 0,
            reason: 'entry ${row['id']}');
      }
    });

    test('hang every example off a sense that exists', () async {
      final rows = await fixture.store.query(
        'SELECT COUNT(*) AS n FROM examples e '
        'LEFT JOIN senses s ON s.id = e.sense_id WHERE s.id IS NULL',
      );
      expect(rows.first['n'], 0);
    });

    test('give every sense an entry that exists', () async {
      final rows = await fixture.store.query(
        'SELECT COUNT(*) AS n FROM senses s '
        'LEFT JOIN entries e ON e.id = s.entry_id WHERE e.id IS NULL',
      );
      expect(rows.first['n'], 0);
    });

    test('store the trigrams of the headword they belong to', () async {
      // The trigram table is the bound that makes the spell checker
      // shippable, and a bound built from a different function is not a bound.
      final rows = await fixture.store.query(
        'SELECT e.norm AS norm, t.t AS t FROM trigrams t '
        'JOIN entries e ON e.id = t.entry_id '
        'WHERE e.id IN (1, 100, 1000, 10000, 31600)',
      );
      final byNorm = <String, List<String>>{};
      for (final row in rows) {
        byNorm
            .putIfAbsent(row['norm']! as String, () => <String>[])
            .add(row['t']! as String);
      }
      expect(byNorm, isNotEmpty);
      byNorm.forEach((norm, grams) {
        expect(grams.toSet(), trigramsOf(norm).toSet(), reason: norm);
      });
    });
  });
}

/// SQL compared with its whitespace collapsed.
///
/// **Whitespace only, and nothing else.** The point of the comparison is that
/// a column was added, dropped or retyped; collapsing runs of whitespace
/// stops a reformatted `CREATE TABLE` from reading as a difference, and
/// nothing else is normalised away.
String _normaliseSql(String sql) =>
    sql.replaceAll(RegExp(r'\s+'), ' ').trim();
