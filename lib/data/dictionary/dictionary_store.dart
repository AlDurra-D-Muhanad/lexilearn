import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/data/dictionary/dictionary_schema.dart';
import 'package:lexilearn/data/dictionary/trigrams.dart' as trigrams;
import 'package:sqflite/sqflite.dart';

/// Read-only access to `assets/dictionary/en_ar.db`.
///
/// **Every method here is a read.** The file is a build artefact shipped inside
/// the APK; it is never written, never migrated and never vacuumed. That is why
/// it has no DAOs with an `executor:` parameter the way `lib/data/*_dao.dart`
/// do - there is no transaction to join and no other writer to coordinate with.
///
/// **`DatabaseExecutor`, not `Database`.** The app database is opened through
/// `openAppDatabase`, which has to be able to create and migrate; this one is
/// opened read-only and is handed to the store as the narrowest interface that
/// can run a query. Tests pass the same object.
class DictionaryStore {
  DictionaryStore(this._executor);

  final DatabaseExecutor _executor;

  /// Runs [query] and returns its rows. Exposed so the schema test can read
  /// `sqlite_master` and `PRAGMA table_info` through exactly the same path the
  /// engine uses, rather than through a second connection.
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? arguments,
  ]) =>
      _executor.rawQuery(sql, arguments);

  /// Every row of `meta`, keyed by `k`.
  Future<Map<String, String>> meta() async {
    final rows = await query('SELECT k, v FROM meta');
    return <String, String>{
      for (final row in rows) row['k']! as String: row['v']! as String,
    };
  }

  /// One `meta` value, or `null`.
  Future<String?> metaValue(String key) async {
    final rows = await query('SELECT v FROM meta WHERE k = ?', <Object?>[key]);
    if (rows.isEmpty) return null;
    return rows.first['v']! as String?;
  }

  /// The headwords among [norms] that exist, in no particular order.
  ///
  /// **This one query is the whole of the stemmer's dictionary check.** The
  /// README's `add` asks "is this a headword?" once per candidate; batching it
  /// into a single `IN` means resolving a word costs at most one round trip per
  /// *stage* rather than one per candidate, and a stage is bounded by the 21
  /// suffix rules plus 15 prefixes.
  Future<List<DictionaryEntry>> entriesForNorms(Iterable<String> norms) async {
    final wanted = <String>[];
    for (final norm in norms) {
      if (norm.isEmpty || wanted.contains(norm)) continue;
      wanted.add(norm);
    }
    if (wanted.isEmpty) return const <DictionaryEntry>[];
    final rows = await query(
      'SELECT id, word, norm, ipa, has_ar FROM entries '
      'WHERE norm IN (${_placeholders(wanted.length)})',
      wanted,
    );
    final byNorm = <String, DictionaryEntry>{
      for (final row in rows) row['norm']! as String: _entry(row),
    };
    return wanted
        .map((norm) => byNorm[norm])
        .whereType<DictionaryEntry>()
        .toList(growable: false);
  }

  /// Whether [norm] is a headword. The stemmer's safety net, asked directly.
  Future<bool> hasHeadword(String norm) async {
    if (norm.isEmpty) return false;
    final rows = await query(
      'SELECT 1 FROM entries WHERE norm = ? LIMIT 1',
      <Object?>[norm],
    );
    return rows.isNotEmpty;
  }

  /// The headword at [norm], with its senses and examples, or `null`.
  Future<DictionaryEntry?> entryByNorm(String norm) async {
    if (norm.isEmpty) return null;
    final rows = await query(
      'SELECT id, word, norm, ipa, has_ar FROM entries WHERE norm = ?',
      <Object?>[norm],
    );
    if (rows.isEmpty) return null;
    return _hydrate(_entry(rows.first));
  }

  /// The headwords at [norms] with their senses, in the order [norms] gives.
  ///
  /// Used by autocomplete: twenty rows of the search list are not twenty
  /// round trips.
  Future<List<DictionaryEntry>> entriesByNormsWithSenses(
    List<String> norms, {
    bool withExamples = false,
  }) async {
    final heads = await entriesForNorms(norms);
    if (heads.isEmpty) return const <DictionaryEntry>[];
    final ids = heads.map((entry) => entry.id).toList(growable: false);
    final senseRows = await query(
      'SELECT id, entry_id, pos, ar, norm_ar, en FROM senses '
      'WHERE entry_id IN (${_placeholders(ids.length)}) ORDER BY id',
      ids,
    );
    final examples = withExamples
        ? await _examplesForSenses(
            senseRows.map((row) => row['id']! as int).toList(growable: false))
        : const <int, List<String>>{};

    final byEntry = <int, List<DictionarySense>>{};
    for (final row in senseRows) {
      final senseId = row['id']! as int;
      byEntry
          .putIfAbsent(row['entry_id']! as int, () => <DictionarySense>[])
          .add(DictionarySense(
            id: senseId,
            pos: row['pos'] as String?,
            arabic: row['ar'] as String?,
            normArabic: row['norm_ar'] as String?,
            gloss: row['en'] as String?,
            examples: examples[senseId] ?? const <String>[],
          ));
    }
    return heads
        .map((head) => head.withSenses(byEntry[head.id] ?? const <DictionarySense>[]))
        .toList(growable: false);
  }

  /// Headwords whose normalised form starts with [prefix].
  ///
  /// **A range scan, not `LIKE`.** `norm >= p AND norm < p || '￿'` is a seek on
  /// the `UNIQUE(norm)` index; `LIKE 'p%'` is only optimised when SQLite's
  /// case-folding rules line up with the column's collation, which is a
  /// configuration detail rather than a guarantee. The upper bound `p` followed
  /// by U+FFFF is the smallest string greater than every string beginning with
  /// `p`, under BINARY collation - which is what `norm` is declared with.
  ///
  /// **`ORDER BY norm`, then sorted by length in Dart.** This is the shipped
  /// README's `suggest`, verbatim, including the part that reads like an
  /// oversight: it walks the map in insertion order, stops at `limit`, and only
  /// then sorts those `limit` by length. Taking the first `limit` in dictionary
  /// order and then sorting is therefore *not* the same as "the `limit` shortest
  /// matches" - it is "the `limit` first matches, shortest first".
  /// `test/data/dictionary/engine_test.dart` asserts the shipped behaviour,
  /// because the point of a faithful port is that the behaviour is the one the
  /// source documents.
  Future<List<DictionaryEntry>> headwordsWithPrefix(String prefix, {int limit = 20}) async {
    if (prefix.isEmpty || limit <= 0) return const <DictionaryEntry>[];
    final rows = await query(
      'SELECT id, word, norm, ipa, has_ar FROM entries '
      'WHERE norm >= ? AND norm < ? ORDER BY norm LIMIT ?',
      <Object?>[prefix, '$prefix\uFFFF', limit],
    );
    final matches = rows.map(_entry).toList();
    matches.sort((a, b) => a.word.length - b.word.length);
    return matches;
  }

  /// English headwords reachable from a normalised Arabic [key].
  ///
  /// **Exact key first, then the same key as a prefix** - two queries, in that
  /// order, deduplicated by entry.
  ///
  /// The prefix half is not an embellishment. 30,567 of the dictionary's Arabic
  /// senses are stored as comma-separated synonym lists - `روديسيا, زمبابوي,
  /// زيمبابوي` is one key - so a user who types one word of a three-word list
  /// finds nothing under exact matching, and a dictionary where typing
  /// `روديسيا` returns nothing while the row visibly contains it is broken.
  /// The `idx_senses_norm_ar` index makes both halves a seek.
  ///
  /// One row per headword: several senses of the same word can normalise to the
  /// same key, and a list that showed `school` three times is a list nobody
  /// reads. `MIN()` on every selected column is what makes the surviving row
  /// deterministic rather than whatever SQLite happened to visit - SQLite's
  /// documented rule is that a bare column in an aggregate query takes the value
  /// from the row that matched the single `min()`/`max()`, so using `min()`
  /// everywhere makes that row well defined.
  Future<List<ArabicSenseHit>> searchArabic(String key, {int limit = 20}) async {
    if (key.isEmpty || limit <= 0) return const <ArabicSenseHit>[];
    final exact = await _arabicQuery(
      'WHERE s.norm_ar = ?',
      <Object?>[key],
      limit,
    );
    if (exact.length >= limit) return exact;
    final seen = exact.map((hit) => hit.entry.id).toSet();
    final prefixed = await _arabicQuery(
      'WHERE s.norm_ar >= ? AND s.norm_ar < ? AND s.norm_ar <> ?',
      <Object?>[key, '$key\uFFFF', key],
      limit,
    );
    return _hydrateHits(<ArabicSenseHit>[
      ...exact,
      ...prefixed.where((hit) => seen.add(hit.entry.id)),
    ]);
  }

  /// Fills the senses of the headwords an Arabic search hit.
  ///
  /// An Arabic search answers with English headwords, and a headword without
  /// its senses is a word and nothing else - the Arabic the user typed is the
  /// *key*, and the sense that carries it is the answer. One extra query for
  /// the whole result set, not one per hit.
  Future<List<ArabicSenseHit>> _hydrateHits(List<ArabicSenseHit> hits) async {
    if (hits.isEmpty) return hits;
    final withSenses = await entriesByNormsWithSenses(
      hits.map((hit) => hit.entry.norm).toList(growable: false),
    );
    final byNorm = <String, DictionaryEntry>{
      for (final entry in withSenses) entry.norm: entry,
    };
    return <ArabicSenseHit>[
      for (final hit in hits)
        ArabicSenseHit(
          entry: byNorm[hit.entry.norm] ?? hit.entry,
        ),
    ];
  }

  /// Headwords that share at least [minimumShared] trigrams with [word], most
  /// shared first.
  ///
  /// **This is the bound that makes spell correction shippable.** Damerau
  /// distance is O(m x n) per candidate; over 31,600 headwords that is not a
  /// per-keystroke operation. The `trigrams` table reduces the comparison set to
  /// the entries that share character context with the query, and
  /// `test/data/dictionary/spelling_test.dart` measures that reduction rather
  /// than asserting it.
  ///
  /// `ORDER BY shared DESC, entry_id ASC` is not decoration either: the secondary
  /// key makes the shortlist deterministic, which is what lets the whole feature
  /// be tested.
  Future<List<({int entryId, int shared})>> spellingCandidates(
    String word, {
    int minimumShared = 1,
    int limit = 512,
  }) async {
    final grams = trigramsOf(word);
    if (grams.isEmpty) return const <({int entryId, int shared})>[];
    final rows = await query(
      'SELECT entry_id, COUNT(*) AS shared FROM trigrams '
      'WHERE t IN (${_placeholders(grams.length)}) '
      'GROUP BY entry_id HAVING shared >= ? '
      'ORDER BY shared DESC, entry_id ASC LIMIT ?',
      <Object?>[...grams, minimumShared, limit],
    );
    return <({int entryId, int shared})>[
      for (final row in rows)
        (entryId: row['entry_id']! as int, shared: row['shared']! as int),
    ];
  }

  /// How many headwords share at least [minimumShared] trigrams with [word].
  ///
  /// **The number that proves the bound.** `spellingCandidates` returns a
  /// shortlist; this returns the size of the whole pool the shortlist is drawn
  /// from, with no limit applied. A test asserts that the pool for a typo is a
  /// small fraction of the 31,600 headwords - and the pool for a *common* word
  /// is allowed to be large, which is why the shortlist is ranked by how many
  /// trigrams are shared rather than taken in table order.
  Future<int> spellingCandidatePoolSize(
    String word, {
    int minimumShared = 1,
  }) async {
    final grams = trigramsOf(word);
    if (grams.isEmpty) return 0;
    final rows = await query(
      'SELECT COUNT(DISTINCT entry_id) AS n FROM trigrams '
      'WHERE t IN (${_placeholders(grams.length)})',
      grams,
    );
    final pool = rows.first['n']! as int;
    if (minimumShared <= 1) return pool;
    final shared = await query(
      'SELECT entry_id, COUNT(*) AS shared FROM trigrams '
      'WHERE t IN (${_placeholders(grams.length)}) '
      'GROUP BY entry_id HAVING shared >= ?',
      <Object?>[...grams, minimumShared],
    );
    return shared.length;
  }

  /// Headwords by row id, with their senses and no examples.
  Future<List<DictionaryEntry>> entriesByIds(List<int> ids) async {
    if (ids.isEmpty) return const <DictionaryEntry>[];
    final rows = await query(
      'SELECT id, word, norm, ipa, has_ar FROM entries '
      'WHERE id IN (${_placeholders(ids.length)}) ORDER BY id',
      ids,
    );
    if (rows.isEmpty) return const <DictionaryEntry>[];
    return entriesByNormsWithSenses(
      rows.map((row) => row['norm']! as String).toList(growable: false),
    );
  }

  /// The distinct three-rune windows of [word], padded with two spaces.
  ///
  /// **The padding is what makes the bound work.** `child` and `childern`
  /// differ in the middle, and both carry `ild` and `ld `; without the spaces a
  /// word shorter than three runes would contribute no trigrams at all and
  /// could never be found.
  ///
  /// The implementation is in `trigrams.dart` rather than here, because the
  /// build tool cannot import a file that reaches `package:sqflite` - and a
  /// second implementation would be a second thing to keep in agreement.
  static List<String> trigramsOf(String word) => trigrams.trigramsOf(word);

  /// How many entries carry a trigram equal to [gram].
  ///
  /// Only the tests use this. It is how the "candidate set is a fraction of the
  /// dictionary" claim is turned into a number instead of a hope.
  Future<int> postingListLength(String gram) async {
    final rows = await query(
      'SELECT COUNT(*) AS n FROM trigrams WHERE t = ?',
      <Object?>[gram],
    );
    return rows.first['n']! as int;
  }

  Future<DictionaryEntry> _hydrate(DictionaryEntry head) async {
    final senseRows = await query(
      'SELECT id, entry_id, pos, ar, norm_ar, en FROM senses '
      'WHERE entry_id = ? ORDER BY id',
      <Object?>[head.id],
    );
    final examples = await _examplesForSenses(
      senseRows.map((row) => row['id']! as int).toList(growable: false),
    );
    return head.withSenses(<DictionarySense>[
      for (final row in senseRows)
        DictionarySense(
          id: row['id']! as int,
          pos: row['pos'] as String?,
          arabic: row['ar'] as String?,
          normArabic: row['norm_ar'] as String?,
          gloss: row['en'] as String?,
          examples: examples[row['id']! as int] ?? const <String>[],
        ),
    ]);
  }

  Future<Map<int, List<String>>> _examplesForSenses(List<int> senseIds) async {
    if (senseIds.isEmpty) return const <int, List<String>>{};
    final rows = await query(
      'SELECT sense_id, text FROM examples '
      'WHERE sense_id IN (${_placeholders(senseIds.length)}) ORDER BY id',
      senseIds,
    );
    final bySense = <int, List<String>>{};
    for (final row in rows) {
      bySense
          .putIfAbsent(row['sense_id']! as int, () => <String>[])
          .add(row['text']! as String);
    }
    return bySense;
  }

  Future<List<ArabicSenseHit>> _arabicQuery(
    String where,
    List<Object?> arguments,
    int limit,
  ) async {
    final rows = await query(
      'SELECT MIN(e.id) AS id, MIN(e.word) AS word, MIN(e.norm) AS norm, '
      'MIN(e.ipa) AS ipa, MIN(e.has_ar) AS has_ar, '
      'MIN(s.pos) AS pos, MIN(s.ar) AS ar, MIN(s.en) AS en '
      'FROM senses s JOIN entries e ON e.id = s.entry_id '
      '$where GROUP BY e.id ORDER BY word LIMIT ?',
      <Object?>[...arguments, limit],
    );
    return <ArabicSenseHit>[
      for (final row in rows)
        ArabicSenseHit(
          entry: DictionaryEntry(
            id: row['id']! as int,
            word: row['word']! as String,
            norm: row['norm']! as String,
            ipa: row['ipa'] as String?,
            hasArabic: (row['has_ar']! as int) != 0,
          ),
        ),
    ];
  }

  static DictionaryEntry _entry(Map<String, Object?> row) => DictionaryEntry(
        id: row['id']! as int,
        word: row['word']! as String,
        norm: row['norm']! as String,
        ipa: row['ipa'] as String?,
        hasArabic: (row['has_ar']! as int) != 0,
      );
}

