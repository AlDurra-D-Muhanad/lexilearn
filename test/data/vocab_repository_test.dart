import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';

import '../helpers/test_env.dart';

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
        ],
      ),
    ]);
  });

  tearDown(() => harness.dispose());

  test('the harness hands back the repository facade, not a DAO', () {
    // The whole point of Task 5: widget tests bind to this one type and never
    // see sqflite. If this ever stops being a VocabRepository, every later
    // screen test is talking to the data layer directly.
    expect(harness.repository, isA<VocabRepository>());
  });

  test('returns every entry for an empty query', () async {
    final results = await harness.repository.search(packKey: 'en_ar', query: '   ');
    expect(results, hasLength(3));
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

  test('a malformed import leaves the database untouched', () async {
    await expectLater(harness.repository.importPack('{ not json'),
        throwsA(isA<PackDecodeException>()));
    expect((await harness.repository.packs()).map((p) => p.packKey), <String>['en_ar']);
  });

  test('exportPackJson round-trips through importPack', () async {
    final json = await harness.repository.exportPackJson('en_ar');
    await harness.repository.importPack(json);
    expect(await harness.repository.entries('en_ar'), hasLength(3));
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

  test('two harnesses live at the same time do not share a database', () async {
    // Guards the harness itself: `openAppDatabase` leaves sqflite's
    // single-instance default on, so an `:memory:` path would hand both
    // harnesses the *same* database and the second would silently inherit the
    // first's packs. This test fails the moment that regression returns.
    final fresh = await TestHarness.create();
    addTearDown(fresh.dispose);

    expect(await fresh.repository.packs(), isEmpty);
    expect(await fresh.repository.entries('en_ar'), isEmpty);

    final json = PackCodec.encodePack(VocabPack(
      schemaVersion: 1,
      packId: 'only_in_fresh',
      title: 'Only In Fresh',
      sourceLanguage: 'en',
      targetLanguage: 'ar',
      entries: const <VocabEntry>[
        VocabEntry(id: 'only-1', term: 'lantern', translations: <String>['فانوس']),
      ],
    ));
    await fresh.repository.importPack(json);

    expect((await fresh.repository.packs()).map((p) => p.packKey),
        <String>['only_in_fresh']);
    expect((await harness.repository.packs()).map((p) => p.packKey),
        <String>['en_ar']);
  });

  test('seedBundledPack installs the bundled pack once and marks it bundled',
      () async {
    final fresh = await TestHarness.create();
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
  });
}