/// Builds `assets/dictionary/en_ar.db` from the source dictionary.
///
/// **This is the only place the 12 MB of JSON is ever parsed.** The app opens a
/// finished SQLite file and parses nothing; the user never pays the build's
/// seconds, because the build happens once, offline, here.
///
/// Usage:
///   dart run tool/build_dictionary_db.dart [sourceJsonPath] [morphologyPath]
///
/// Defaults to the dictionary the project was given:
///   `C:\Users\user\Desktop\LexiLearn\Dictionary\en-ar-dictionary.json`
///
/// ## Determinism
///
/// The output is a **byte-for-byte function of the input**. That is not
/// tidiness; it is what makes the artefact testable at all. A dictionary that
/// differs between builds is a dictionary nobody can test, because every
/// expectation written against it would have to be re-measured.
///
/// What that costs, and how it is paid:
///
///  * **No timestamps anywhere.** Not in `meta`, not in a column. The one
///    time-varying fact a build would normally record - when it ran - is
///    replaced by the SHA-256 of the source file, which is both stable and
///    more useful: it says *which* dictionary this is, not *when* it was made.
///  * **A fixed insertion order.** Entries are inserted sorted by `norm`, so a
///    row id is a function of the word and not of the order the JSON happened
///    to list them in.
///  * **A fixed page size**, set on the empty file before the first table
///    exists.
///  * **One write transaction.** SQLite's header carries a change counter that
///    increments once per write transaction, so chunking the insert into
///    several transactions would change the file's bytes while changing nothing
///    about its contents. The rows are therefore batched into multi-row
///    `INSERT` statements - a thousand statements rather than half a million -
///    and committed once.
///  * **No `VACUUM`, no `ANALYZE`, no auto-vacuum.** Each of those rewrites the
///    file in a way that is at best incidental and at worst version-dependent.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lexilearn/data/dictionary/dictionary_normalization.dart';
import 'package:lexilearn/data/dictionary/dictionary_schema.dart';
import 'package:lexilearn/data/dictionary/morphology_table.dart';
import 'package:lexilearn/data/dictionary/trigrams.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String defaultSourcePath =
    r'C:\Users\user\Desktop\LexiLearn\Dictionary\en-ar-dictionary.json';

const String defaultMorphologyPath =
    r'C:\Users\user\Desktop\LexiLearn\Dictionary\en-morphology-table.json';

const String artifactPath = 'assets/dictionary/en_ar.db';
const String morphologyAssetPath = 'assets/dictionary/en_morphology.json';
const String generatedConstantsPath =
    'lib/data/dictionary/dictionary_artifact.dart';

/// The upstream project the dictionary was built from, and its URL.
///
/// **Read from the upstream repository's own configuration**, not paraphrased:
/// `docs/dictionary-attribution.md` records where each of these strings came
/// from, and the upstream's own licensing rule is that an adapter must
/// determine a licence from the data rather than assume one. The `meta` block
/// inside the source JSON names the *build*, not the project, and reduces
/// three different licences to one — so the record is written here, at build
/// time, where it can be checked against the artefact it ships with.
const String upstreamProject = 'DanielGregorini/koreader-dicts';
const String upstreamProjectUrl =
    'https://github.com/DanielGregorini/koreader-dicts';
const String upstreamTagline =
    'Free offline StarDict dictionaries for KOReader';

/// The dictionary pair inside the upstream project, and its own description.
const String upstreamPair = 'en-ar';
const String upstreamPairDescription =
    'English to Arabic, built by pivoting Princeton WordNet 3.0 through the '
    'Arabic WordNet and enriching with the English Wiktionary. Includes an '
    'inflection index.';

/// Each source's own licence, from the upstream's `configs/sources.toml`.
///
/// **The three licences differ, and collapsing them into one share-alive
/// line would misstate two of them.** `WordNet-3.0` is a separate and
/// permissive licence; `omw-arb` is `CC-BY-SA-3.0`, which the upstream notes
/// "upgrades to 4.0, so it bundles with Wiktionary without trouble"; and
/// `wikt-en-ar` is `CC-BY-SA-4.0`.
const Map<String, String> sourceLicenses = <String, String>{
  'pwn30': 'WordNet-3.0',
  'omw-arb': 'CC-BY-SA-3.0',
  'wikt-en-ar': 'CC-BY-SA-4.0',
};

