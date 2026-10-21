import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/vocab_entry.dart';
import 'package:lexilearn/domain/vocab_pack.dart';
import 'package:lexilearn/ui/home/home_screen.dart';

import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';

import '../helpers/test_env.dart';

/// The four visual defects the user named against `new theme.png`, one test
/// each.
///
/// **The reference is the authority and every number in here was measured off
/// it** — `C:\Users\user\Desktop\lexilearn notes\new theme.png`, an 852 × 1846
/// image of a 360-px phone, so one image pixel is 0.424 logical pixels.
///
/// The user's own words, which are the reason the file exists:
///
/// 1. «الايقونات في مربعات الاربعة ليست مطابقة لا بالشكل ولا بالموقع و ايضا
///    لون هذه المربعات ليس متدرجا كما في new theme.png بل هو لون ثابت ليس
///    متدرجا» — the tiles' icons, their places, and their flat badge.
/// 2. «التنوين على كلمة مرحبا ليس ذهبيا واجعل علامة التعجب ايضا ذهبية» — the
///    greeting's tanween and its exclamation mark.
/// 3. «جملة word of the day ليست ذهبية و لايوجد خط هبي متدرج بجانبها» — the
///    "Word of the Day" phrase and the line beside it.
/// 4. «الريط السفلي ليس له حافة منحنية ذات لون اغمق بدرجة لتباين الحافة كما في
///    new theme.png وايضا لونه ليس متدرجا» — the bottom bar.
const String _greeting = 'مرحباً بك!';
const String _wordOfTheDayLabel = 'Word of the Day';

/// The tanween, `U+064B`, on its own — the character the reference draws in
/// gold above the alef.
const String _tanween = '\u064B';

