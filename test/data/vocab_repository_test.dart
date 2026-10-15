import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';

import '../helpers/test_env.dart';

/// Everything the repository exposes, flattened to plain values that two
/// snapshots can be compared with `expect`.
///
/// The fields are projected explicitly rather than comparing the objects
/// directly, because `PackSummary` does not implement `operator ==` — two
/// identical summaries compare unequal by identity, which would make this
/// helper report a change on every single call.
///
/// Takes the harness rather than a `VocabRepository` so this file needs no
/// import of the type under test.
Future<List<Object?>> _snapshot(TestHarness harness) async {
  final seen = <Object?>[];
  for (final summary in await harness.repository.packs()) {
    seen.add(<Object?>[
      'pack',
      summary.packKey,
      summary.title,
      summary.sourceLanguage,
      summary.targetLanguage,
      summary.entryCount,
      summary.isBundled,
      summary.importedAt.toUtc().toIso8601String(),
    ]);
    for (final entry in await harness.repository.entries(summary.packKey)) {
      seen.add(<Object?>[
        'entry',
        entry.id,
        entry.term,
        entry.translations,
        entry.note,
        entry.phonetic,
        entry.partOfSpeech,
        entry.synonyms,
        entry.examples,
      ]);
    }
  }
  return seen;
}

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[
      VocabPack(
        schemaVersion: 1,
        packId: 'en_ar',
        title: 'English to Arabic',
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: const <VocabEntry>[
          VocabEntry(id: 'fever-1', term: 'fever', translations: <String>['حمى']),
          VocabEntry(
              id: 'buried-1', term: 'Buried', translations: <String>['دفن', 'مدفون']),
          VocabEntry(id: 'checkup-1', term: 'checkup', translations: <String>['فحص']),
          VocabEntry(
              id: 'multi-1', term: 'multi   space', translations: <String>['مسافة']),
        ],
      ),
    ]);
  });

  tearDown(() => harness.dispose());

  test('returns every entry for an empty query', () async {
    final results = await harness.repository.search(packKey: 'en_ar', query: '   ');
    expect(results, hasLength(4));
  });

  test('matches an English term case-insensitively', () async {
    final results = await harness.repository.search(packKey: 'en_ar', query: 'BURI');
    expect(results.single.term, 'Buried');
  });

  test('matches a substring in the middle of a term', () async {
    final results = await harness.repository.search(packKey: 'en_ar', query: 'heck');
    expect(results.single.term, 'checkup');
  });

  test('matches an Arabic translation', () async {
    final results = await harness.repository.search(packKey: 'en_ar', query: 'مدفون');
    expect(results.single.term, 'Buried');
  });

  test('matches across a run of internal whitespace in the term', () async {
    // 'multi   space' is stored verbatim. Both a single-space query and a
    // differently-cased multi-space query must reach it, which only holds if
    // whitespace is collapsed on both sides before comparison.
    expect(
        await harness.repository.search(packKey: 'en_ar', query: 'multi space'),
        hasLength(1));
    expect(
        await harness.repository
            .search(packKey: 'en_ar', query: 'MULTI   SPACE'),
        hasLength(1));
  });

  test('returns nothing when no entry matches', () async {
    expect(await harness.repository.search(packKey: 'en_ar', query: 'zzzz'), isEmpty);
  });

  test('imports a pack and makes it searchable', () async {
    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'imported',
      title: 'Imported',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'extra-1', term: 'lantern', translations: <String>['فانوس']),
      ],
    ));

    final pack = await harness.repository.importPack(json);
    expect(pack.packId, 'imported');
    expect((await harness.repository.packs()).map((p) => p.packKey),
        contains('imported'));
    expect(await harness.repository.search(packKey: 'imported', query: 'lant'),
        hasLength(1));
  });

  test('every rejected document leaves the database byte-for-byte unchanged',
      () async {
    // Every one of these parses as JSON and is rejected only by the *strict*
    // pack decode. That is the point: a document that dies inside jsonDecode
    // proves nothing about ordering, because no implementation could have
    // written anything before it failed. These fail after parsing, so an
    // implementation that writes a placeholder row before the strict decode
    // gets caught here.
    const rejected = <String, String>{
      'not JSON at all': '{ not json',
      'unsupported schemaVersion':
          '{"schemaVersion":99,"packId":"ghost","title":"t","entries":[]}',
      'a backup document':
          '{"kind":"backup","schemaVersion":1,"packId":"ghost","title":"t","entries":[]}',
      'a missing entries list': '{"schemaVersion":1,"packId":"ghost","title":"t"}',
      'two entries sharing an id':
          '{"schemaVersion":1,"packId":"ghost","title":"t","entries":['
              '{"id":"dup","term":"A","translations":["x"]},'
              '{"id":"dup","term":"B","translations":["y"]}]}',
      'an empty term':
          '{"schemaVersion":1,"packId":"ghost","title":"t","entries":['
              '{"id":"g1","term":"  ","translations":["x"]}]}',
      'a non-string translation':
          '{"schemaVersion":1,"packId":"ghost","title":"t","entries":['
              '{"id":"g1","term":"A","translations":[7]}]}',
    };

    // The fixture pack has four entries, so the entries half of the snapshot is
    // non-empty and a clobbered entry row would actually be visible.
    expect(await harness.repository.entries('en_ar'), hasLength(4));

    for (final document in rejected.entries) {
      final before = await _snapshot(harness);

      await expectLater(
        harness.repository.importPack(document.value),
        throwsA(isA<PackDecodeException>()),
        reason: '"${document.key}" must be rejected',
      );

      expect(await _snapshot(harness), before,
          reason: 'a failed import of "${document.key}" changed the database');
    }
  });

  test('exportPackJson round-trips through importPack', () async {
    final json = await harness.repository.exportPackJson('en_ar');
    await harness.repository.importPack(json);
    expect(await harness.repository.entries('en_ar'), hasLength(4));
  });

  test('exportPackJson throws a readable error for an unknown pack', () async {
    await expectLater(harness.repository.exportPackJson('nope'),
        throwsA(isA<PackDecodeException>()));
  });

  test('deletePack removes the pack and its entries', () async {
    await harness.repository.deletePack('en_ar');
    expect(await harness.repository.packs(), isEmpty);
    expect(await harness.repository.entries('en_ar'), isEmpty);
  });

  // --- Beyond the brief: interface surface the brief's tests do not reach. ---

  test('a bidi control character on either side does not block a match', () async {
    // The source dataset really does contain bidi marks, and the plan's global
    // rule strips them on ingest. Either way a user pasting text out of a
    // rich-text editor must still find the word.
    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'bidi',
      title: 'Bidi',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'bidi-1', term: 'serenity', translations: <String>['الهدوء\u200f']),
      ],
    ));
    await harness.repository.importPack(json);

    expect(await harness.repository.search(packKey: 'bidi', query: 'الهدوء'),
        hasLength(1));
    expect(
        await harness.repository.search(packKey: 'bidi', query: 'الهدوء\u200e'),
        hasLength(1));
  });

  test('invisible marks never block a match on either side', () async {
    // U+061C ARABIC LETTER MARK is the one most likely to appear in Arabic text
    // pasted out of a rich-text editor; the zero-width family rides with it.
    // Each mark is embedded in its own entry, so every entry normalises to the
    // same clean text and a clean query must reach all of them.
    const marks = <String>['\u061c', '\u200b', '\u200c', '\u200d', '\ufeff'];
    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'marks',
      title: 'Marks',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: <VocabEntry>[
        for (var i = 0; i < marks.length; i++)
          VocabEntry(
            id: 'mark-$i',
            term: 'mark${marks[i]}ed',
            translations: <String>['تع${marks[i]}ريب'],
          ),
      ],
    ));
    await harness.repository.importPack(json);

    for (final mark in marks) {
      final label = 'U+${mark.codeUnitAt(0).toRadixString(16).toUpperCase()}';
      expect(await harness.repository.search(packKey: 'marks', query: 'marked'),
          hasLength(marks.length), reason: '$label inside the term');
      expect(await harness.repository.search(packKey: 'marks', query: 'تعريب'),
          hasLength(marks.length), reason: '$label inside the translation');
    }
  });

  test('importPack stamps importedAt from the injected clock, not the wall',
      () async {
    // Task 7 records progress against the same clock. If importPack ever falls
    // back to DateTime.now(), that pinning breaks silently.
    final pinned = DateTime.utc(2031, 3, 4, 5, 6, 7);
    final fresh = await TestHarness.create(now: pinned);
    addTearDown(fresh.dispose);

    await fresh.repository.importPack(PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'timed',
      title: 'Timed',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'timed-1', term: 'a', translations: <String>['b']),
      ],
    )));

    expect((await fresh.repository.packs()).single.importedAt, pinned);
  });

  test('three harnesses live at the same time do not share a database',
      () async {
    // Guards the harness itself: the harnesses open `:memory:` with
    // `singleInstance: false`. Left at the default, sqflite keys its
    // open-database helper by path and would hand every harness in this isolate
    // the *same* database — each one created successfully and silently wrong.
    final second = await TestHarness.create();
    addTearDown(second.dispose);
    final third = await TestHarness.create();
    addTearDown(third.dispose);

    for (final empty in <TestHarness>[second, third]) {
      expect(await empty.repository.packs(), isEmpty);
      expect(await empty.repository.entries('en_ar'), isEmpty);
    }

    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'only_in_second',
      title: 'Only In Second',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'only-1', term: 'lantern', translations: <String>['فانوس']),
      ],
    ));
    await second.repository.importPack(json);

    expect((await second.repository.packs()).map((p) => p.packKey),
        <String>['only_in_second']);
    expect((await third.repository.packs()), isEmpty);
    expect((await harness.repository.packs()).map((p) => p.packKey),
        <String>['en_ar']);
  });

  test('seedBundledPack installs the bundled pack once and marks it bundled',
      () async {
    // Pinned far from the wall clock: the default harness clock sits close to
    // real time, which is exactly why a seeding path that ignored it went
    // unnoticed.
    final pinned = DateTime.utc(2031, 3, 4, 5, 6, 7);
    final fresh = await TestHarness.create(now: pinned);
    addTearDown(fresh.dispose);
    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'english_ar_v1',
      title: 'English to Arabic',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'x-1', term: 'fever', translations: <String>['حمى']),
        VocabEntry(id: 'x-2', term: 'checkup', translations: <String>['فحص']),
      ],
    ));

    expect(await fresh.repository.seedBundledPack(json), isTrue);
    expect(await fresh.repository.seedBundledPack(json), isFalse);

    final summary = (await fresh.repository.packs()).single;
    expect(summary.packKey, 'english_ar_v1');
    expect(summary.isBundled, isTrue);
    expect(summary.entryCount, 2);
    expect(summary.importedAt, pinned);
  });

  test('seedBundledPack rejects a corrupt asset without writing anything',
      () async {
    final before = await _snapshot(harness);
    await expectLater(
        harness.repository.seedBundledPack('{"schemaVersion":99,"packId":"g",'
            '"title":"t","entries":[]}'),
        throwsA(isA<PackDecodeException>()));
    expect(await _snapshot(harness), before);
  });
}