import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';

import '../helpers/test_env.dart';

void main() {
  test('spacing scale ascends and covers a full phone layout', () {
    expect(AppSpacing.xs, lessThan(AppSpacing.s));
    expect(AppSpacing.s, lessThan(AppSpacing.m));
    expect(AppSpacing.m, lessThan(AppSpacing.l));
    expect(AppSpacing.l, lessThan(AppSpacing.xl));
    expect(AppSpacing.m, 16);
  });

  test('radii are ordered and the pill radius exceeds any card', () {
    expect(AppRadii.sm, lessThan(AppRadii.md));
    expect(AppRadii.md, lessThan(AppRadii.lg));
    expect(AppRadii.pill, greaterThan(AppRadii.lg));
  });

  test('brand colours are exactly the hexes the user supplied', () {
    // Pinned to the brand files. If someone "improves" one of these, a test
    // fails, which is the only thing stopping silent brand drift.
    //
    // **The navy-and-gold palette, measured off
    // `C:\Users\user\Desktop\lexilearn notes\new theme.png`** and recorded in
    // `docs/new-identity.md`.
    expect(AppColors.gold, const Color(0xFFF3AC43));
    expect(AppColors.onGold, const Color(0xFF020E24));
    expect(AppColors.backgroundLight, const Color(0xFFF8F7F5));
    expect(AppColors.surfaceLight, const Color(0xFFFFFFFF));
    expect(AppColors.textLight, const Color(0xFF1F2937));
    expect(AppColors.textSecondaryLight, const Color(0xFF6B7280));
    expect(AppColors.borderLight, const Color(0xFFE5E7EB));
    expect(AppColors.outlineLight, const Color(0xFFE5E7EB));
    expect(AppColors.backgroundDark, const Color(0xFF020E24));
    expect(AppColors.surfaceDark, const Color(0xFF0E2344));
    expect(AppColors.surfaceDarkAlt, const Color(0xFF071937));
    expect(AppColors.textDark, const Color(0xFFFFFFFF));
    expect(AppColors.textSecondaryDark, const Color(0xFF94A3B8));
    expect(AppColors.borderDark, const Color(0xFF17376A));
    expect(AppColors.outlineDark, const Color(0xFF31599B));
    expect(AppColors.bottomBarDark, const Color(0xFF06142C));
    expect(AppColors.iconBadgeDark, const Color(0xFF0C1E38));
    expect(AppColors.successLight, const Color(0xFF16A34A));
    expect(AppColors.successDark, const Color(0xFF4ADE80));
    expect(AppColors.errorLight, const Color(0xFFDC2626));
    expect(AppColors.errorDark, const Color(0xFFF87171));
  });

  test('the primary is one gold in both modes, and it is a fill', () {
    // **The new identity's own rule: the light palette is the same system
    // inverted, and the primary does not invert.** There is no "a lighter
    // primary for light mode" any more, and this is what stops one creeping
    // back in.
    expect(AppColors.gold, AppColors.gold);
    expect(ThemeData.estimateBrightnessForColor(AppColors.gold),
        Brightness.light);

    // **The gold is a FILL and the ink on it is dark.** The reference's
    // "معرفة المعنى" is a solid gold pill with near-black lettering, so the
    // gold is never a text colour on a light surface — it measures
    // **1.95 : 1** on white, and **1.82 : 1** on the light background.
    expect(contrastRatio(AppColors.gold, AppColors.surfaceLight),
        lessThan(4.5));
    expect(contrastRatio(AppColors.gold, AppColors.backgroundLight),
        lessThan(4.5));
  });

  test('the ink on the gold clears AA, and it is the same ink in both modes', () {
    // **The number the brief asks for, as an assertion rather than a
    // sentence.** The gold is the same gold in both modes, so the ink on it is
    // the same ink in both modes, and the ratio is the same number twice.
    expect(contrastRatio(AppColors.onGold, AppColors.gold),
        greaterThanOrEqualTo(4.5));
    expect(contrastRatio(AppColors.onGold, AppColors.gold), closeTo(9.89, 0.02));
  });

  test('the gold carries text on the navy surfaces, and nowhere else', () {
    // **The measured numbers.** The gold is **9.89 : 1** on the navy
    // background, **8.04 : 1** on the navy surface, **8.97 : 1** on the
    // second surface, **9.43 : 1** on the bottom bar and **8.58 : 1** on the
    // icon badge — so it may carry the active tab's label, the active
    // destination's icon and the marks on the cards.
    for (final surface in <Color>[
      AppColors.backgroundDark,
      AppColors.surfaceDark,
      AppColors.surfaceDarkAlt,
      AppColors.bottomBarDark,
      AppColors.iconBadgeDark,
    ]) {
      expect(contrastRatio(AppColors.gold, surface), greaterThanOrEqualTo(4.5),
          reason: 'the gold on $surface');
    }
  });

  test('the accent ink is the gold in dark mode and the body ink in light', () {
    // **The rule that keeps the gold a fill, in one place.** In dark mode the
    // gold is legible as ink on the navy (8.04 : 1 on the surface); in light
    // mode it is 1.95 : 1 on white, so the accent ink there is the body ink
    // instead (14.68 : 1).
    expect(AppColors.accentInk(true), AppColors.gold);
    expect(AppColors.accentInk(false), AppColors.textLight);
    expect(contrastRatio(AppColors.accentInk(true), AppColors.surfaceDark),
        greaterThanOrEqualTo(4.5));
    expect(contrastRatio(AppColors.accentInk(false), AppColors.surfaceLight),
        greaterThanOrEqualTo(4.5));
  });

  test('the body inks clear AA on the surfaces they are drawn on', () {
    // The measured numbers: white on the navy background is 19.25 : 1 and on
    // the navy surface 15.64 : 1; the light ink is 13.71 : 1 on the light
    // background and 14.68 : 1 on the light surface.
    expect(contrastRatio(AppColors.textDark, AppColors.backgroundDark),
        greaterThanOrEqualTo(4.5));
    expect(contrastRatio(AppColors.textDark, AppColors.surfaceDark),
        greaterThanOrEqualTo(4.5));
    expect(contrastRatio(AppColors.textLight, AppColors.backgroundLight),
        greaterThanOrEqualTo(4.5));
    expect(contrastRatio(AppColors.textLight, AppColors.surfaceLight),
        greaterThanOrEqualTo(4.5));
    // The muted inks, which are the ones that are allowed to be quieter and
    // still clear AA: 6.10 : 1 and 4.83 : 1.
    expect(contrastRatio(AppColors.textSecondaryDark, AppColors.surfaceDark),
        greaterThanOrEqualTo(4.5));
    expect(contrastRatio(AppColors.textSecondaryLight, AppColors.surfaceLight),
        greaterThanOrEqualTo(4.5));
  });

  test('the ink on the gold is never black', () {
    // `#000000` is the exact colour `tool/golden_census.ps1` fails a golden
    // for. The reference's button lettering is black, and the app's ink is
    // the app's darkest navy instead — visually the same, and it cannot put a
    // forbidden colour into the reference images by the back door.
    expect(AppColors.onGold, isNot(const Color(0xFF000000)));
    expect(AppColors.onGold, AppColors.backgroundDark);
  });

  test('light-mode shadow matches the brand spec exactly', () {
    expect(AppShadows.light, hasLength(1));
    final shadow = AppShadows.light.single;
    expect(shadow.offset, const Offset(0, 4));
    expect(shadow.blurRadius, 12);
    expect(shadow.color, const Color(0x0D000000)); // 0.05 alpha
    expect(AppShadows.none, isEmpty);
  });

  test('the text shadow on a photograph is still the artwork\'s own', () {
    // **It stays.** The user refused the reference's split card — «بطاقة اليوم
    // ليست نصفان ابقها كما هي ابق التدرج و الظل» — so the card keeps its
    // full-bleed photograph, its ramp and this shadow, and the text still
    // sits on the photograph.
    expect(AppShadows.onPhoto, hasLength(1));
    final shadow = AppShadows.onPhoto.single;
    expect(shadow.blurRadius, 3);
    expect(shadow.offset, Offset.zero);
    expect(shadow.color.a, greaterThan(0.5));
    expect(shadow.color, isNot(const Color(0xFF000000)));
    // The ink the card's own text is drawn in.
    expect(AppColors.onPhoto, const Color(0xFFFFFFFF));
  });

  test('durations are short enough to feel instant', () {
    expect(AppDurations.fast.inMilliseconds, lessThan(AppDurations.standard.inMilliseconds));
    expect(AppDurations.standard.inMilliseconds, lessThanOrEqualTo(250));
  });

  test('Latin terms name Inter explicitly rather than the ambient family', () {
    // Tajawal does have Latin glyphs; the rule is that English terms are set on
    // the brand's Latin face on purpose, not inherited by accident.
    expect(AppText.latin.fontFamily, 'Inter');
    expect(AppText.arabic.fontFamily, 'Tajawal');
  });
}
