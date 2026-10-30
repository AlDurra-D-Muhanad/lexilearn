import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/domain/custom_dictionary.dart';
import 'package:lexilearn/ui/custom_dictionary/add_custom_word_screen.dart';
import 'package:lexilearn/ui/custom_dictionary/custom_dictionary_screen.dart';
import 'package:lexilearn/ui/custom_dictionary/custom_words_screen.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../helpers/test_env.dart';

/// The landing screen's copy, in Arabic.
const _subtitle = 'أنشئ قاموسك الشخصي واحفظ كلماتك المفضلة لتتعلمها في أي وقت.';
const _addTitle = 'إضافة كلمة';
const _addSubtitle = 'أضف كلمة جديدة إلى قاموسك الخاص.';
const _wordsTitle = 'الكلمات المضافة';
const _wordsSubtitle = 'عرض وإدارة كلماتك المحفوظة.';
const _backTooltip = 'رجوع';

/// Mounts the landing screen with the seams its two pushed screens need.
///
/// The screen itself reads no provider, but both routes it opens do: the add
/// screen carries `AppOverflowMenu`, which reads the settings controller and
/// the dictionary controller, and the words screen reads the repository. A
/// stand-in that supplied only the repository would pass the landing assertions
/// and throw the moment a card was tapped.
Widget _host(VocabRepository repository) => MultiProvider(
  providers: <SingleChildWidget>[
    Provider<VocabRepository>.value(value: repository),
    ...appSeamProviders(settings: createAppSettings(repository)),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.light,
    // The app is right to left end to end; a stand-in that left the default
    // LTR would put the back control on the wrong edge and make the
    // alignment assertions below meaningless.
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const CustomDictionaryScreen(),
  ),
);

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets('names the dictionary and draws both doors', (tester) async {
    useAPhone(tester);
    await tester.pumpWidget(_host(harness.repository));
    await settleDatabase(tester);

    expect(find.byType(CustomDictionaryScreen), findsOneWidget);
    expect(find.text(customDictionaryTitle), findsOneWidget);
    expect(find.text(_subtitle), findsOneWidget);

    expect(find.text(_addTitle), findsOneWidget);
    expect(find.text(_addSubtitle), findsOneWidget);
    expect(find.text(_wordsTitle), findsOneWidget);
    expect(find.text(_wordsSubtitle), findsOneWidget);

    // Two gradient cards, and two chevrons pointing left — the direction the
    // eye leaves a card in this RTL app. The artwork's mock points them right,
    // which is its mirror, not this screen's direction.
    expect(find.byType(AppSurface), findsNWidgets(2));
    expect(find.byIcon(Icons.chevron_left_rounded), findsNWidgets(2));

    // The gold open book is the header's mark and the words card's badge.
    expect(find.byIcon(Icons.menu_book_rounded), findsNWidgets(2));

    // This is a pushed route, not a fifth destination.
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets(
    'puts the back chevron on the right and the title in the middle',
    (tester) async {
      useAPhone(tester);
      await tester.pumpWidget(_host(harness.repository));
      await settleDatabase(tester);

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final back = tester.getCenter(find.byTooltip(_backTooltip));
      final title = tester.getCenter(find.text(customDictionaryTitle));

      expect(back.dx, greaterThan(width / 2));
      expect(back.dx, lessThan(width));
      // The book mark is part of the centred group, so the title's own centre
      // sits just beside the screen's centre line rather than exactly on it.
      expect(title.dx, closeTo(width / 2, 32));
    },
  );

  testWidgets('the add card opens the add screen', (tester) async {
    useAPhone(tester);
    await tester.pumpWidget(_host(harness.repository));
    await settleDatabase(tester);

    await tester.tap(find.text(_addTitle));
    await tester.pumpAndSettle();

    expect(find.byType(AddCustomWordScreen), findsOneWidget);
    expect(find.text('إنشاء قاموسك الخاص'), findsOneWidget);
  });

  testWidgets('the words card opens the list and it starts empty', (
    tester,
  ) async {
    useAPhone(tester);
    await tester.pumpWidget(_host(harness.repository));
    await settleDatabase(tester);

    await tester.tap(find.text(_wordsTitle));
    await settleDatabase(tester);

    expect(find.byType(CustomWordsScreen), findsOneWidget);
    expect(find.text(_wordsTitle), findsOneWidget);
    // The dictionary starts with nothing, and the screen says so in words.
    expect(find.text('لا كلمات بعد'), findsOneWidget);
    expect(find.text('لا توجد كلمات في قاموسك بعد.'), findsOneWidget);
  });

  testWidgets('back on the landing route is a refusal, not a crash', (
    tester,
  ) async {
    useAPhone(tester);
    await tester.pumpWidget(_host(harness.repository));
    await settleDatabase(tester);

    await tester.tap(find.byTooltip(_backTooltip));
    await tester.pumpAndSettle();

    expect(find.byType(CustomDictionaryScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
