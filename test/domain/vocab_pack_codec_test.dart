import 'package:flutter_test/flutter_test.dart';
import 'package:lexilearn/domain/pack_codec.dart';

void main() {
  group('PackCodec', () {
    test('decodes a well-formed pack', () {
      final json = '''
{
  "schemaVersion": 1,
  "packId": "english_ar_v1",
  "title": "English to Arabic",
  "sourceLanguage": "en",
  "targetLanguage": "ar",
  "entries": [
    {"id": "fever-a1b2c3", "term": "fever", "translations": ["\\u062d\\u0645\\u0649", "\\u0633\\u062e\\u0648\\u0646\\u0629"]}
  ]
}
''';
      final pack = PackCodec.decodePack(json);
      expect(pack.schemaVersion, 1);
      expect(pack.packId, 'english_ar_v1');
      expect(pack.entryCount, 1);
      expect(pack.entries.first.term, 'fever');
      expect(pack.entries.first.translations, hasLength(2));
      expect(pack.entries.first.note, isEmpty);
    });

    test('encode then decode round-trips without loss', () {
      final original = PackCodec.decodePack('''
{"schemaVersion":1,"packId":"p","title":"T","sourceLanguage":"en","targetLanguage":"ar",
 "entries":[{"id":"a-000001","term":"A","translations":["x"],"note":"n"}]}
''');
      final again = PackCodec.decodePack(PackCodec.encodePack(original));
      expect(again.entries.single, original.entries.single);
      expect(again.packId, original.packId);
    });

    test('rejects text that is not JSON', () {
      expect(() => PackCodec.decodePack('not json at all'),
          throwsA(isA<PackDecodeException>()));
    });

    test('rejects JSON whose root is not an object', () {
      expect(() => PackCodec.decodePack('[1,2,3]'),
          throwsA(isA<PackDecodeException>()));
    });

    test('rejects a missing entries list', () {
      expect(
        () => PackCodec.decodePack(
            '{"schemaVersion":1,"packId":"p","title":"T","sourceLanguage":"en","targetLanguage":"ar"}'),
        throwsA(isA<PackDecodeException>()),
      );
    });

    test('rejects an unsupported schemaVersion instead of guessing', () {
      expect(
        () => PackCodec.decodePack(
            '{"schemaVersion":99,"packId":"p","title":"T","sourceLanguage":"en","targetLanguage":"ar","entries":[]}'),
        throwsA(isA<PackDecodeException>()),
      );
    });

    test('rejects an entry whose translations is not a list of strings', () {
      expect(
        () => PackCodec.decodePack(
            '{"schemaVersion":1,"packId":"p","title":"T","sourceLanguage":"en","targetLanguage":"ar",'
            '"entries":[{"id":"a-1","term":"A","translations":"x"}]}'),
        throwsA(isA<PackDecodeException>()),
      );
    });

    test('rejects an entry with an empty term', () {
      expect(
        () => PackCodec.decodePack(
            '{"schemaVersion":1,"packId":"p","title":"T","sourceLanguage":"en","targetLanguage":"ar",'
            '"entries":[{"id":"a-1","term":"   ","translations":["x"]}]}'),
        throwsA(isA<PackDecodeException>()),
      );
    });

    test('rejects two entries sharing the same id', () {
      expect(
        () => PackCodec.decodePack(
            '{"schemaVersion":1,"packId":"p","title":"T","sourceLanguage":"en","targetLanguage":"ar",'
            '"entries":[{"id":"dup","term":"A","translations":["x"]},{"id":"dup","term":"B","translations":["y"]}]}'),
        throwsA(isA<PackDecodeException>()),
      );
    });

    test('keeps phonetic, part of speech, synonyms, and examples', () {
      final pack = PackCodec.decodePack('''
{"schemaVersion":1,"packId":"p","title":"T","sourceLanguage":"en","targetLanguage":"ar",
 "entries":[{"id":"s-1","term":"serenity","translations":["الهدوء"],
   "phonetic":"/səˈrenəti/","partOfSpeech":"noun",
   "synonyms":["peace","tranquility"],
   "examples":["The room was filled with serenity."]}]}
''');
      final entry = pack.entries.single;
      expect(entry.phonetic, '/səˈrenəti/');
      expect(entry.partOfSpeech, 'noun');
      expect(entry.synonyms, <String>['peace', 'tranquility']);
      expect(entry.examples, hasLength(1));
    });

    test('a bundled entry with none of that data loads with empty fields', () {
      final pack = PackCodec.decodePack(
          '{"schemaVersion":1,"packId":"p","title":"T","sourceLanguage":"en",'
          '"targetLanguage":"ar","entries":[{"id":"f-1","term":"fever","translations":["حمى"]}]}');
      final entry = pack.entries.single;
      expect(entry.phonetic, isEmpty);
      expect(entry.partOfSpeech, isEmpty);
      expect(entry.synonyms, isEmpty);
      expect(entry.examples, isEmpty);
    });

    test('a rich entry survives encode then decode unchanged', () {
      final pack = PackCodec.decodePack('''
{"schemaVersion":1,"packId":"p","title":"T","sourceLanguage":"en","targetLanguage":"ar",
 "entries":[{"id":"s-1","term":"serenity","translations":["الهدوء"],
   "phonetic":"/x/","partOfSpeech":"noun",
   "synonyms":["peace"],"examples":["e1","e2"]}]}
''');
      final again = PackCodec.decodePack(PackCodec.encodePack(pack));
      expect(again.entries.single, pack.entries.single);
    });
  });
}