/// `?, ?, ?` for a three-argument query. Built once per call rather than
/// interpolated into the SQL, so no caller can inject anything through a list
/// length.
String _placeholders(int count) => List<String>.filled(count, '?').join(', ');

/// Everything the dictionary's `meta` table must contain.
///
/// **The key names, not just the content.** `lib/data/database.dart` holds the
/// app's own `settings` table and this is a different table in a different file;
/// naming it here keeps a future reader from merging the two by accident.
const List<String> requiredMetaKeys = <String>[
  'schemaVersion',
  'name',
  'source',
  'sources',
  'license',
  'licenseUrl',
  'attributionFile',
  'generatedFrom',
  'sourceFile',
  'sourceSha256',
  'sourceBytes',
  'entryCount',
  'sourceEntryCount',
  'mergedCaseVariantCount',
  'senseCount',
  'arabicSenseCount',
  'exampleCount',
  'ipaEntryCount',
  'arabicKeyCount',
  'trigramCount',
];

/// The value `meta.schemaVersion` must hold. Checked on open; see
/// `openDictionaryDatabase`.
const String dictionarySchemaVersionKey = 'schemaVersion';

/// The expected value of `meta.schemaVersion`.
const String dictionarySchemaVersionValue = '$dictionarySchemaVersion';

/// The declared schema, as the tables and indices say it.
///
/// Only used by the schema test, and only so that the test reads the same
/// strings the build tool executed rather than a copy of them.
Map<String, String> get dictionarySchemaSql =>
    <String, String>{...dictionaryTables, ...dictionaryIndices};