/// The source's own `sources` list, keyed by id.
///
/// The list is `id: credit`, and the credit is the source's own wording —
/// "Princeton University WordNet 3.0", "Arabic WordNet (AWN v2), via Open
/// Multilingual Wordnet 1.4", "English Wiktionary via kaikki.org
/// (wiktextract)". The screen shows them one by one with their licences, so
/// they are keyed here rather than left as a list of strings to be split
/// again on the way to the screen.
Map<String, String> _creditsById(Object? raw) {
  if (raw is! List) return const <String, String>{};
  final credits = <String, String>{};
  for (final entry in raw) {
    if (entry is! String) continue;
    final separator = entry.indexOf(':');
    if (separator <= 0) continue;
    credits[entry.substring(0, separator).trim()] = entry.substring(separator + 1).trim();
  }
  return credits;
}

Future<void> main(List<String> args) async {
  final sourcePath = args.isNotEmpty ? args[0] : defaultSourcePath;
  final morphologyPath = args.length > 1 ? args[1] : defaultMorphologyPath;

  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('Source dictionary not found: $sourcePath');
    exitCode = 66;
    return;
  }

  sqfliteFfiInit();

  final total = Stopwatch()..start();

  // --- 1. parse -------------------------------------------------------------
  final parseWatch = Stopwatch()..start();
  final sourceBytes = sourceFile.readAsBytesSync();
  final sourceSha = sha256.convert(sourceBytes).toString();
  final decoded = jsonDecode(utf8.decode(sourceBytes));
  parseWatch.stop();
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('The source dictionary is not a JSON object.');
    exitCode = 65;
    return;
  }
  final rawEntries = decoded['entries'];
  if (rawEntries is! List) {
    stderr.writeln('The source dictionary has no "entries" array.');
    exitCode = 65;
    return;
  }
  final sourceMeta = decoded['meta'];
  if (sourceMeta is! Map<String, dynamic>) {
    stderr.writeln('The source dictionary has no "meta" object.');
    exitCode = 65;
    return;
  }

  stdout.writeln('parsed ${rawEntries.length} entries in '
      '${parseWatch.elapsedMilliseconds} ms');

  // --- 2. merge the case variants ------------------------------------------
  final indexWatch = Stopwatch()..start();
  final merged = <String, _Merged>{};
  for (final raw in rawEntries) {
    if (raw is! Map<String, dynamic>) continue;
    final word = raw['w'];
    if (word is! String) continue;
    final norm = normalizeEnglish(word);
    final rawIpa = raw['ipa'];
    final ipa = rawIpa is String ? rawIpa : null;
    var target = merged[norm];
    if (target == null) {
      target = _Merged(word: word, ipa: _clean(ipa));
      merged[norm] = target;
    } else {
      // The README keeps the first non-empty IPA across every spelling.
      target.mergedFrom++;
      if (_isBlank(target.ipa) && !_isBlank(ipa)) target.ipa = ipa;
    }
    final senses = raw['senses'];
    if (senses is! List) continue;
    for (final rawSense in senses) {
      if (rawSense is! Map<String, dynamic>) continue;
      final rawAr = rawSense['ar'];
      final rawEn = rawSense['en'];
      final rawPos = rawSense['pos'];
      final arabic = rawAr is String ? rawAr : null;
      final gloss = rawEn is String ? rawEn : null;
      final partOfSpeech = rawPos is String ? rawPos : null;
      // The README's own dedup: two senses are the same sense when their
      // Arabic, their gloss and their part of speech all match. U+0000 cannot
      // occur in any of them, so it is a separator that cannot collide.
      final fingerprint = '$arabic\u0000$gloss\u0000$partOfSpeech';
      if (!target.seen.add(fingerprint)) continue;
      final examples = <String>[];
      final rawExamples = rawSense['ex'];
      if (rawExamples is List) {
        for (final rawExample in rawExamples) {
          if (rawExample is String) examples.add(rawExample);
        }
      }
      target.senses.add(_Sense(
        pos: partOfSpeech,
        arabic: arabic,
        gloss: gloss,
        examples: examples,
      ));
    }
  }
  indexWatch.stop();
  stdout.writeln('merged to ${merged.length} headwords in '
      '${indexWatch.elapsedMilliseconds} ms');

  // Sorted by `norm`, so a row id is a function of the word.
  final ordered = merged.keys.toList()..sort();

  // --- 3. write the database -----------------------------------------------
  final artifact = File(artifactPath);
  await artifact.parent.create(recursive: true);
  if (artifact.existsSync()) artifact.deleteSync();
  // A stale journal or WAL from an earlier run would be picked up by the next
  // open, and the file this build writes must be the file that is shipped.
  for (final suffix in <String>['-journal', '-wal', '-shm']) {
    final sidecar = File('$artifactPath$suffix');
    if (sidecar.existsSync()) sidecar.deleteSync();
  }

  final insertWatch = Stopwatch()..start();
  // Declared out here so the generated constants can report them; the values
  // are filled in below, inside the transaction that writes them.
  var senseId = 0;
  var exampleId = 0;
  var trigramRows = 0;
  var arabicSenseCount = 0;
  var exampleCount = 0;
  var ipaCount = 0;
  var arabicKeyCount = 0;
  // No `version:` here. sqflite would otherwise manage `user_version` itself,
  // and this tool wants to control every byte of the header.
  //
  // **The path is absolute, and that is not a convenience.** `sqflite`'s FFI
  // factory resolves a relative path against its own database directory -
  // `.dart_tool/sqflite_common_ffi/databases/` - so `assets/dictionary/en_ar.db`
  // would be written *there* and the artefact would never reach the repository.
  // Measured, by getting it wrong: the first run of this tool wrote a database
  // under `.dart_tool/` and left the repository without one.
  final artifactAbsolute = artifact.absolute.path;
  final db = await databaseFactoryFfi.openDatabase(
    artifactAbsolute,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    // Before the first table exists, so the page size is fixed for good.
    await db.execute('PRAGMA page_size = 4096');
    await db.execute('PRAGMA journal_mode = DELETE');

    // The schema, from the one declaration in `lib/`. The build tool and the
    // tests import the same strings, so the artefact and the code that reads
    // it cannot drift apart.
    for (final name in dictionaryTables.keys) {
      await db.execute(dictionaryTables[name]!);
    }
    for (final name in dictionaryIndices.keys) {
      await db.execute(dictionaryIndices[name]!);
    }

    final batch = db.batch();
    final entries = _Chunked(batch, 'entries', <String>['id', 'word', 'norm', 'ipa', 'has_ar']);
    final senses = _Chunked(batch, 'senses', <String>['id', 'entry_id', 'pos', 'ar', 'norm_ar', 'en']);
    final examples = _Chunked(batch, 'examples', <String>['id', 'sense_id', 'text']);
    final trigrams = _Chunked(batch, 'trigrams', <String>['t', 'entry_id']);

    final arabicKeys = <String>{};

    for (var index = 0; index < ordered.length; index++) {
      final norm = ordered[index];
      final entry = merged[norm]!;
      final entryId = index + 1;
      var hasArabic = false;
      for (final sense in entry.senses) {
        if (!_isBlank(sense.arabic)) {
          hasArabic = true;
          arabicSenseCount++;
          arabicKeys.add(normalizeArabic(sense.arabic));
        }
        exampleCount += sense.examples.length;
      }
      if (!_isBlank(entry.ipa)) ipaCount++;
      entries.add(<Object?>[entryId, entry.word, norm, entry.ipa, hasArabic ? 1 : 0]);
      for (final sense in entry.senses) {
        senseId++;
        final normAr = _isBlank(sense.arabic) ? null : normalizeArabic(sense.arabic);
        senses.add(<Object?>[
          senseId,
          entryId,
          sense.pos,
          sense.arabic,
          normAr,
          sense.gloss,
        ]);
        for (final example in sense.examples) {
          exampleId++;
          examples.add(<Object?>[exampleId, senseId, example]);
        }
      }
      for (final gram in trigramsOf(norm)) {
        trigramRows++;
        trigrams.add(<Object?>[gram, entryId]);
      }
    }
    entries.flush();
    senses.flush();
    examples.flush();
    trigrams.flush();

    arabicKeyCount = arabicKeys.length;

    final meta = <String, String>{
      'schemaVersion': '$dictionarySchemaVersion',
      'name': (sourceMeta['name'] as String?) ?? '',
      'source': (sourceMeta['source'] as String?) ?? '',
      'sources': jsonEncode(sourceMeta['sources'] ?? const <String>[]),
      'license': (sourceMeta['license'] as String?) ?? '',
      'licenseUrl': (sourceMeta['licenseUrl'] as String?) ?? '',
      // **The attribution record, and it is the record rather than a
      // summary.** The `meta` block inside the source JSON names the *build*
      // and reduces three different licences to one; the app has to show
      // each source's own licence, because two of the three are not
      // share-alike. The strings below are read from the upstream project's
      // own `configs/sources.toml` and are recorded verbatim in
      // `docs/dictionary-attribution.md`; nothing here is paraphrased.
      'upstreamProject': upstreamProject,
      'upstreamProjectUrl': upstreamProjectUrl,
      'upstreamTagline': upstreamTagline,
      'upstreamPair': upstreamPair,
      'upstreamPairDescription': upstreamPairDescription,
      'sourceLicenses': jsonEncode(sourceLicenses),
      // **The credits are the source's own**, parsed out of its `sources`
      // list rather than written again here: the list is `id: credit`, and
      // the screen wants them keyed by id.
      'sourceCredits': jsonEncode(_creditsById(sourceMeta['sources'])),
      'generatedFrom': (sourceMeta['generatedFrom'] as String?) ?? '',
      'sourceFile': sourceFile.uri.pathSegments.last,
      'sourceSha256': sourceSha,
      'sourceBytes': '${sourceBytes.length}',
      'entryCount': '${merged.length}',
      'sourceEntryCount': '${rawEntries.length}',
      'mergedCaseVariantCount':
          '${merged.values.fold<int>(0, (sum, e) => sum + e.mergedFrom)}',
      'senseCount': '$senseId',
      'arabicSenseCount': '$arabicSenseCount',
      'exampleCount': '$exampleCount',
      'ipaEntryCount': '$ipaCount',
      'arabicKeyCount': '$arabicKeyCount',
      'trigramCount': '$trigramRows',
    };
    final metaRows = _Chunked(batch, 'meta', <String>['k', 'v']);
    for (final entry in meta.entries) {
      metaRows.add(<Object?>[entry.key, entry.value]);
    }
    metaRows.flush();

    // One transaction for the whole file. See the library doc comment.
    await batch.commit(noResult: true);
    await db.execute('PRAGMA user_version = $dictionarySchemaVersion');

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.first.values.first != 'ok') {
      stderr.writeln('integrity_check failed: $integrity');
      exitCode = 70;
      return;
    }
    final pageSize = await db.rawQuery('PRAGMA page_size');
    insertWatch.stop();
    stdout.writeln('inserted ${merged.length} entries, $senseId senses, '
        '$exampleCount examples, $trigramRows trigrams in '
        '${insertWatch.elapsedMilliseconds} ms');
    stdout.writeln('arabic keys: ${arabicKeys.length}, with ipa: $ipaCount, '
        'page size: ${pageSize.first.values.first}');
  } finally {
    await db.close();
  }

  // --- 4. the morphology table ---------------------------------------------
  final morphologyFile = File(morphologyPath);
  if (!morphologyFile.existsSync()) {
    stderr.writeln('Morphology table not found: $morphologyPath');
    exitCode = 66;
    return;
  }
  final morphologyBytes = morphologyFile.readAsBytesSync();
  final morphologyTarget = File(morphologyAssetPath);
  await morphologyTarget.parent.create(recursive: true);
  await morphologyTarget.writeAsBytes(morphologyBytes, flush: true);
  // Parsed here so that a malformed table fails the build rather than the app.
  final table = MorphologyTable.parse(utf8.decode(morphologyBytes));
  stdout.writeln('morphology: ${table.irregulars.length} irregulars, '
      '${table.suffixRules.length} rules, ${table.prefixes.length} prefixes, '
      '${table.neverStem.length} neverStem');

  // --- 5. the generated constants ------------------------------------------
  final artifactBytes = artifact.readAsBytesSync();
  final artifactSha = sha256.convert(artifactBytes).toString();
  final constants = _generatedConstants(
    artifactBytes: artifactBytes.length,
    artifactSha256: artifactSha,
    sourceSha256: sourceSha,
    sourceBytes: sourceBytes.length,
    entryCount: merged.length,
    sourceEntryCount: rawEntries.length,
    senseCount: senseId,
    arabicSenseCount: arabicSenseCount,
    exampleCount: exampleCount,
    ipaEntryCount: ipaCount,
    arabicKeyCount: arabicKeyCount,
    trigramCount: trigramRows,
    sourceFileName: sourceFile.uri.pathSegments.last,
  );
  final constantsFile = File(generatedConstantsPath);
  await constantsFile.parent.create(recursive: true);
  await constantsFile.writeAsString(constants, encoding: utf8, flush: true);

  total.stop();
  stdout.writeln('');
  stdout.writeln('$artifactPath: ${artifactBytes.length} bytes');
  stdout.writeln('sha256: $artifactSha');
  stdout.writeln('built in ${total.elapsedMilliseconds} ms');
}

