import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/home/home_screen.dart';
import 'package:lexilearn/ui/more/more_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_controller.dart';
import 'package:lexilearn/ui/quiz/quiz_screen.dart';
import 'package:lexilearn/ui/quiz/quiz_setup_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:provider/provider.dart';

import '../helpers/test_env.dart';

/// The "My Favourites" pack, on the screens.
///
/// **The derived pack is a pack like any other, so it has to work on every
/// surface a pack works on**: it is listed, it can be chosen, and once chosen
/// the word of the day, the deck and the quiz all draw from it. Those are the
/// four questions the specification asks to be settled, and this file settles
/// them through the real app rather than through the repository alone.
///
/// The user's own words: «حزمة مفضلتي يجب ان تكون مستقلة تزداد كلماتها و
/// تنقص كلما اضاف المستخدم كلمة الى المفضلة او ازال كلمة اي اي بكل بساطة
/// هي حزمة جديدة يتم ملؤها و تفريغها من قبل المستخدم عبر اضافة كلمة او
/// ازالة كلمة من اي من الحزمتين المدمجتين حاليا».
/// The pack the fixture installs.
///
/// **Four words, so the quiz has something to choose from and the favourites
/// are a strict subset of it.** Two of the four are saved in the quiz test,
/// and the assertion that the quiz's options are drawn from those two alone
/// is what proves the quiz read the favourites rather than the pack.
const _pack = VocabPack(
  schemaVersion: 1,
  packId: 'en_ar',
  title: 'English to Arabic',
  sourceLanguage: 'en',
  targetLanguage: 'ar',
  entries: <VocabEntry>[
    VocabEntry(
      id: 'serenity-1',
      term: 'serenity',
      translations: <String>['الهدوء والسكينة'],
    ),
    VocabEntry(id: 'ambition-1', term: 'ambition', translations: <String>['طموح']),
    VocabEntry(id: 'fervour-1', term: 'fervour', translations: <String>['حماس']),
    VocabEntry(id: 'clarity-1', term: 'clarity', translations: <String>['وضوح']),
  ],
);

/// The chrome, spelled out rather than read out of the screens' own private
/// constants — a test that reached into a screen's constants could not fail
/// for the reason it exists.
const String _derivedTitle = 'مفضلتي';
const String _derivedChip = 'من المفضلة';
const String _bundledChip = 'مدمجة';
const String _activePack = 'الحزمة الحالية';
const String _startQuiz = 'ابدأ الاختبار';
const String _emptyDeck = 'لا توجد بطاقات بعد';

/// Saves the words with these ids, from the fixture pack.
///
/// `tester.runAsync`, because a `testWidgets` body runs in a fake-async zone
/// where a real sqflite future never answers on its own.
Future<void> _save(
  WidgetTester tester,
  VocabRepository repository,
  List<String> entryIds,
) =>
    tester.runAsync(() async {
      for (final entryId in entryIds) {
        await repository.setFavorite(
          packKey: 'en_ar',
          entryId: entryId,
          isFavorite: true,
        );
      }
    });

/// Removes the word with this id, from the fixture pack.
Future<void> _unsave(
  WidgetTester tester,
  VocabRepository repository,
  String entryId,
) =>
    tester.runAsync(() => repository.setFavorite(
          packKey: 'en_ar',
          entryId: entryId,
          isFavorite: false,
        ));

/// Goes to the More screen and picks the derived pack out of the list.
///
/// **Through the real screen, because "the derived pack must be selectable
/// like any other" is a claim about the app and not about the repository.**
Future<void> _chooseTheDerivedPack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.apps));
  await tester.pumpAndSettle();
  await settleDatabase(tester);

  final row = find.text(_derivedTitle);
  expect(row, findsOneWidget,
      reason: 'the derived pack is in the list, with its size');
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
  await settleDatabase(tester);
}

