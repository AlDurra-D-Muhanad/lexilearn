import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';

/// The input outline, pinned at the theme.
///
/// **Why this file exists.** Material 3 does not paint a *filled* text field's
/// outline from `InputDecorationTheme.border`. It synthesises the outline inside
/// the decorator from `colorScheme.onSurfaceVariant`, and it selects
/// `enabledBorder` / `focusedBorder` / `disabledBorder` — not `border` — to do
/// it. `AppTheme` set only `border`, so every one of those three resolved to
/// `null`, the decorator fell back to `onSurfaceVariant`, and a plain `TextField`
/// under the app theme rasterised a `#6B7280` outline — the secondary *text*
/// grey — where the brand specifies `#E5E7EB`.
///
/// Measured, not assumed: overriding `onSurfaceVariant` to `#00FF00` and
/// rasterising produced a `#00FF00` border, and the theme's own `border` was
/// confirmed to read `#E5E7EB` at width 1.0 while the pixels said otherwise.
///
/// `onSurfaceVariant` is *not* the thing to change. It is correctly the muted
/// text role and `app_theme_test.dart` pins it; recolouring it would recolour
/// every muted string in the app. The fix is the three missing borders.
///
/// `HomeScreen` was the app's only text input, so before this file nothing would
/// have caught a regression here.
void main() {
  /// A `TextField` with **no local decoration at all** — every value must come
  /// from the theme, which is the whole point.
  Finder plainField() => find.byType(TextField);

  Color outlineColour(WidgetTester tester, InputBorder? border) {
    expect(border, isA<OutlineInputBorder>(),
        reason: 'the brand field is a pill, not an underlined box');
    return (border! as OutlineInputBorder).borderSide.color;
  }

  Future<InputDecoration> decorationFor(WidgetTester tester, Brightness mode) async {
    await tester.pumpWidget(MaterialApp(
      theme: mode == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      home: const Scaffold(body: Center(child: TextField())),
    ));
    await tester.pumpAndSettle();
    return tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
  }

  testWidgets('a plain field resolves the brand hairline, not the muted text colour',
      (tester) async {
    final decoration = await decorationFor(tester, Brightness.light);

    expect(decoration.enabledBorder, isNotNull,
        reason: 'a null enabledBorder is what let Material substitute '
            'onSurfaceVariant for the outline');
    expect(outlineColour(tester, decoration.enabledBorder), AppColors.borderLight);
  });

  testWidgets('the theme, not the decoration, is where that came from',
      (tester) async {
    // The decoration is empty on the widget. If this ever stops being true the
    // test above would be passing for the wrong reason — a screen that restated
    // its own border rather than the theme providing one.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: Center(child: TextField())),
    ));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(plainField());
    // A bare `TextField` still carries an empty `InputDecoration` rather than
    // `null`; what matters is that it specifies no border of its own. If this
    // ever stops being true the tests above would be passing for the wrong
    // reason — a screen restating its own outline instead of the theme's.
    final decoration = field.decoration!;
    expect(decoration.border, isNull);
    expect(decoration.enabledBorder, isNull);
    expect(decoration.focusedBorder, isNull);
    expect(decoration.disabledBorder, isNull);

  });

  testWidgets('the focused outline is the brand purple at 2px', (tester) async {
    final decoration = await decorationFor(tester, Brightness.light);

    expect(outlineColour(tester, decoration.focusedBorder), AppColors.gold);
    expect((decoration.focusedBorder! as OutlineInputBorder).borderSide.width, 2);
  });

  testWidgets('the disabled outline is the brand hairline too', (tester) async {
    final decoration = await decorationFor(tester, Brightness.light);

    expect(outlineColour(tester, decoration.disabledBorder), AppColors.borderLight);
  });

  testWidgets('every outline is a pill, at both brightnesses', (tester) async {
    for (final mode in <Brightness>[Brightness.light, Brightness.dark]) {
      final decoration = await decorationFor(tester, mode);
      for (final entry in <String, InputBorder?>{
        'enabledBorder': decoration.enabledBorder,
        'focusedBorder': decoration.focusedBorder,
        'disabledBorder': decoration.disabledBorder,
      }.entries) {
        final border = entry.value as OutlineInputBorder;
        expect(border.borderRadius.topLeft.x, AppRadii.pill,
            reason: '${entry.key} in $mode is not a pill');
      }
    }
  });

  testWidgets('dark mode takes the dark hairline', (tester) async {
    final decoration = await decorationFor(tester, Brightness.dark);

    expect(outlineColour(tester, decoration.enabledBorder), AppColors.outlineDark);
    expect(outlineColour(tester, decoration.focusedBorder), AppColors.gold);
    expect(outlineColour(tester, decoration.disabledBorder), AppColors.outlineDark);
  });

  testWidgets('onSurfaceVariant stays the muted text role', (tester) async {
    // The fix above deliberately did NOT touch this. If a later task
    // "simplifies" the input outline by recolouring the role, this fails.
    final themes = <(String, ColorScheme, Color)>[
      ('light', AppTheme.light().colorScheme, AppColors.textSecondaryLight),
      ('dark', AppTheme.dark().colorScheme, AppColors.textSecondaryDark),
    ];
    for (final (name, scheme, expected) in themes) {
      expect(scheme.onSurfaceVariant, expected, reason: name);
    }
  });
}
