import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/custom_dictionary.dart';
import 'package:lexilearn/ui/custom_dictionary/add_custom_word_screen.dart';
import 'package:lexilearn/ui/settings/app_overflow_menu.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../helpers/test_env.dart';

/// The screen's copy, in Arabic.
const _title = 'إنشاء قاموسك الخاص';
const _subtitle = 'أضف كلماتك ومعانيها كما تريد';
const _wordRequired = 'اكتب الكلمة أولاً.';
const _meaningRequired = 'اكتب معنى الكلمة أولاً.';
const _duplicate = 'هذه الكلمة موجودة في قاموسك بالفعل.';
const _success = 'تم إضافة الكلمة بنجاح';
const _done = 'تم';
const _save = 'حفظ الكلمة';

/// The keys the screen puts on its two fields, by their string values.
const Key _wordField = ValueKey<String>('custom-word-field');
const Key _meaningField = ValueKey<String>('custom-meaning-field');

/// Mounts the add screen with every provider it and its overflow menu read.
Widget _host(VocabRepository repository) => MultiProvider(
  providers: <SingleChildWidget>[
    Provider<VocabRepository>.value(value: repository),
    ...appSeamProviders(settings: createAppSettings(repository)),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.light,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const AddCustomWordScreen(),
  ),
);

Future<void> _pumpAdd(WidgetTester tester, VocabRepository repository) async {
  await tester.pumpWidget(_host(repository));
  await settleDatabase(tester);
}

String _fieldText(WidgetTester tester, Key key) =>
    tester.widget<TextField>(find.byKey(key)).controller!.text;

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets('both fields are required, inline, and nothing is written', (
    tester,
  ) async {
    useAPhone(tester);
    await _pumpAdd(tester, harness.repository);

    // Whitespace is not a word and not a meaning: the refusal is about trimmed
    // text, not about the field having had a keystroke.
    await tester.enterText(find.byKey(_wordField), '   ');
    await tester.enterText(find.byKey(_meaningField), '   ');

    final before = harness.operationsStarted;
    await tester.tap(find.text(_save));
    await tester.pump();

    expect(find.text(_wordRequired), findsOneWidget);
    expect(find.text(_meaningRequired), findsOneWidget);
    expect(find.text(_success), findsNothing);

    // The refusal happened before the repository was asked, so there is not
    // even a write to observe — and the dictionary is still empty.
    expect(harness.operationsStarted, before);
    final words = await readOutsideFakeAsync(
      tester,
      () => harness.repository.customWords(),
    );
    expect(words, isEmpty);
  });

  testWidgets('a missing meaning is named under the meaning field', (
    tester,
  ) async {
    useAPhone(tester);
    await _pumpAdd(tester, harness.repository);

    await tester.enterText(find.byKey(_wordField), 'serendipity');
    await tester.tap(find.text(_save));
    await tester.pump();

    expect(find.text(_wordRequired), findsNothing);
    expect(find.text(_meaningRequired), findsOneWidget);
    expect(find.text(_success), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(_wordField)).maxLength,
      customWordMaxLength,
    );
    expect(
      tester.widget<TextField>(find.byKey(_meaningField)).maxLength,
      customMeaningMaxLength,
    );
  });

  testWidgets('the meaning field starts three lines tall, as the drawing has it',
      (tester) async {
    useAPhone(tester);
    await _pumpAdd(tester, harness.repository);

    // **The drawing's meaning field is 220 px in its 852-px-wide mock** — about
    // 93 dp, which is three 24-dp lines plus the field's own padding. Five lines
    // made it a 152-dp capsule on the phone: the field, not the words, became
    // the largest thing on the screen. The literal is the drawing's, not the
    // implementation's.
    final field = tester.widget<TextField>(find.byKey(_meaningField));
    expect(field.minLines, 3);
    expect(field.maxLines, 8,
        reason: 'a long meaning still has room to grow before it scrolls');
  });

  testWidgets('a valid word shows the success dialog, clears and stays', (
    tester,
  ) async {
    useAPhone(tester);
    await _pumpAdd(tester, harness.repository);

    await tester.enterText(find.byKey(_wordField), '  serendipity  ');
    await tester.enterText(
      find.byKey(_meaningField),
      'صدفة سعيدة، اكتشاف غير متوقع.',
    );
    await tester.tap(find.text(_save));
    await settleDatabase(tester);

    expect(find.text(_success), findsOneWidget);
    // The screen is under the dialog rather than replaced by it.
    expect(find.byType(AddCustomWordScreen), findsOneWidget);

    await tester.tap(find.text(_done));
    await tester.pumpAndSettle();

    expect(find.text(_success), findsNothing);
    // Still here, so the next pair can be typed without leaving.
    expect(find.byType(AddCustomWordScreen), findsOneWidget);
    expect(_fieldText(tester, _wordField), isEmpty);
    expect(_fieldText(tester, _meaningField), isEmpty);
    expect(find.text('0/500'), findsOneWidget);
    expect(find.text(_wordRequired), findsNothing);
    expect(find.text(_meaningRequired), findsNothing);

    final words = await readOutsideFakeAsync(
      tester,
      () => harness.repository.customWords(),
    );
    expect(words, hasLength(1));
    // The stored term is trimmed but keeps the user's capitalisation.
    expect(words.single.term, 'serendipity');
    expect(words.single.primaryTranslation, 'صدفة سعيدة، اكتشاف غير متوقع.');
  });

  testWidgets('a duplicate is refused with the repository sentence', (
    tester,
  ) async {
    useAPhone(tester);
    await tester.runAsync(
      () => harness.repository.addCustomWord(
        term: 'serendipity',
        meaning: 'صدفة سعيدة.',
      ),
    );
    await _pumpAdd(tester, harness.repository);

    // Different case, same word — the comparison is normalised.
    await tester.enterText(find.byKey(_wordField), 'Serendipity');
    await tester.enterText(find.byKey(_meaningField), 'معنى آخر.');
    await tester.tap(find.text(_save));
    await settleDatabase(tester);

    expect(find.text(_duplicate), findsOneWidget);
    expect(find.text(_success), findsNothing);
    // The typed values are still there for the user to correct.
    expect(_fieldText(tester, _wordField), 'Serendipity');

    final words = await readOutsideFakeAsync(
      tester,
      () => harness.repository.customWords(),
    );
    expect(words, hasLength(1));
    expect(words.single.primaryTranslation, 'صدفة سعيدة.');
  });

  testWidgets('the meaning counter starts at 0/500 and follows the text', (
    tester,
  ) async {
    useAPhone(tester);
    await _pumpAdd(tester, harness.repository);

    expect(find.text('0/500'), findsOneWidget);
    // The word field deliberately has no counter — the drawing draws one
    // under the meaning only.
    expect(find.text('0/100'), findsNothing);

    await tester.enterText(find.byKey(_meaningField), 'مرحبا');
    await tester.pump();

    expect(find.text('5/500'), findsOneWidget);
    expect(find.text('0/500'), findsNothing);
    // The word field's bound is still enforced, counter or no counter.
    expect(find.textContaining('/100'), findsNothing);
  });

  testWidgets('the overflow menu is at the top-left and back is on the right', (
    tester,
  ) async {
    useAPhone(tester);
    await _pumpAdd(tester, harness.repository);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final menu = tester.getCenter(find.byType(AppOverflowMenu));
    final back = tester.getCenter(find.byTooltip('رجوع'));

    expect(menu.dx, lessThan(width / 2));
    expect(back.dx, greaterThan(width / 2));
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_subtitle), findsOneWidget);
  });
}
