import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:lexilearn/ui/theme/app_verdict_colors.dart';

import '../helpers/test_env.dart';

void main() {
  test('the colour scheme is the brand palette, not Material\'s tonal guess', () {
    // `ColorScheme.fromSeed` does not produce the brand's colours: seeding with
    // the gold `#F3AC43` gives a `primaryContainer` of a pale sand. Asserting
    // `isNot(light, dark)` passed happily against a dusty pair, which is why
    // these are pinned by hex.
    final light = AppTheme.light().colorScheme;
    final dark = AppTheme.dark().colorScheme;

    expect(light.primary, AppColors.gold);
    expect(dark.primary, AppColors.gold);
    // **The same gold in both brightnesses, and that is the new identity's own
    // rule**: the light palette is the same system inverted and the primary
    // does not invert. The old pair — a violet and a lilac — asserted the
    // opposite, and the old test asserted they differed.
    expect(light.primary, dark.primary);

    expect(light.secondary, AppColors.gold);
    expect(dark.secondary, AppColors.gold);

    // **The ink on the gold, which is what the primary is a fill of.**
    expect(light.onPrimary, AppColors.onGold);
    expect(dark.onPrimary, AppColors.onGold);

    expect(light.surface, AppColors.surfaceLight);
    expect(dark.surface, AppColors.surfaceDark);
    expect(light.onSurface, AppColors.textLight);
    expect(dark.onSurface, AppColors.textDark);
    expect(light.onSurfaceVariant, AppColors.textSecondaryLight);
    expect(dark.onSurfaceVariant, AppColors.textSecondaryDark);
    expect(light.outline, AppColors.borderLight);
    expect(dark.outline, AppColors.borderDark);
    expect(light.outlineVariant, AppColors.borderLight);
    expect(dark.outlineVariant, AppColors.borderDark);
    expect(light.error, AppColors.errorLight);
    expect(dark.error, AppColors.errorDark);

    expect(AppTheme.light().useMaterial3, isTrue);
    expect(AppTheme.dark().useMaterial3, isTrue);
  });

  test('both themes use the one brand primary, and the ink on it is dark', () {
    // The failure this replaces asserted only `isNot(light.primary,
    // dark.primary)`, which the pair `#65558F` / `#A78BFA` satisfied happily
    // while the whole app rendered the wrong purple. Both the primary and the
    // body ink are pinned by token, per brightness.
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.colorScheme.primary, AppColors.gold);
    expect(dark.colorScheme.primary, AppColors.gold);
    expect(light.colorScheme.onPrimary, AppColors.onGold);
    expect(dark.colorScheme.onPrimary, AppColors.onGold);

    expect(light.textTheme.bodyMedium?.color, AppColors.textLight);
    expect(dark.textTheme.bodyMedium?.color, AppColors.textDark);
    expect(light.textTheme.bodyMedium?.color,
        isNot(dark.textTheme.bodyMedium?.color));

    expect(light.scaffoldBackgroundColor, AppColors.backgroundLight);
    expect(dark.scaffoldBackgroundColor, AppColors.backgroundDark);
  });

  test('the bottom bar is the gold badge, the gold icon and the gold label', () {
    // **The active destination, as the identity document rule 6 has it**: the
    // primary is a **fill** — the active destination sits in a *translucent*
    // gold field with a stronger gold ring around it — the icon on it is the
    // gold, and the *label* is the gold on the bar's navy, which is what the
    // reference draws.
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final bar = theme.navigationBarTheme;
      final isDark = theme.brightness == Brightness.dark;

      // **The field is the brand gold, translucent.** The alpha is the fitted
      // one; `AppColors.goldField` carries the derivation.
      expect(bar.indicatorColor, AppColors.goldField);
      expect(bar.indicatorColor!.a, closeTo(0.28, 0.01));

      // **The edge is the same gold, stronger**, and it is the shape's own
      // side — so the ring is stroked around the field, not painted over it.
      final shape = bar.indicatorShape! as RoundedRectangleBorder;
      final side = shape.side;
      expect(side.color, AppColors.goldEdge);
      expect(side.color.a, closeTo(0.70, 0.01));
      expect(side.width, 1.0);

      const selected = <WidgetState>{WidgetState.selected};
      const unselected = <WidgetState>{};
      // **The icon is the accent ink.** The reference draws the active tab's
      // icon in the *full* gold inside the translucent field; the icon is ink
      // rather than a fill, so light mode takes the body ink, where the gold
      // is 1.95 : 1 against the page.
      expect(bar.iconTheme?.resolve(selected)?.color,
          AppColors.accentInk(isDark));
      expect(bar.labelTextStyle?.resolve(selected)?.color, AppColors.gold);
      expect(bar.labelTextStyle?.resolve(unselected)?.color,
          isNot(AppColors.gold));
    }
    // The bar's own colour, measured off the reference: `#06142C`.
    expect(AppTheme.dark().navigationBarTheme.backgroundColor,
        AppColors.bottomBarDark);
  });

  test('text roles are inked with the brand text colour, not a derived one', () {
    // The generated text theme coloured every stock role `#1D1B20` on light,
    // which is visibly not the brand's `#1F2937`.
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    for (final role in <TextStyle?>[
      light.textTheme.displayLarge,
      light.textTheme.titleLarge,
      light.textTheme.bodyMedium,
      light.textTheme.labelSmall,
    ]) {
      expect(role?.color, AppColors.textLight);
    }
    for (final role in <TextStyle?>[
      dark.textTheme.displayLarge,
      dark.textTheme.titleLarge,
      dark.textTheme.bodyMedium,
      dark.textTheme.labelSmall,
    ]) {
      expect(role?.color, AppColors.textDark);
    }
    expect(light.primaryTextTheme.bodyMedium?.color, AppColors.textLight);
    expect(dark.primaryTextTheme.bodyMedium?.color, AppColors.textDark);
  });

  testWidgets('AppSurface paints the brand shadow and hairline, and no elevation shadow',
      (tester) async {
    Future<BoxDecoration> decorationFor(ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(body: AppSurface(child: SizedBox.expand())),
      ));
      await tester.pumpAndSettle();
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(AppSurface),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return container.decoration! as BoxDecoration;
    }

    final light = await decorationFor(AppTheme.light());
    expect(light.boxShadow, AppShadows.light);
    expect((light.border! as Border).top.color, AppColors.borderLight);
    expect(light.color, AppColors.surfaceLight);
    expect(light.borderRadius, BorderRadius.circular(AppRadii.md));

    final dark = await decorationFor(AppTheme.dark());
    expect(dark.boxShadow, AppShadows.none);
    expect((dark.border! as Border).top.color, AppColors.borderDark);
    expect(dark.color, AppColors.surfaceDark);
  });

  test('no theme surface turns elevation into a shadow', () {
    // Material's elevation shadow is ~4x the brand's umbra alpha, and the test
    // rasteriser strokes it as an opaque black keyline. `CardThemeData` cannot
    // carry the brand shadow, so the only safe elevation is zero.
    expect(AppTheme.light().cardTheme.elevation, 0);
    expect(AppTheme.dark().cardTheme.elevation, 0);
  });

  test('every button family is pinned at zero elevation, hovered included',
      () {
    // Amendment 6's defect, fixed a second time and now prevented rather than
    // patched. The defaults these replace, read out of this SDK's
    // `packages/flutter/lib/src/material/` and not from a blog post:
    //
    // | Widget           | resting | hovered | pressed | source |
    // |------------------|---------|---------|---------|--------|
    // | `ElevatedButton` | **1.0** | **3.0** | 1.0     | `elevated_button.dart:570-585` |
    // | `FilledButton`   | 0.0     | **1.0** | 0.0     | `filled_button.dart:588-603`   |
    // | `OutlinedButton` | 0.0     | 0.0     | 0.0     | `outlined_button.dart:512-513` |
    // | `Chip`           | 0.0     | --      | 0.0     | `chip.dart:1350-1352` `?? 0`  |
    //
    // **`hovered` is the half that matters and the half that is easy to leave
    // out.** `FilledButton` rests at 0, so an assertion that resolves only the
    // resting state passes against an unmodified theme while a mouse-over still
    // paints the keyline — and no golden can catch it, because a screenshot is
    // taken with no pointer over anything.
    //
    // **Per-widget opt-out did not hold, and this is the evidence.** Measured
    // across `lib/ui/`: three widgets shipped with no elevation override at all
    // — `quiz_result_screen.dart`'s `FilledButton`, `stats_screen.dart`'s
    // `_Notice` `OutlinedButton`, and `quiz_setup_screen.dart`'s
    // `ActionChip`. Only the ones somebody happened to remember were safe.
    const hovering = <WidgetState>{WidgetState.hovered};
    const pressed = <WidgetState>{WidgetState.pressed};

    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final families = <String, ButtonStyle?>{
        'elevated': theme.elevatedButtonTheme.style,
        'filled': theme.filledButtonTheme.style,
        'outlined': theme.outlinedButtonTheme.style,
      };
      families.forEach((name, style) {
        for (final entry in <String, Set<WidgetState>>{
          'resting': const <WidgetState>{},
          'hovered': hovering,
          'pressed': pressed,
        }.entries) {
          expect(
            style?.elevation?.resolve(entry.value),
            0.0,
            reason: 'the $name button paints elevation in its ${entry.key} state',
          );
        }
      });

      // `ChipThemeData.elevation` is a plain `double?`, not a
      // `WidgetStateProperty`: `chip.dart:1350` reads it straight into a
      // `?? 0` chain, so there is nothing to resolve and pretending otherwise
      // would be inventing an API. Pinned because a reader cannot otherwise see
      // that a chip is already safe — and `cardTheme.elevation` says nothing
      // about a chip at all.
      expect(theme.chipTheme.elevation, 0.0);
      expect(theme.chipTheme.pressElevation, 0.0);
    }
  });

  test('cards use the brand surface colour and a rounded outline', () {
    final light = AppTheme.light();
    expect(light.cardTheme.color, AppColors.surfaceLight);
    final lightShape = light.cardTheme.shape as RoundedRectangleBorder;
    expect(lightShape.side.color, AppColors.borderLight);
    expect(lightShape.borderRadius, BorderRadius.circular(AppRadii.md));

    final darkShape = AppTheme.dark().cardTheme.shape as RoundedRectangleBorder;
    expect(darkShape.side.color, AppColors.borderDark);
  });

  test('search fields are pill shaped, matching the artwork', () {
    final decoration = AppTheme.light().inputDecorationTheme;
    expect(decoration.filled, isTrue);
    expect(decoration.border, isA<OutlineInputBorder>());
    final border = decoration.border as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(AppRadii.pill));
    expect(decoration.fillColor, AppColors.surfaceLight);
    expect(decoration.hintStyle?.color, AppColors.textSecondaryLight);
  });

  test('both themes bind Tajawal, which is what renders every Arabic string', () {
    // `ThemeData` takes a `fontFamily` but exposes no getter for it: the family
    // is baked into every style of the text theme, which is what a screen
    // actually renders. So the assertion is made there instead. Covering four
    // roles in both themes is strictly more than checking one field twice.
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final styles = theme.textTheme;
      expect(styles.displayLarge?.fontFamily, 'Tajawal');
      expect(styles.titleLarge?.fontFamily, 'Tajawal');
      expect(styles.bodyMedium?.fontFamily, 'Tajawal');
      expect(styles.labelSmall?.fontFamily, 'Tajawal');
    }
  });

  test('scaffold backgrounds match the brand, not Material\'s default', () {
    expect(AppTheme.light().scaffoldBackgroundColor, AppColors.backgroundLight);
    expect(AppTheme.dark().scaffoldBackgroundColor, AppColors.backgroundDark);
  });

  test('fromColorScheme is a pure function of the scheme', () {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.gold);
    expect(AppTheme.fromColorScheme(scheme).colorScheme.primary, scheme.primary);
  });

  // ---------------------------------------------------------------------------
  // The verdict palette — the one role `ColorScheme` has no field for.
  // ---------------------------------------------------------------------------

  test('both themes install a verdict palette, so no screen can be without one', () {
    // The `!` inside `AppVerdictColors.of(context)` is a claim that this holds.
    // A theme built any other way would throw `null check operator used on a
    // null value` at the quiz screen rather than quietly drawing no feedback.
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      expect(theme.extension<AppVerdictColors>(), isNotNull);
    }
    expect(
      AppTheme.fromColorScheme(ColorScheme.fromSeed(seedColor: AppColors.gold))
          .extension<AppVerdictColors>(),
      isNotNull,
      reason: 'the fromColorScheme caller installs it too',
    );
  });

  test('the correct verdict is green, and it is a derivation rather than a literal', () {
    // **The defect, in the theme.** The correct option's fill was
    // `colorScheme.primaryContainer` — `#E9DDFF` light, `#4C3E76` dark — which is
    // the brand purple, behind a 2px green border. The user photographed that and
    // called it «الاختيار الصحيح يكون فقط اطاره بالاخضر و الحقل بنفسجي». There is
    // no `successContainer` on `ColorScheme`, so this is where the role had to be
    // added; what it must never be is purple.
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    for (final theme in <ThemeData>[light, dark]) {
      final verdict = theme.extension<AppVerdictColors>()!;
      expect(
        verdict.correctFill,
        isNot(theme.colorScheme.primaryContainer),
        reason: 'the right answer is painted in the purple primary container',
      );
      // Green, defined as green: hue inside the green arc AND the green channel
      // dominant. A hue-only check would accept a desaturated grey-green; a
      // channel-only check would accept a cyan. This is the test that goes red if
      // the seed, the Flutter version or the role itself ever moves off green.
      final hsl = HSLColor.fromColor(verdict.correctFill);
      expect(hsl.hue, inInclusiveRange(80, 170),
          reason: '${verdict.correctFill} is not on the green arc');
      expect(hsl.saturation, greaterThan(0.3));
      expect(hsl.lightness, greaterThan(0.1));
      expect(verdict.correctFill.g, greaterThan(verdict.correctFill.r));
      expect(verdict.correctFill.g, greaterThan(verdict.correctFill.b));
    }

    // And it is the *same* construction the error half uses: M3's container tone
    // for that seed. Recomputed here rather than read out of the extension, so a
    // future edit that hardcodes a "nicer" green instead of deriving one goes red.
    expect(
      light.extension<AppVerdictColors>()!.correctFill,
      ColorScheme.fromSeed(
        seedColor: AppColors.successLight,
        brightness: Brightness.light,
      ).primaryContainer,
    );
    expect(
      dark.extension<AppVerdictColors>()!.correctFill,
      ColorScheme.fromSeed(
        seedColor: AppColors.successDark,
        brightness: Brightness.dark,
      ).primaryContainer,
    );
  });

  test('the verdict palette carries the measured hexes, per brightness', () {
    // These are the numbers in the report. Pinned so a Flutter upgrade that
    // re-tones the palette cannot move a green the user has already approved
    // without this saying so.
    final light = AppTheme.light().extension<AppVerdictColors>()!;
    final dark = AppTheme.dark().extension<AppVerdictColors>()!;

    expect(light.correctFill, const Color(0xFFB7F1BA));
    expect(light.correctInk, const Color(0xFF1C5128));
    expect(dark.correctFill, const Color(0xFF17512B));
    expect(dark.correctInk, const Color(0xFFB4F1BE));

    // The borders are the brand tokens, per brightness — this is the fix for the
    // dark-mode defect, stated at its source. `#16A34A` and `#DC2626` in a dark
    // theme is what the user's phone drew.
    expect(light.correctBorder, AppColors.successLight);
    expect(dark.correctBorder, AppColors.successDark);
    expect(light.wrongBorder, AppColors.errorLight);
    expect(dark.wrongBorder, AppColors.errorDark);
    expect(dark.correctBorder, isNot(AppColors.successLight));
    expect(dark.wrongBorder, isNot(AppColors.errorLight));
  });

  test('the wrong verdict is untouched: it is the scheme\'s own error container', () {
    // The user approved this one explicitly («ممتاز و هو المطلوب»), so it is
    // carried through by reference rather than restated. `isNot` the correct
    // half too, so swapping the two cannot pass.
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final verdict = theme.extension<AppVerdictColors>()!;
      expect(verdict.wrongFill, theme.colorScheme.errorContainer);
      expect(verdict.wrongInk, theme.colorScheme.onErrorContainer);
      expect(verdict.wrongFill, isNot(verdict.correctFill));
      expect(verdict.wrongInk, isNot(verdict.correctInk));
    }
  });

  test('ink on the verdict fills passes WCAG AA in both brightnesses', () {
    // The requirement the check mark and the cross have to meet, as an assertion
    // rather than a sentence: AA is 4.5:1 for text, and these are 24px glyphs so
    // they are measured against the stricter of the two bars anyway.
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final verdict = theme.extension<AppVerdictColors>()!;
      final correct = contrastRatio(verdict.correctInk, verdict.correctFill);
      final wrong = contrastRatio(verdict.wrongInk, verdict.wrongFill);
      expect(correct, greaterThanOrEqualTo(4.5),
          reason: 'the tick on the green fill in ${theme.brightness}');
      expect(wrong, greaterThanOrEqualTo(4.5),
          reason: 'the cross on the red fill in ${theme.brightness}');
    }
  });

  test('the verdict borders clear the 3:1 a 2px border needs against the surface', () {
    // Measured on the surface each mode actually puts behind the option row. The
    // wrong half clears it everywhere; the correct border is the tighter one and
    // lands at 3.30:1 in light, which is the reason the verdict carries a
    // *filled* green field rather than relying on the border alone.
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final verdict = theme.extension<AppVerdictColors>()!;
      expect(contrastRatio(verdict.correctBorder, theme.colorScheme.surface),
          greaterThanOrEqualTo(3.0));
      expect(contrastRatio(verdict.wrongBorder, theme.colorScheme.surface),
          greaterThanOrEqualTo(3.0));
    }
  });
}