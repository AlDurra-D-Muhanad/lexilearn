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

  /// The headwords whose normalised form starts with [prefix], **shortest
  /// first**, with their senses.
  ///
  /// **The search list's prefix band, and it is not the autocomplete.**
  /// [headwordsWithPrefix] is the shipped README's `suggest` verbatim: it takes
  /// the first [limit] matches *in dictionary order* and sorts those by length.
  /// That is the right order for a type-ahead, where the user is still typing
  /// and the words they are most likely to want are the ones that come first
  /// alphabetically. A finished search is a different thing - the word the user
  /// typed is already shown above this list, and the rest read shortest-first
  /// and then alphabetically, so the list does not reshuffle as the query grows.
  ///
  /// **The alphabetical cut is a bound, and it is stated rather than hidden.**
  /// A range scan on the `UNIQUE(norm)` index returns every headword under the
  /// prefix - ten thousand of them for a single letter - so the scan is capped
  /// at [prefixScanLimit] rows. The cap takes the *alphabetically* first, which
  /// is not the same as the shortest: `cab` sorts before `cabbage`, and a word
  /// that is a prefix of another sorts before it, so the short words are
  /// concentrated at the front of the range anyway.
  Future<List<DictionaryEntry>> entriesStartingWith(
    String prefix, {
    int limit = 50,
  }) async {
    if (prefix.isEmpty || limit <= 0) return const <DictionaryEntry>[];
    final rows = await query(
      'SELECT id, word, norm, ipa, has_ar FROM entries '
      'WHERE norm >= ? AND norm < ? ORDER BY norm LIMIT ?',
      <Object?>[prefix, '$prefix\uFFFF', prefixScanLimit],
    );
    if (rows.isEmpty) return const <DictionaryEntry>[];
    final matches = rows.map(_entry).toList()
      ..sort((a, b) {
        final byLength = a.word.length.compareTo(b.word.length);
        if (byLength != 0) return byLength;
        // The tie-break is the point: Dart's `List.sort` is **not** stable, so
        // two words of the same length could come back in either order and the
        // list would differ between two runs of the same query.
        return a.norm.compareTo(b.norm);
      });
    final heads = matches.take(limit).toList(growable: false);
    return entriesByNormsWithSenses(
      heads.map((entry) => entry.norm).toList(growable: false),
    );
  }

  /// The headwords whose **own English text** contains [text], with their
  /// senses.
  ///
  /// **The third band, and the loosest of the three.** The exact band matches a
  /// headword; the prefix band matches a headword that starts with the query;
  /// this one matches an entry whose *definition* contains the query - the
  /// dictionary stores a headword's English gloss as a sentence or a list of
  /// them, and a user who types "young person" is asking for the entry whose
  /// gloss says "a young person of either sex".
  ///
  /// **It is the mirror of the Arabic band's third case**, which is the
  /// README's own: the Arabic key is stored as a comma-separated list of
  /// synonyms and the search looks *inside* that list, because a dictionary
  /// where a row visibly contains the word but the search does not find it is
  /// broken. The English side is the same rule against the English side.
  ///
  /// **A scan, and the cost is the price.** There is no index on `senses.en` -
  /// it holds 81,451 sentences - so this is a full read of the column. Measured
  /// at **47 to 116 ms** on the shipped file, against the spell checker's
  /// 37 to 119 ms on the same path. It is the last band, it is bounded by
  /// [limit], and it is only reached for a query of at least
  /// [minimumEnglishTextQueryLength] characters - a one-letter query matches
  /// 31,339 entries and a list of twenty of them would be a lie.
  Future<List<DictionaryEntry>> entriesMentioningEnglish(
    String text, {
    int limit = 20,
  }) async {
    if (text.length < minimumEnglishTextQueryLength) {
      return const <DictionaryEntry>[];
    }
    if (limit <= 0) return const <DictionaryEntry>[];
    final rows = await query(
      'SELECT MIN(e.id) AS id, MIN(e.word) AS word, MIN(e.norm) AS norm, '
      'MIN(e.ipa) AS ipa, MIN(e.has_ar) AS has_ar '
      'FROM senses s JOIN entries e ON e.id = s.entry_id '
      "WHERE s.en IS NOT NULL AND lower(s.en) LIKE ? ESCAPE '\\' "
      'GROUP BY e.id ORDER BY word LIMIT ?',
      <Object?>['%${_escapeLike(text)}%', limit],
    );
    if (rows.isEmpty) return const <DictionaryEntry>[];
    return entriesByNormsWithSenses(
      rows.map((row) => row['norm']! as String).toList(growable: false),
    );
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
    // **The prefix half gets the budget the exact half did not spend.** The
    // first version asked for a full `limit` here, so a key with one exact hit
    // and a hundred prefix hits answered with a hundred and one rows - over the
    // limit the caller set. The limit is a promise about the size of the
    // answer, and a promise that is sometimes exceeded is not a promise.
    final prefixed = await _arabicQuery(
      'WHERE s.norm_ar >= ? AND s.norm_ar < ? AND s.norm_ar <> ?',
      <Object?>[key, '$key\uFFFF', key],
      limit - exact.length,
    );
    final merged = <ArabicSenseHit>[
      ...exact,
      ...prefixed.where((hit) => seen.add(hit.entry.id)),
    ];
    if (merged.length >= limit) return _hydrateHits(merged);

    // **The third case, and the one the list shape is about.** The two above
    // match the key at the *front* of the stored list. A user who types the
    // second or third word of `روديسيا, زمبابوي, زيمبابوي` finds nothing under
    // either, and a dictionary where the row visibly contains the word but the
    // search does not find it is broken. So the key is matched inside the list
    // as well - and it comes last, because an exact key is a better answer
    // than a word that merely appears in a list of synonyms.
    final contained = await _containedArabicQuery(key, limit - merged.length);
    return _hydrateHits(<ArabicSenseHit>[
      ...merged,
      ...contained.where((hit) => seen.add(hit.entry.id)),
    ]);
  }

  /// The headwords whose Arabic **list** holds [key] anywhere inside it.
  ///
  /// **This is the band that makes the multi-hit case work, and the first
  /// version of it did not.** 30,567 of the dictionary's Arabic senses are
  /// stored as a comma-separated list of synonyms - `رضيع, طفل, حدث, صبيّ,
  /// غلام` is one key - and a user who types the *second* of those words has
  /// to reach the row that visibly contains it.
  ///
  /// **The separator is a comma and a space, and the first version's patterns
  /// did not say so.** The stored key is the normalised whole list, and the
  /// normalisation collapses the whitespace, so the separator is `, ` -
  /// measured over the shipped file: 23,396 senses hold a comma and **one**
  /// of them holds a comma that is not followed by a space. The patterns that
  /// ignored the space therefore matched the *first* element of a list and
  /// nothing else, and the second and third words of every synonym list in
  /// the dictionary were unreachable. **Measured: the key `حكم` is carried by
  /// 44 headwords and the band found 17 of them.**
  ///
  /// **The element check is in Dart, and it is exact.** A `LIKE` says "this
  /// text contains these characters"; it cannot say "this text contains this
  /// *element*". The stored list is split on the comma and each element is
  /// compared with the key, and both sides are normalised, so the comparison
  /// is exact.
  ///
  /// **The wildcards in the key are escaped.** `LIKE` treats `%` and `_` as
  /// wildcards, and a key is a user's typing: without the escape, a query of
  /// `a_b` would match `axb`.
  Future<List<ArabicSenseHit>> _containedArabicQuery(
    String key,
    int limit,
  ) async {
    if (limit <= 0) return const <ArabicSenseHit>[];
    final escaped = _escapeLike(key);
    final rows = await query(
      'SELECT e.id AS id, e.word AS word, e.norm AS norm, '
      'e.ipa AS ipa, e.has_ar AS has_ar, s.norm_ar AS norm_ar, '
      's.pos AS pos, s.ar AS ar '
      'FROM senses s JOIN entries e ON e.id = s.entry_id '
      "WHERE s.norm_ar IS NOT NULL AND ("
      "s.norm_ar LIKE ? ESCAPE '\\' OR "
      "s.norm_ar LIKE ? ESCAPE '\\' OR "
      "s.norm_ar LIKE ? ESCAPE '\\' OR "
      "s.norm_ar LIKE ? ESCAPE '\\' OR "
      "s.norm_ar LIKE ? ESCAPE '\\') "
      'ORDER BY e.word LIMIT ?',
      <Object?>[
        // The key is the first element, whatever follows the comma.
        '$escaped,%',
        // The key is a middle element, with and without the space.
        '%, $escaped,%',
        '%,$escaped,%',
        // The key is the last element, with and without the space.
        '%, $escaped',
        '%,$escaped',
        // **Four times the answer**, because the rows are the *senses* and one
        // headword can carry several of them.
        limit * 4,
      ],
    );
    final seen = <int>{};
    final hits = <ArabicSenseHit>[];
    for (final row in rows) {
      if (!_holdsElement(row['norm_ar']! as String, key)) continue;
      final id = row['id']! as int;
      if (!seen.add(id)) continue;
      hits.add(ArabicSenseHit(
        entry: DictionaryEntry(
          id: id,
          word: row['word']! as String,
          norm: row['norm']! as String,
          ipa: row['ipa'] as String?,
          hasArabic: (row['has_ar']! as int) != 0,
        ),
        arabic: row['ar'] as String?,
        partOfSpeech: row['pos'] as String?,
      ));
      if (hits.length >= limit) break;
    }
    return hits;
  }

  /// Whether the comma-separated [list] holds [key] as one of its elements.
  ///
  /// **The elements are compared exactly, and both sides are normalised.** The
  /// stored list is the normalised whole string, so its elements are the
  /// normalised words with the separator's space trimmed off.
  static bool _holdsElement(String list, String key) {
    for (final part in list.split(',')) {
      if (part.trim() == key) return true;
    }
    return false;
  }
  /// The `LIKE` wildcards in [value], escaped.
  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

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
          // The Arabic of the matching sense is **kept** through the
          // hydration: the hydrated entry carries every sense, and the one
          // that matched is still the one the row was found by.
          arabic: hit.arabic,
          partOfSpeech: hit.partOfSpeech,
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

  /// How many headwords the study surface admits.
  ///
  /// **The number the report quotes, computed by the same rule the study
  /// surface uses.** A count written out in prose is a claim; this is the
  /// claim's arithmetic, and `test/data/dictionary/study_filter_test.dart`
  /// asserts it against the shipped data.
  Future<int> countStudyableEntries() async {
    final rows = await query(
      'SELECT COUNT(*) AS n FROM entries e WHERE ${_studyablePredicate('e')}',
    );
    return (rows.first['n']! as num).toInt();
  }

  /// The headwords the study surface admits, with their senses.
  ///
  /// **The filter is the dictionary's own, in SQL, and the same filter
  /// [StudyFilter] applies in Dart.** Two implementations of one rule is two
  /// things to keep in agreement, so the SQL and the Dart predicate are
  /// asserted against each other in `test/data/dictionary/study_filter_test.dart`
  /// over every headword in the shipped file.
  ///
  /// **The order is a hash of the row id, salted by [salt].** A deck that
  /// always dealt the same words would be a deck nobody plays twice, and an
  /// order that changed on every read would make the word of the day change
  /// within the day. The salt is the day number, so the order is stable within
  /// a day and different the next one - and it is a hash rather than a random
  /// number because a random number is not stable at all.
  Future<List<DictionaryEntry>> studyableEntries({
    int limit = 0,
    int salt = 0,
  }) async {
    final rows = await query(
      'SELECT e.id, e.word, e.norm, e.ipa, e.has_ar FROM entries e '
      'WHERE ${_studyablePredicate('e')} '
      'ORDER BY (((e.id + $salt) * 2654435761) % 1000003) ASC '
      '${limit > 0 ? 'LIMIT $limit' : ''}',
    );
    if (rows.isEmpty) return const <DictionaryEntry>[];
    final heads = rows.map(_entry).toList();
    final ids = heads.map((entry) => entry.id).toList(growable: false);
    final senseRows = await query(
      'SELECT id, entry_id, pos, ar, norm_ar, en FROM senses '
      'WHERE entry_id IN (${_placeholders(ids.length)}) ORDER BY id',
      ids,
    );
    final byEntry = <int, List<DictionarySense>>{};
    for (final row in senseRows) {
      byEntry
          .putIfAbsent(row['entry_id']! as int, () => <DictionarySense>[])
          .add(DictionarySense(
            id: row['id']! as int,
            pos: row['pos'] as String?,
            arabic: row['ar'] as String?,
            normArabic: row['norm_ar'] as String?,
            gloss: row['en'] as String?,
          ));
    }
    return heads
        .map((head) => head.withSenses(byEntry[head.id] ?? const <DictionarySense>[]))
        .toList(growable: false);
  }

  /// The SQL half of [StudyFilter].
  ///
  /// **Written once and used by both the count and the list**, so the two can
  /// never disagree about which entries are studyable.
  ///
  /// * an affix is a headword that begins with a hyphen or an elision, or one
  ///   the dictionary marks `suf` / `pref`;
  /// * a proper noun is an entry **every one** of whose senses is `prop. n`.
  ///   The clause therefore keeps an entry that has at least one sense which
  ///   is *not* a proper noun — `may` is the month and a modal verb, and the
  ///   verb is what a learner wants. An entry with no senses at all is kept,
  ///   because there is nothing to call a proper noun.
  static String _studyablePredicate(String alias) =>
      "$alias.word NOT LIKE '-%' AND $alias.word NOT LIKE '''%' "
      "AND $alias.id NOT IN (SELECT entry_id FROM senses "
      "WHERE pos IN ('suf', 'pref')) "
      "AND ($alias.id NOT IN (SELECT entry_id FROM senses) OR $alias.id IN ("
      'SELECT entry_id FROM senses GROUP BY entry_id '
      "HAVING SUM(CASE WHEN pos IS NULL OR pos <> 'prop. n' "
      'THEN 1 ELSE 0 END) > 0))';

  /// The senses whose Arabic list holds [key], however it is spelled inside
  /// the list.
  ///
  /// **The comma-separated list is the reason this is not a plain equality
  /// test.** 30,567 of the dictionary's Arabic senses are stored as a list of
  /// synonyms - `روديسيا, زمبابوي, زيمبابوي` is one key - so a user who types
  /// one word of a three-word list has to find the row that visibly contains
  /// it. The stored `norm_ar` is the normalised *whole list*, so the element
  /// has to be matched inside it.
  ///
  /// **The separator is a comma and a space, and the patterns say so.** The
  /// middle element is `, key,` and not `,key,`. Measured over the shipped
  /// file: 23,396 senses hold a comma and one of them holds a comma that is
  /// not followed by a space.
  Future<List<Map<String, Object?>>> sensesContainingArabicKey(String key) {
    if (key.isEmpty) return Future<List<Map<String, Object?>>>.value(const []);
    return query(
      'SELECT s.entry_id AS entry_id, s.id AS sense_id, s.pos AS pos, '
      's.ar AS ar, s.norm_ar AS norm_ar, s.en AS en, '
      "CASE WHEN s.norm_ar = ? THEN 0 "
      "WHEN s.norm_ar LIKE ? THEN 1 "
      "ELSE 2 END AS rank "
      'FROM senses s '
      'WHERE s.norm_ar IS NOT NULL AND ('
      's.norm_ar = ? OR '
      "s.norm_ar LIKE ? OR "
      "s.norm_ar LIKE ? OR "
      "s.norm_ar LIKE ? OR "
      "s.norm_ar LIKE ?) "
      'ORDER BY rank ASC, s.entry_id ASC',
      <Object?>[
        key,
        '$key,%',
        key,
        '$key,%',
        '%, $key,%',
        '%,$key,%',
        '%, $key',
      ],
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
          arabic: row['ar'] as String?,
          partOfSpeech: row['pos'] as String?,
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

/// How many rows the prefix band's range scan may read before it is cut.
///
/// **A bound, and a generous one.** A single letter is a prefix of thousands
/// of headwords and the range scan on the `UNIQUE(norm)` index would read all
/// of them; 500 rows is enough for the sort to have the short words in front
/// of it and small enough to be free.
const int prefixScanLimit = 500;

/// The shortest query the English-text band will answer.
///
/// **Four characters, and the same floor the spell checker uses.** One
/// character matches 31,339 entries and two match thousands, and a list of
/// twenty of them would say nothing at all. The floor is the reason the band
/// exists in this shape: it is for a phrase the user has finished typing, not
/// for the first letter of one.
const int minimumEnglishTextQueryLength = 4;

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
  // **The attribution record**, written by the build tool from the upstream
  // project's own configuration. `docs/dictionary-attribution.md` records
  // where each string came from; nothing here is paraphrased.
  'upstreamProject',
  'upstreamProjectUrl',
  'upstreamTagline',
  'upstreamPair',
  'upstreamPairDescription',
  'sourceLicenses',
  'sourceCredits',
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