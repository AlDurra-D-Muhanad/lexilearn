import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/dictionary_pack.dart';
import 'package:lexilearn/domain/my_favourites_pack.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/flashcards/flashcard_controller.dart';

import '../helpers/test_env.dart';

/// The derived pack's progress, through the deck that draws from it.
///
/// **The repository's own tests pin the rule** — an answer given about a
/// derived pack's word is filed in the pack the word came from — and this
/// file pins the path the app takes to get there: the deck is dealt from the
/// derived pack's own entries, which carry the namespaced ids, and the
/// controller hands the pack key and the entry id to `recordAnswer` as they
/// are.
///
/// **A plain `test`, not a `testWidgets`.** Nothing here is a widget, and the
/// controller's read of the pack is a real future — a `testWidgets` body runs
/// in a fake-async zone where it would never answer on its own.
/// `docs/engineering-standards.md` §5.
void main() {
  late TestHarness harness;
  late VocabRepository repository;

  /// One word, saved, so the deck has exactly one card.
  const starterPack = VocabPack(
    schemaVersion: 1,
    packId: starterPackKey,
    title: 'English to Arabic',
    sourceLanguage: 'en',
    targetLanguage: 'ar',
    entries: <VocabEntry>[
      VocabEntry(
        id: 'ghost-clusters-4da03e',
        term: 'ghost clusters',
        translations: <String>['شبح'],
      ),
    ],
  );

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[starterPack]);
    repository = harness.repository;
  });

  tearDown(() => harness.dispose());

  test('the deck with the derived pack active records the answer in the pack '
      'the word came from', () async {
    await repository.setFavorite(
      packKey: starterPackKey,
      entryId: 'ghost-clusters-4da03e',
      isFavorite: true,
    );

    final controller = FlashcardController(
      repository: repository,
      packKey: myFavouritesPackKey,
      cardCount: 1,
    );
    addTearDown(controller.dispose);
    await controller.start();

    // **The card is the saved word**, under the derived pack's own id — the
    // id the controller hands to `recordAnswer`.
    expect(controller.current, isNotNull);
    expect(controller.current!.id, 'myfav:english_ar_v1:ghost-clusters-4da03e');

    await controller.answer(knewIt: true);

    // **And the answer is in the pack the word came from.**
    final source = await repository.stats(starterPackKey);
    expect(source.totalAttempts, 1);
    expect(source.totalCorrect, 1);
    // **The derived pack sees the same record**, because it is the same
    // record and not a copy of it.
    expect((await repository.stats(myFavouritesPackKey)).totalAttempts, 1);
    // **And there is no row under the derived pack's own key.**
    final rows = await harness.database.query('word_progress');
    expect(rows, hasLength(1));
    expect(rows.single['pack_key'], starterPackKey);
    expect(rows.single['entry_id'], 'ghost-clusters-4da03e');
  });
}