/// One headword after the case-variant merge.
class _Merged {
  _Merged({required this.word, required this.ipa});

  /// The first spelling the source offered - `Acre`, not `acre`.
  final String word;

  /// The first non-empty phonetic transcription across every spelling.
  String? ipa;

  /// How many extra spellings were folded into this headword.
  int mergedFrom = 0;

  final List<_Sense> senses = <_Sense>[];

  /// The fingerprints of the senses already held, for the README's dedup.
  final Set<String> seen = <String>{};
}

/// One sense.
class _Sense {
  _Sense({
    required this.pos,
    required this.arabic,
    required this.gloss,
    required this.examples,
  });

  final String? pos;
  final String? arabic;
  final String? gloss;
  final List<String> examples;
}

/// Buffers rows and flushes them as multi-row `INSERT` statements.
///
/// **One statement per 150 rows rather than one per row.** 478,000 individual
/// inserts means 478,000 SQL strings to build and hold; 3,200 statements means
/// the build stays inside a reasonable memory budget and finishes in seconds.
///
/// The chunk size is 150 because the widest table here has six columns, and
/// 150 x 6 = 900 placeholders - under SQLite's historical 999-variable limit,
/// so the build does not depend on the version of SQLite that happens to be
/// installed.
class _Chunked {
  _Chunked(this.batch, this.table, this.columns, {this.chunk = 150});

