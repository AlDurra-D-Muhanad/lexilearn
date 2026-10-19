// GENERATED FILE - DO NOT EDIT.
//
// Written by `tool/build_dictionary_db.dart`, which is the only thing that may
// write it. Regenerate with:
//
//   dart run tool/build_dictionary_db.dart
//
// It records the facts about the shipped artefact that the runtime and the
// tests both need, so that neither of them has to hard-code a number that can
// drift away from the file on disk. `test/data/dictionary/dictionary_schema_test.dart`
// re-measures the artefact and fails if any of these has stopped being true.

/// The exact size, in bytes, of `assets/dictionary/en_ar.db`.
const int dictionaryArtifactBytes = 26599424;

/// The SHA-256 of `assets/dictionary/en_ar.db`, lower-case hex.
const String dictionaryArtifactSha256 = 'd66ee0bc62d73f71d7b979d02eddc36f31a6a69c3c6728282c6ce99643311445';

/// The SHA-256 of the source JSON the artefact was built from.
const String dictionarySourceSha256 = 'd9a64f1f45ed2afe8a3bd1e6a97c488ceca5f9966734f93d3c48e081f4b669b1';

/// The size, in bytes, of the source JSON.
const int dictionarySourceBytes = 13302909;

/// The name of the source JSON.
const String dictionarySourceFileName = 'en-ar-dictionary.json';

/// Headwords in the artefact, after the case-variant merge.
const int dictionaryEntryCount = 31600;

/// Headwords in the source, before the merge.
const int dictionarySourceEntryCount = 32451;

/// Senses in the artefact.
const int dictionarySenseCount = 81451;

/// Senses carrying Arabic.
const int dictionaryArabicSenseCount = 47266;

/// Example sentences.
const int dictionaryExampleCount = 37063;

/// Headwords carrying a phonetic transcription.
const int dictionaryIpaEntryCount = 15952;

/// Distinct normalised Arabic keys.
const int dictionaryArabicKeyCount = 30508;

/// Rows in the `trigrams` table.
const int dictionaryTrigramCount = 327705;