/// The four tiles, with the reference's own glyph for each.
///
/// | tile | the reference's glyph | the app's glyph |
/// |---|---|---|
/// | بطاقات التعلم | a tilted card, outlined | `Icons.style_outlined` |
/// | الاختبارات | a clipboard with a tick, outlined | `Icons.assignment_turned_in_outlined` |
/// | المفضلة | an outlined heart | `Icons.favorite_outlined` |
/// | إحصائياتك | three solid bars | `Icons.bar_chart_rounded` |
///
/// **The first one is the reference's own bottom-bar glyph.** The reference
/// draws the same tilted card for `البطاقات` in its bottom bar and for
/// `بطاقات التعلم` in its grid, and the app's bottom bar already uses
/// `Icons.style_outlined` for it.
const List<(String, IconData)> _tiles = <(String, IconData)>[
  ('بطاقات التعلم', Icons.style_outlined),
  ('الاختبارات', Icons.assignment_turned_in_outlined),
  ('المفضلة', Icons.favorite_outlined),
  ('إحصائياتك', Icons.bar_chart_rounded),
];

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
          VocabEntry(
            id: 'a',
            term: 'ghost clusters',
            translations: <String>['أشباح عنقودية'],
            phonetic: '/ɡoʊst klˈʌstərz/',
          ),
        ],
      ),
    ]);
  });

  tearDown(() => harness.dispose());

  /// Mounts the app on a dark phone.
  ///
  /// **Dark, because the reference is a dark design** and every colour measured
  /// off it is a dark-mode colour. The app follows the platform brightness, so
  /// overriding the dispatcher is how the app itself would see a dark device.
  Future<void> pumpDark(WidgetTester tester) async {
    useAPhone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpShell(tester, harness.repository);
  }

  group('defect 1 — the four tiles', () {
    testWidgets('each badge is a gradient disc, not a flat colour',
        (tester) async {
      await pumpDark(tester);

      // **The badge is the circle, and it is the reference's own ramp.**
      //
      // Measured off the reference: a vertical slice down the disc behind the
      // top-left tile's icon reads `#172B4F` at the disc's top and `#091C3B`
      // at its foot, with the tile's own fill around it at `#0D2245`.
      //
      // **Scoped to each tile**, because the header's book mark is a circle
      // too — and it is a *flat* disc, on purpose: the reference draws that one
      // flat as well (`#10151F`, the page lifted a hair).
      for (final (title, _) in _tiles) {
        final tile = find.ancestor(
          of: find.descendant(
            of: find.byType(HomeScreen),
            matching: find.text(title),
          ),
          matching: find.byType(AppSurface),
        );
        final badges = find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).shape == BoxShape.circle,
            description: 'a circular badge',
          ),
        );
        expect(badges, findsOneWidget,
            reason: '"$title" has no badge around its glyph');

        final decoration = (tester.widget<DecoratedBox>(badges).decoration)
            as BoxDecoration;
        // **A gradient, and not a flat fill.** This is the assertion the
        // defect turns on: the old badge painted one colour.
        expect(decoration.gradient, isNotNull,
            reason: 'the badge is a flat colour, and the reference\'s is a ramp');
        expect(decoration.color, isNull,
            reason: 'a flat colour and a gradient are two different fills');
        final gradient = decoration.gradient! as LinearGradient;
        expect(gradient.colors, <Color>[
          AppColors.iconBadgeDarkTop,
          AppColors.iconBadgeDarkBottom,
        ]);
        expect(gradient.begin, Alignment.topCenter);
        expect(gradient.end, Alignment.bottomCenter);
      }
    });

    testWidgets('each tile carries the reference\'s own glyph, in the gold',
        (tester) async {
      await pumpDark(tester);

      for (final (title, glyph) in _tiles) {
        final icon = find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byIcon(glyph),
        );
        expect(icon, findsOneWidget,
            reason: 'the "$title" tile does not carry the reference\'s glyph');
        // **The gold, as ink, where the mode can carry it.** The reference
        // draws all four of its tile glyphs in the brand's gold.
        expect(tester.widget<Icon>(icon).color, AppColors.gold);
      }

      // **And the old glyphs are gone**, so a stale one cannot pass by
      // sitting beside the new one.
      for (final stale in <IconData>[
        Icons.auto_stories_rounded,
        Icons.check_box_rounded,
        Icons.favorite_rounded,
        Icons.insights_rounded,
      ]) {
        expect(
          find.descendant(of: find.byType(HomeScreen), matching: find.byIcon(stale)),
          findsNothing,
          reason: '$stale is not the reference\'s glyph for this tile',
        );
      }
    });

    testWidgets('the badge and the text are against the leading edge',
        (tester) async {
      await pumpDark(tester);

      for (final (title, _) in _tiles) {
        final tile = find.ancestor(
          of: find.descendant(
            of: find.byType(HomeScreen),
            matching: find.text(title),
          ),
          matching: find.byType(Container),
        );
        expect(tile, findsWidgets);

        final badge = find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).shape == BoxShape.circle,
            description: 'a circular badge',
          ),
        );
        expect(badge, findsOneWidget,
            reason: '"$title" has no badge around its glyph');

        // **The badge is against the leading edge, and the title is with it.**
        //
        // The reference puts the disc on the same edge as the title and the
        // subtitle; this app reads right to left, so the leading edge is the
        // **right**, and the badge's right edge is the title's right edge.
        final badgeRect = tester.getRect(badge);
        final titleRect = tester.getRect(
          find.descendant(
            of: find.byType(HomeScreen),
            matching: find.text(title),
          ),
        );
        expect(badgeRect.right, closeTo(titleRect.right, 1.0),
            reason: '"$title": the badge is not against the title\'s leading edge');
        // And it is above the title, not beside it.
        expect(badgeRect.bottom, lessThan(titleRect.top),
            reason: '"$title": the badge is not above the title');
      }
    });
  });

  group('defect 2 — the greeting', () {
    testWidgets('the tanween and the exclamation mark are gold, and the word '
        'is not', (tester) async {
      await pumpDark(tester);

      final greeting = tester.widget<Text>(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.text(_greeting),
        ),
      );

      // **The greeting is one `Text` with four runs**, and the runs are what
      // the assertion is about: a colour on the whole word would colour the
      // word, and the reference's treatment is white «مرحبا» with the tanween
      // and the "!" in gold.
      final root = greeting.textSpan! as TextSpan;
      final runs = root.children!.whereType<TextSpan>().toList();
      expect(runs, hasLength(4),
          reason: 'the greeting is not split into the reference\'s four runs');

      final tanween = runs.firstWhere((run) => run.text == _tanween,
          orElse: () => fail('the greeting has no run for the tanween'));
      final bang = runs.firstWhere((run) => run.text == '!',
          orElse: () => fail('the greeting has no run for the exclamation mark'));

      // **The diacritic span is gold.**
      expect(tanween.style?.color, AppColors.gold);
      // **And the exclamation mark is gold too.**
      expect(bang.style?.color, AppColors.gold);

      // **And the rest of the word is not.** Every other run resolves to the
      // theme's ink — white in dark mode — and to nothing that is gold.
      for (final run in runs) {
        if (run.text == _tanween || run.text == '!') continue;
        final colour = run.style?.color ?? root.style?.color;
        expect(colour, isNot(AppColors.gold),
            reason: 'the run "${run.text}" is gold, and the reference draws it '
                'in the ink');
      }
      // And the whole run of ink is the app's own text colour, not a gold that
      // happened to leak in.
      expect(root.style?.color, isNot(AppColors.gold));
    });
  });

  group('defect 3 — the word-of-the-day label', () {
    testWidgets('the phrase is gold, with a gold star and a gold rule beside it',
        (tester) async {
      await pumpDark(tester);

      // **The phrase is the gold**, and not the card's white ink: the
      // reference draws this label in the brand's gold and the user asked for
      // it — «جملة word of the day ليست ذهبية».
      final label = tester.widget<Text>(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.text(_wordOfTheDayLabel),
        ),
      );
      expect(label.style?.color, AppColors.gold);
      // **And it keeps the artwork's shadow**, which is what carries a gold run
      // over a photograph.
      expect(label.style?.shadows, AppShadows.onPhoto);

      // **The gold star**, before the phrase.
      final star = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byIcon(Icons.star_rounded),
      );
      expect(star, findsOneWidget);
      expect(tester.widget<Icon>(star).color, AppColors.gold);

      // **And the rule**, which is a gradient and not a flat gold bar: the
      // reference's line starts at the full gold and fades away until it is
      // gone — «لايوجد خط هبي متدرج بجانبها».
      final card = find.ancestor(
        of: find.descendant(
          of: find.byType(HomeScreen),
          matching: find.text(_wordOfTheDayLabel),
        ),
        matching: find.byType(AppSurface),
      );
      final goldRamps = <LinearGradient>[];
      for (final element in find
          .descendant(of: card, matching: find.byType(DecoratedBox))
          .evaluate()) {
        final decoration = (element.widget as DecoratedBox).decoration;
        if (decoration is! BoxDecoration) continue;
        final gradient = decoration.gradient;
        if (gradient is! LinearGradient) continue;
        if (gradient.colors.isEmpty) continue;
        if (gradient.colors.first != AppColors.gold) continue;
        goldRamps.add(gradient);
      }
      expect(goldRamps, hasLength(1),
          reason: 'there is no gold rule beside the label');
      final rule = goldRamps.single;
      // **It fades away**, so the second stop is the gold at no alpha.
      expect(rule.colors.last.a, 0.0);
      expect(rule.colors.last, isNot(rule.colors.first));
      // **And it is directional**, so the gold end is against the phrase and
      // the transparent end is away from it.
      expect(rule.begin, AlignmentDirectional.centerStart);
      expect(rule.end, AlignmentDirectional.centerEnd);
    });
  });

  group('the active tab\'s gold badge', () {
    testWidgets('the active destination sits in a translucent gold field with '
        'a stronger gold edge, and its icon is the gold', (tester) async {
      await pumpDark(tester);

      final bar = AppTheme.dark().navigationBarTheme;

      // **The field is the brand gold, translucent.** The alpha is the fitted
      // one — see `AppColors.goldField` for the composite it comes from.
      expect(bar.indicatorColor, AppColors.goldField);
      expect(bar.indicatorColor!.a, closeTo(0.28, 0.01));

      // **The edge is the same gold, stronger**, and it is the shape's own side
      // — so the ring is stroked *around* the field and not painted over it.
      final shape = bar.indicatorShape! as RoundedRectangleBorder;
      final side = shape.side;
      expect(side.color, AppColors.goldEdge);
      expect(side.color.a, closeTo(0.70, 0.01));
      expect(side.width, 1.0);

      // **And the icon is the full gold**, which is what the reference draws
      // inside the field — not the gold's own dark ink.
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.home),
        ),
      );
      expect(icon.color, isNull,
          reason: 'the colour is the theme\'s, and the theme says what it is');
      expect(
        IconTheme.of(
          tester.element(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.byIcon(Icons.home),
            ),
          ),
        ).color,
        AppColors.gold,
      );

      // **And the label is the gold too**, which is what the identity's rule 6
      // says: the active destination's icon *and* its label.
      expect(
        bar.labelTextStyle?.resolve(const <WidgetState>{WidgetState.selected})
            ?.color,
        AppColors.gold,
      );
    });
  });

  group('defect 4 — the bottom bar', () {
    testWidgets('the bar has a rounded top, a darker edge and a gradient fill',
        (tester) async {
      await pumpDark(tester);

      // **The bar's own surface**, found by its decoration rather than by its
      // position, so the assertion is about what is painted.
      Container? surface;
      for (final widget in tester.widgetList<Container>(find.byType(Container))) {
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) continue;
        final gradient = decoration.gradient;
        if (gradient is! LinearGradient) continue;
        if (!gradient.colors.contains(AppColors.bottomBarDarkTop)) continue;
        surface = widget;
      }
      expect(surface, isNotNull,
          reason: 'the bottom bar is not painted as a gradient');
      final decoration = surface!.decoration! as BoxDecoration;

      // **The fill is a ramp and not a flat colour.** Measured off the
      // reference: `#07152D` at the bar's top and `#06142B` at its foot.
      final gradient = decoration.gradient! as LinearGradient;
      expect(gradient.colors, <Color>[
        AppColors.bottomBarDarkTop,
        AppColors.bottomBarDarkBottom,
      ]);
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);

      // **A darker line along the top edge**, so the edge is visible rather
      // than implied: the reference's reads `#000A1E` where the bar meets the
      // page, darker than both the page and the bar's own fill.
      final border = decoration.border! as Border;
      expect(border.top.color, AppColors.bottomBarEdgeDark);
      expect(border.top.width, 1.0);
      expect(border.top.color, isNot(AppColors.bottomBarDark));

      // **And the top corners are rounded**, with the bottom square — the
      // reference's bar is a rounded-top surface. Measured off the reference:
      // the corner's radius is 33 image px, which is 14 logical px.
      final radius = decoration.borderRadius! as BorderRadius;
      expect(radius.topLeft.x, greaterThan(0.0));
      expect(radius.topRight.x, greaterThan(0.0));
      expect(radius.bottomLeft.x, 0.0);
      expect(radius.bottomRight.x, 0.0);
      expect(radius.topLeft.x, radius.topRight.x);

      // **And the bar inside it is transparent**, so the ramp is what is seen
      // rather than a flat colour painted over it.
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.backgroundColor, Colors.transparent);
    });
  });
}
