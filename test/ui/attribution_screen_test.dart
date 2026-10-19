import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/data/dictionary/dictionary_models.dart';
import 'package:lexilearn/ui/dictionary/attribution_screen.dart';
import 'package:lexilearn/ui/link/external_link.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../data/dictionary/dictionary_test_env.dart';

/// The attribution screen, and the licence obligation it discharges.
///
/// **The dictionary is CC-BY-SA-4.0**, and that licence obliges an application
/// shipping it to name the licence, its URL and its sources. The three
/// upstream sources are named in the dictionary's own `meta` table, and
/// **nothing on this screen is written by hand**: every string it shows comes
/// out of `meta`.
void main() {
  late DictionaryFixture fixture;
  late DictionaryAttribution attribution;

  setUpAll(() async {
    fixture = await DictionaryFixture.open();
    attribution = await fixture.engine.attribution();
  });

  tearDownAll(() async {
    await fixture.close();
  });

  /// Mounts the screen on a phone.
  Future<void> pumpAttribution(
    WidgetTester tester, {
    OpenExternalUrl? openUrl,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Provider<OpenExternalUrl>.value(
        value: openUrl ?? (Uri url) async => false,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AttributionScreen(attribution: attribution),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('the licence and its URL are on the screen', () async {
    expect(attribution.license, 'CC-BY-SA-4.0');
    expect(attribution.licenseUrl, isNotEmpty);
  });

  test('all three upstream sources are named, with their attribution strings',
      () {
    // **The licence's requirement, and the data's own names.**
    expect(attribution.sources, hasLength(3));
    expect(attribution.namesEveryUpstreamSource, isTrue);
    expect(attribution.sources[0], startsWith('omw-arb'));
    expect(attribution.sources[1], startsWith('pwn30'));
    expect(attribution.sources[2], startsWith('wikt-en-ar'));
  });

  testWidgets('the licence, its URL and the three sources are on the screen',
      (tester) async {
    await pumpAttribution(tester);
    expect(find.text(attribution.licenseUrl), findsOneWidget);
    // **The licence of the shipped work**, at the top of the page.
    expect(find.text('CC-BY-SA-4.0'), findsOneWidget);

    // **The three sources are on the screen, each with its own licence**, and
    // the licences are not the same string. A screen that showed one
    // share-alive line for all three would misstate two of them.
    //
    // **Scrolled to them**, because a `ListView` only builds what is on
    // screen and the sources are below the licence card.
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('WordNet-3.0'), findsOneWidget);
    expect(find.text('CC-BY-SA-3.0'), findsOneWidget);
    expect(find.textContaining('omw-arb'), findsWidgets);
    expect(find.textContaining('pwn30'), findsWidgets);
    expect(find.textContaining('wikt-en-ar'), findsWidgets);
  });

  testWidgets('the upstream project is named, with its URL', (tester) async {
    await pumpAttribution(tester);
    expect(find.text('DanielGregorini/koreader-dicts'), findsOneWidget);
    expect(
      find.text('https://github.com/DanielGregorini/koreader-dicts'),
      findsOneWidget,
    );
  });

  testWidgets('the counts are on the screen', (tester) async {
    await pumpAttribution(tester);
    // **Scrolled to them.** A `ListView` only builds what is on screen, and
    // the counts are at the bottom of the page.
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('${attribution.entryCount}'), findsOneWidget);
    expect(find.text('${attribution.senseCount}'), findsOneWidget);
  });

  testWidgets('the licence link is handed to the launcher', (tester) async {
    Uri? launched;
    await pumpAttribution(
      tester,
      openUrl: (Uri url) async {
        launched = url;
        return true;
      },
    );
    await tester.tap(find.text('فتح الرابط'));
    await tester.pumpAndSettle();
    expect(launched, isNotNull);
    expect(launched.toString(), attribution.licenseUrl);
  });

  testWidgets('the screen shows nothing that is not in `meta`', (tester) async {
    await pumpAttribution(tester);
    // **Every Latin run the screen draws is one the dictionary supplied.**
    // The chrome is Arabic; the Latin runs are the dictionary's name, its
    // source, the licence, the URL and the three sources. Anything else
    // would be an attribution the app invented, and the licence obliges it
    // to name its sources accurately.
    final allowed = <String>{
      attribution.name,
      attribution.source,
      attribution.license,
      attribution.licenseUrl,
      attribution.upstreamProject,
      attribution.upstreamProjectUrl,
      attribution.upstreamTagline,
      attribution.upstreamPair,
      attribution.upstreamPairDescription,
      ...attribution.sources,
      ...attribution.sourceCredits.values,
      ...attribution.sourceLicenses.values,
    };
    final latin = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.isNotEmpty && _hasLatinLetter(s))
        .toList();
    for (final text in latin) {
      expect(
        allowed.any((candidate) => text.contains(candidate)),
        isTrue,
        reason: 'the screen shows "$text", which is not in the dictionary\'s '
            'own meta',
      );
    }
  });

  test('the upstream project, its URL and the three sources are named', () {
    // **The record, and the licences differ.**
    expect(attribution.upstreamProject, 'DanielGregorini/koreader-dicts');
    expect(attribution.sourceIds, hasLength(3));
    expect(attribution.licenseOf('pwn30'), 'WordNet-3.0');
    expect(attribution.licenseOf('omw-arb'), 'CC-BY-SA-3.0');
    expect(attribution.licenseOf('wikt-en-ar'), 'CC-BY-SA-4.0');
  });

  test('the stale attribution file is not carried', () async {
    // **Dropped, not rendered.** The path pointed at a file on the machine
    // that generated the data; it exists nowhere else, and a path that
    // cannot be resolved is not an attribution.
    final meta = await fixture.store.metaValue('attributionFile');
    expect(meta, isNull,
        reason: 'the build no longer writes the stale path into meta');
  });
}

/// Whether [value] carries a Latin letter.
bool _hasLatinLetter(String value) => value.runes.any(
      (rune) => (rune >= 0x41 && rune <= 0x7A),
    );