/// The derived pack's own row on the More screen.
///
/// **The row, not the page.** The row is the `AppSurface` the pack's title
/// sits in, and everything asserted about this pack has to be scoped to it —
/// a `findsNothing` over the whole page would be a claim about every pack
/// at once, and the fixture pack beside it *is* deletable.
Finder derivedRow() => find.ancestor(
      of: find.text(_derivedTitle),
      matching: find.byType(AppSurface),
    );

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create(packs: <VocabPack>[_pack]);
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets('the pack list names the derived pack, and says where its words '
      'come from', (tester) async {
    await _save(tester, harness.repository, <String>['serenity-1']);

    await pumpShell(tester, harness.repository);
    await tester.tap(find.byIcon(Icons.apps));
    await tester.pumpAndSettle();
    await settleDatabase(tester);

    expect(find.byType(MoreScreen), findsOneWidget);
    expect(find.text(_derivedTitle), findsOneWidget);
    // **Its own chip, and not the bundled one.** The two integrated packs are
    // the ones the user called «المدمجتين»; this one is a new pack the user
    // fills and empties, and saying "bundled" would say it is a third dataset
    // shipped with the app.
    expect(find.text(_derivedChip), findsOneWidget);
    expect(
      find.descendant(of: derivedRow(), matching: find.text(_bundledChip)),
      findsNothing,
      reason: 'the derived pack is the user\'s own curation, not a bundled '
          'dataset',
    );
    // **Its size is the number of saved words.**
    expect(find.text('1 كلمة'), findsOneWidget);
    // **And it is not deletable** — it has no rows on the device to delete.
    expect(
      find.descendant(
        of: derivedRow(),
        matching: find.byIcon(Icons.delete_outline),
      ),
      findsNothing,
    );
  });

  testWidgets('the derived pack does not become the active pack by accident',
      (tester) async {
    // **The active pack is what the word of the day and the flashcards draw
    // from.** A derived pack that took over the app the moment a user saved
    // one word would be a bug, not a feature.
    await _save(tester, harness.repository, <String>['serenity-1']);

    await pumpShell(tester, harness.repository);
    await tester.tap(find.byIcon(Icons.apps));
    await tester.pumpAndSettle();
    await settleDatabase(tester);

    // **The active pack is the fixture pack**, and the derived pack's own row
    // does not carry the "this is the one" mark.
    expect(find.text(_activePack), findsOneWidget);
    expect(
      find.descendant(of: derivedRow(), matching: find.text(_activePack)),
      findsNothing,
      reason: 'the derived pack was not made active by being saved',
    );
  });

  testWidgets('the quiz chooser offers the derived pack, and choosing it '
      'quizzes the favourites', (tester) async {
    // **Two of the four words saved**, so the derived pack is a strict subset
    // of the pack and the assertion below can tell the two apart.
    await _save(tester, harness.repository, <String>['serenity-1', 'ambition-1']);

    await pumpShell(tester, harness.repository);
    await tester.tap(find.byIcon(Icons.check_box_outlined));
    await tester.pumpAndSettle();
    await settleDatabase(tester);
    expect(find.byType(QuizSetupScreen), findsOneWidget);

    // **The chooser lists it, with the number of saved words.**
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('$_derivedTitle (2)'), findsOneWidget);
    await tester.tap(find.text('$_derivedTitle (2)'));
    await tester.pumpAndSettle();
    await settleDatabase(tester);

    // **The pill above the picker names it.**
    expect(find.text(_derivedTitle), findsOneWidget);

    // **And the quiz draws from the favourites.**
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.widgetWithText(FilledButton, _startQuiz));
    await tester.pumpAndSettle();
    await settleDatabase(tester);

    expect(find.byType(QuizScreen), findsOneWidget);
    final controller = Provider.of<QuizController>(
      tester.element(find.byType(QuizScreen)),
      listen: false,
    );
    final question = controller.question!;
    expect(
      <String>['serenity', 'ambition'],
      contains(question.answer.term),
      reason: 'the quiz asked one of the saved words',
    );
    // **Every option is a saved word's meaning** — and neither of the two
    // words the user did *not* save is among them. The pool is the two saved
    // words, so the options are exactly their two meanings.
    expect(
      question.options.map((option) => option.text).toSet(),
      <String>{'الهدوء والسكينة', 'طموح'},
    );
  });

  testWidgets('the deck with one favourite in it deals that word, and the '
      'counter reads 1/1', (tester) async {
    await _save(tester, harness.repository, <String>['serenity-1']);

    await pumpShell(tester, harness.repository);
    await _chooseTheDerivedPack(tester);

    await tester.tap(find.byIcon(Icons.style_outlined));
    await tester.pumpAndSettle();
    await settleDatabase(tester);

    // **The one saved word is the card**, and the counter knows the deck is
    // one card long rather than ten.
    expect(find.text('serenity'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
  });

  testWidgets('and the deck says so when the last favourite goes', (tester) async {
    await _save(tester, harness.repository, <String>['serenity-1']);

    await pumpShell(tester, harness.repository);
    await _chooseTheDerivedPack(tester);

    // **The user unsaves the word while the derived pack is the active one.**
    // The pack is computed from the favourites, so it is now empty — and the
    // deck has to say so rather than deal a card it does not have.
    await _unsave(tester, harness.repository, 'serenity-1');

    await tester.tap(find.byIcon(Icons.style_outlined));
    await tester.pumpAndSettle();
    await settleDatabase(tester);

    expect(find.text(_emptyDeck), findsOneWidget);
    expect(find.text('serenity'), findsNothing);
  });

  testWidgets('the word of the day with the derived pack active is a favourite',
      (tester) async {
    await _save(tester, harness.repository, <String>['serenity-1']);

    await pumpShell(tester, harness.repository);
    await _chooseTheDerivedPack(tester);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    await settleDatabase(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    // **The card is drawn, and it holds the saved word** — the derived pack's
    // only entry. This is correct behaviour and it is said out loud here rather
    // than discovered later.
    expect(find.text('serenity'), findsOneWidget);
  });
}
