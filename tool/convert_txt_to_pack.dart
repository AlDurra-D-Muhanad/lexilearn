import 'dart:convert';
import 'dart:io';

import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/domain/vocab_pack.dart';

import 'legacy_line_parser.dart';

/// Regenerates assets/packs/english_ar_v1.json from the original English.txt.
///
/// Usage:
///   dart run tool/convert_txt_to_pack.dart "C:\path\to\English.txt"
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/convert_txt_to_pack.dart <English.txt>');
    exitCode = 64;
    return;
  }
  final source = File(args.single);
  if (!source.existsSync()) {
    stderr.writeln('Source file not found: ${source.path}');
    exitCode = 66;
    return;
  }
  final report = LegacyLineParser.parse(await source.readAsString(encoding: utf8));
  final pack = VocabPack(
    schemaVersion: VocabPack.currentSchemaVersion,
    packId: 'english_ar_v1',
    title: 'English to Arabic',
    sourceLanguage: 'en',
    targetLanguage: 'ar',
    entries: report.entries,
  );
  final out = File('assets/packs/english_ar_v1.json');
  await out.parent.create(recursive: true);
  await out.writeAsString(PackCodec.encodePack(pack), encoding: utf8);

  stdout.writeln('Parsed ${report.parsedCount} entries -> ${out.path}');
  stdout.writeln('Skipped ${report.issues.length} line(s):');
  for (final issue in report.issues) {
    stdout.writeln('  line ${issue.lineNumber}: ${issue.reason}');
    stdout.writeln('    ${issue.line}');
  }
}