import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/search/search_controller.dart';

import '../helpers/test_env.dart';

/// The controller is the screen's only door onto the data layer, so it is
/// tested against a real repository and a real database rather than a mock:
/// the interesting failure is the one where a pack key does not exist.
void main() {
  late TestHarness harness;
  late SearchController controller;

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[
      VocabPack(
        schemaVersion: 1,
        packId: 'p',
        title: 'P',
        sourceLanguage: 'en',
        targetLanguage: 'ar',
        entries: const [
          VocabEntry(id: 'a', term: 'ghost clusters', translations: ['أشباح عنقودية']),
          VocabEntry(id: 'b', term: 'Buried', translations: ['دفن']),
        ],
      ),
    ]);
    controller = SearchController(repository: harness.repository);
  });

  tearDown(() => harness.dispose());

  // NOTE ON `packKey`
  // `search` defaults `packKey` to the last one used, and a fresh controller has
  // never been given one — so every test below that expects a pack's entries
  // names the pack. The one case that does not is pinned separately, under
  // "with no pack known yet", because that answer is part of the contract.

  test('an empty query returns every entry in the pack', () async {
    await controller.search('', packKey: 'p');
    expect(controller.results, hasLength(2));
    expect(controller.isSearching, isFalse);
  });

  test('a query narrows the results and notifies listeners', () async {
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.search('buried', packKey: 'p');
    expect(controller.results.single.term, 'Buried');
    expect(notifications, greaterThan(0));
  });

  test('an unmatched query yields no results rather than an error', () async {
    await controller.search('qqqq', packKey: 'p');
    expect(controller.results, isEmpty);
    expect(controller.error, isNull);
  });

  test('an unknown pack answers with nothing rather than an error', () async {
    // `PackDao.entriesOf` is a plain query, so a pack key that is not installed
    // yields an empty list and never throws. That is the real behaviour, and it
    // is indistinguishable from "you searched for something nobody has" — which
    // is why this is pinned rather than left to be discovered on the screen.
    await controller.search('x', packKey: 'missing');
    expect(controller.error, isNull);
    expect(controller.results, isEmpty);
  });

  test('a failing read reports a readable error instead of throwing', () async {
    // A row whose `translations` column is not JSON makes `entriesOf` throw a
    // `FormatException` from inside `jsonDecode`. This is the case the
    // controller's `error` field exists for, and it must not escape into the
    // widget tree: `search` is called from a timer.
    await harness.database.insert('entries', <String, Object?>{
      'entry_id': 'corrupt-1',
      'pack_key': 'p',
      'term': 'corrupt',
      'translations': 'not json at all',
      'sort_index': 99,
    });

    await controller.search('buried', packKey: 'p');
    expect(controller.error, isNotNull);
    expect(controller.error, isA<FormatException>());
    expect(controller.results, isEmpty);
  });

  test('clear resets query and results', () async {
    await controller.search('buried', packKey: 'p');
    controller.clear();
    expect(controller.query, isEmpty);
    expect(controller.results, isEmpty);
  });

  // --- Beyond the plan's five: the state the Home screen actually reads. ---

  test('with no pack known yet a search finds nothing and reports no error',
      () async {
    // An empty answer, not a failure — pinned so that "the key was forgotten"
    // cannot be mistaken for "the database is broken" on the screen.
    await controller.search('buried');
    expect(controller.results, isEmpty);
    expect(controller.error, isNull);
  });

  test('the query is kept verbatim so the field can echo it back', () async {
    await controller.search('  GhOST  ', packKey: 'p');
    expect(controller.query, '  GhOST  ');
    expect(controller.results.single.term, 'ghost clusters');
  });

  test('the pack key is remembered, so a re-run needs no second argument', () async {
    // This is the whole reason `packKey` is optional on `search`: after the user
    // switches packs the screen re-runs the query it already has rather than
    // tracking the active key itself.
    await controller.search('buried', packKey: 'p');
    await controller.search('buried');
    expect(controller.results.single.term, 'Buried');
  });

  test('a pack switch narrows the results to the new pack', () async {
    // Written out rather than built with `PackCodec` so the test states what the
    // second pack contains without importing the encoder.
    await harness.repository.importPack(
      '{"schemaVersion":1,"packId":"other","title":"Other",'
      '"sourceLanguage":"en","targetLanguage":"ar","entries":'
      '[{"id":"z","term":"lantern","translations":["فانوس"]}]}',
    );

    await controller.search('a', packKey: 'other');
    expect(controller.results.single.term, 'lantern');
  });

  test('isSearching is true for the duration of the read and false after', () async {
    final seen = <bool>[];
    controller.addListener(() => seen.add(controller.isSearching));

    await controller.search('buried', packKey: 'p');

    expect(seen.first, isTrue, reason: 'the first notification must be "busy"');
    expect(seen.last, isFalse, reason: 'the last notification must be "done"');
    expect(controller.isSearching, isFalse);
  });

  test('an error does not survive the next successful search', () async {
    await harness.database.insert('entries', <String, Object?>{
      'entry_id': 'corrupt-1',
      'pack_key': 'p',
      'term': 'corrupt',
      'translations': 'not json at all',
      'sort_index': 99,
    });
    await controller.search('buried', packKey: 'p');
    expect(controller.error, isNotNull);

    // Repair the row the way a pack re-import would, then search again. The
    // stale error must be gone, not merely overwritten by the next failure.
    await harness.database.update(
      'entries',
      <String, Object?>{'translations': '["مدفون"]'},
      where: 'entry_id = ?',
      whereArgs: <Object?>['corrupt-1'],
    );
    await controller.search('buried', packKey: 'p');
    expect(controller.error, isNull);
    expect(controller.results.single.term, 'Buried');
  });

  test('clear leaves isSearching false', () async {
    controller.clear();
    expect(controller.isSearching, isFalse);
    expect(controller.error, isNull);
  });

  test('an Arabic query matches the translation', () async {
    await controller.search('دفن', packKey: 'p');
    expect(controller.results.single.term, 'Buried');
  });

  test('a search that lands after dispose does not throw', () async {
    // The real failure this guards: the Home screen's debounced read is still in
    // flight when the user leaves, and `notifyListeners()` on a disposed
    // `ChangeNotifier` throws a FlutterError in debug and asserts in release.
    // Start the read, dispose, then let it finish.
    final inFlight = controller.search('buried', packKey: 'p');
    controller.dispose();

    await expectLater(inFlight, completes);
  });
}