  final Batch batch;
  final String table;
  final List<String> columns;
  final int chunk;
  final List<List<Object?>> _rows = <List<Object?>>[];

  void add(List<Object?> row) {
    _rows.add(row);
    if (_rows.length >= chunk) flush();
  }

  void flush() {
    if (_rows.isEmpty) return;
    final buffer = StringBuffer('INSERT INTO $table (${columns.join(', ')}) VALUES ');
    final arguments = <Object?>[];
    for (var i = 0; i < _rows.length; i++) {
      if (i > 0) buffer.write(', ');
      buffer.write('(');
      buffer.write(List<String>.filled(columns.length, '?').join(', '));
      buffer.write(')');
      arguments.addAll(_rows[i]);
    }
    batch.rawInsert(buffer.toString(), arguments);
    _rows.clear();
  }
}

bool _isBlank(String? value) => value == null || value.isEmpty;

String? _clean(String? value) => _isBlank(value) ? null : value;

String _generatedConstants({
  required int artifactBytes,
  required String artifactSha256,
  required String sourceSha256,
  required int sourceBytes,
  required int entryCount,
  required int sourceEntryCount,
  required int senseCount,
  required int arabicSenseCount,
  required int exampleCount,
  required int ipaEntryCount,
  required int arabicKeyCount,
  required int trigramCount,
  required String sourceFileName,
}) {
  return '''
// GENERATED FILE - DO NOT EDIT.
//
// Written by `tool/build_dictionary_db.dart`, which is the only thing that may
// write it. Regenerate with:
//
//   dart run tool/build_dictionary_db.dart
//
// It records the facts about the shipped artefact that the runtime and the
// tests both need, so that neither of them has to hard-code a number that can
// drift away from the file on disk. `test/data/dictionary/dictionary_schema_test.dart`
// re-measures the artefact and fails if any of these has stopped being true.

/// The exact size, in bytes, of `$artifactPath`.
const int dictionaryArtifactBytes = $artifactBytes;

/// The SHA-256 of `$artifactPath`, lower-case hex.
const String dictionaryArtifactSha256 = '$artifactSha256';

/// The SHA-256 of the source JSON the artefact was built from.
const String dictionarySourceSha256 = '$sourceSha256';

/// The size, in bytes, of the source JSON.
const int dictionarySourceBytes = $sourceBytes;

/// The name of the source JSON.
const String dictionarySourceFileName = '$sourceFileName';

/// Headwords in the artefact, after the case-variant merge.
const int dictionaryEntryCount = $entryCount;

/// Headwords in the source, before the merge.
const int dictionarySourceEntryCount = $sourceEntryCount;

/// Senses in the artefact.
const int dictionarySenseCount = $senseCount;

/// Senses carrying Arabic.
const int dictionaryArabicSenseCount = $arabicSenseCount;

/// Example sentences.
const int dictionaryExampleCount = $exampleCount;

/// Headwords carrying a phonetic transcription.
const int dictionaryIpaEntryCount = $ipaEntryCount;

/// Distinct normalised Arabic keys.
const int dictionaryArabicKeyCount = $arabicKeyCount;

/// Rows in the `trigrams` table.
const int dictionaryTrigramCount = $trigramCount;
''';
}
