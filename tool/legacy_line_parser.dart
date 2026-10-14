import 'package:crypto/crypto.dart';
import 'package:lexilearn/domain/vocab_entry.dart';

/// Why a source line did not become an entry. Surfaced by the converter so the
/// author can see exactly what was dropped, rather than guessing.
class LegacyParseIssue {
  const LegacyParseIssue({
    required this.lineNumber,
    required this.line,
    required this.reason,
  });

  final int lineNumber;
  final String line;
  final String reason;
}

class LegacyParseReport {
  const LegacyParseReport({required this.entries, required this.issues});

  final List<VocabEntry> entries;
  final List<LegacyParseIssue> issues;

  int get parsedCount => entries.length;
}

/// Converts the original `English.txt` ("term : translation", one per line)
/// into `VocabEntry` objects.
///
/// Deliberately lives in `tool/`: the app itself only ever reads JSON, so none
/// of this parsing cost or code is shipped to users.
class LegacyLineParser {
  const LegacyLineParser._();

  /// The `schemaVersion` this parser stamps into the packs it builds. It must
  /// track `VocabPack.currentSchemaVersion`, and it is restated here so a
  /// parser change is visible in the file that does the parsing.
  static const int supportedSchemaVersion = 1;

  /// Bidi control characters that survive copy-paste out of word processors.
  static final RegExp _bidiControls =
      RegExp('[\u200e\u200f\u202a-\u202e\u2066-\u2069]');

  static LegacyParseReport parse(String rawText) {
    final normalised = rawText.startsWith('\ufeff') ? rawText.substring(1) : rawText;
    final entries = <VocabEntry>[];
    final issues = <LegacyParseIssue>[];
    final seenTerms = <String>{};
    final lines = normalised.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final lineNumber = i + 1;
      final line = _clean(lines[i]);
      if (line.isEmpty) continue;
      if (line.contains('://')) {
        issues.add(LegacyParseIssue(
          lineNumber: lineNumber,
          line: line,
          reason: 'URL line: skipped, it has no term/translation pair',
        ));
        continue;
      }
      final colon = line.indexOf(':');
      if (colon < 0) {
        issues.add(LegacyParseIssue(
          lineNumber: lineNumber,
          line: line,
          reason: 'no colon: skipped, cannot tell term from translation',
        ));
        continue;
      }
      final term = line.substring(0, colon).trim();
      final translationText = line.substring(colon + 1).trim();
      if (term.isEmpty || translationText.isEmpty) {
        issues.add(LegacyParseIssue(
          lineNumber: lineNumber,
          line: line,
          reason: 'empty term or empty translation: skipped',
        ));
        continue;
      }
      if (!seenTerms.add(term.toLowerCase())) {
        issues.add(LegacyParseIssue(
          lineNumber: lineNumber,
          line: line,
          reason: 'duplicate term "$term": kept the first occurrence only',
        ));
        continue;
      }
      final translations = translationText
          .split(',')
          .map(_clean)
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      entries.add(VocabEntry(
        id: entryId(term),
        term: term,
        translations: translations.isEmpty ? <String>[translationText] : translations,
      ));
    }
    return LegacyParseReport(entries: entries, issues: issues);
  }

  /// Stable slug plus a short digest of the *raw* term, so `check up` and
  /// `check-up` cannot collide and a regenerated asset keeps the same ids.
  static String entryId(String term) {
    final slug = term
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final digest = sha1.convert(term.codeUnits).toString().substring(0, 6);
    return '${slug.isEmpty ? 'entry' : slug}-$digest';
  }

  static String _clean(String value) => value.replaceAll(_bidiControls, '').trim();
}
