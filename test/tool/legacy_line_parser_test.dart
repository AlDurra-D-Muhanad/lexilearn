import 'package:flutter_test/flutter_test.dart';
// `tool/legacy_line_parser.dart` deliberately sits outside `lib/` so it is not
// compiled into the app binary, which means it has no `package:` URI and must
// be imported by relative path. Same file the converter runs.
import '../../tool/legacy_line_parser.dart';

void main() {
  group('LegacyLineParser', () {
    test('splits on the first colon and trims both sides', () {
      final report = LegacyLineParser.parse('ghost clusters : \u0645\u062c\u0645\u0648\u0639\u0627\u062a \u0627\u0644\u0623\u0634\u0628\u0627\u062d');
      expect(report.entries, hasLength(1));
      expect(report.entries.single.term, 'ghost clusters');
      expect(report.entries.single.translations, <String>['\u0645\u062c\u0645\u0648\u0639\u0627\u062a \u0627\u0644\u0623\u0634\u0628\u0627\u062d']);
    });

    test('splits a comma-separated translation list into separate entries', () {
      final report = LegacyLineParser.parse(
          'session : \u0627\u0644\u062c\u0644\u0633\u0629,\u062d\u0635\u0629');
      expect(report.entries.single.translations, hasLength(2));
      expect(report.entries.single.translations.first, '\u0627\u0644\u062c\u0644\u0633\u0629');
    });

    test('keeps text after a second colon inside the translation', () {
      final report = LegacyLineParser.parse('ratio : 3:1 \u0646\u0633\u0628\u0629');
      expect(report.entries.single.term, 'ratio');
      expect(report.entries.single.translations.single, contains('3:1'));
    });

    test('reports a colon-less line instead of inventing an entry', () {
      final report = LegacyLineParser.parse("You're scaring me, bro, okay?");
      expect(report.entries, isEmpty);
      expect(report.issues.single.reason, contains('no colon'));
      expect(report.issues.single.lineNumber, 1);
    });

    test('skips blank lines silently', () {
      final report = LegacyLineParser.parse('\n\n   \n');
      expect(report.entries, isEmpty);
      expect(report.issues, isEmpty);
    });

    test('treats a URL line as a term with no translation and reports it', () {
      final report = LegacyLineParser.parse('https://example.com: a site');
      expect(report.entries, isEmpty);
      expect(report.issues.single.reason, contains('URL'));
    });

    test('strips bidi control characters', () {
      final report = LegacyLineParser.parse(
          'Boar pit : \u202b\u062d\u0641\u0631\u0629 \u062e\u0646\u0627\u0632\u064a\u0631');
      expect(report.entries.single.translations.single,
          '\u062d\u0641\u0631\u0629 \u062e\u0646\u0627\u0632\u064a\u0631');
    });

    test('keeps the first of two identical terms and reports the duplicate', () {
      final report = LegacyLineParser.parse('Buried : a\nBuried : b');
      expect(report.entries, hasLength(1));
      expect(report.entries.single.translations.single, 'a');
      expect(report.issues.single.reason, contains('duplicate'));
    });

    test('ignores a UTF-8 BOM at the start of the file', () {
      final report = LegacyLineParser.parse('\ufeffBury : \u064a\u062f\u0641\u0646');
      expect(report.entries.single.term, 'Bury');
    });

    test('produces ids that are stable across runs', () {
      final first = LegacyLineParser.parse('Buried : a');
      final second = LegacyLineParser.parse('Buried : a');
      expect(first.entries.single.id, second.entries.single.id);
      expect(first.entries.single.id, matches(RegExp(r'^buried-[0-9a-f]{6}$')));
    });

    test('gives different ids to two terms with the same slug', () {
      final report = LegacyLineParser.parse('check up : a\ncheck-up : b');
      final ids = report.entries.map((e) => e.id).toSet();
      expect(ids, hasLength(2));
    });
  });
}
