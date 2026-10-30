/// The user's own dictionary: words they typed themselves, with the meanings
/// they want them to carry.
///
/// **Why this is a stored pack and not a derived one.** `my_favourites` is
/// derived because it is a second view of words that already exist in other
/// packs. This one is the opposite: the words exist nowhere else. A student
/// adding «البرمجة» for a curriculum word needs that pair stored, backed up and
/// restored — so this is a real `packs` row with real `entries` rows, exactly
/// like an imported pack, and the whole existing machinery (search, quiz,
/// flashcards, favourites, progress, backup) works on it without a special
/// path.
///
/// The specification is the user's `README.MD` in `lexilearn notes`:
/// *«اريد اضافة ميزة جديدة وهي ان يستطيع المستخدم انشاء قاموسه الخاص و جعل
/// امكانية اختيار هذا القاموس كحزمة مستقلة عن باقي الحزم ليستطيع المستخدم البحث
/// و اجراء الاختبارات من قاموسه الخاص.»*
library;

import 'vocab_entry.dart';

/// The pack key of the user's own dictionary.
///
/// **Reserved against pack files, and deliberately not against backups.** A
/// `.json` pack claiming this key is refused: it would install somebody else's
/// dataset under the name of the user's own words. A **backup** is a different
/// thing — it is a snapshot of this device or of a device the user is moving
/// from, and the custom dictionary is part of that snapshot, so the restore
/// accepts it. See `VocabRepository.importBackupJson`.
const String customDictionaryPackKey = 'my_dictionary';

/// What the dictionary is called, everywhere it is named.
///
/// **The user's own words, in the artwork and in the brief**: «قاموسك الخاص».
/// It is the same string on the Home tile, on the screen's header and in the
/// pack list, so the thing the user taps is the thing they then see.
const String customDictionaryTitle = 'قاموسك الخاص';

/// The chip the pack list shows on this pack's row.
///
/// **Not «مدمجة».** The two integrated packs ship with the app; this one is
/// written by the user. The chip says whose words they are, and — together with
/// the missing delete control — says that the way to empty it is to delete the
/// words themselves.
const String customDictionaryChip = 'كلماتك';

/// The prefix every entry id of the user's own dictionary carries.
///
/// **Namespaced like every other pack's ids**, so a custom word and a starter
/// word can never collide in `favorites` or `word_progress`, where the key is
/// `(pack_key, entry_id)`. It also makes the origin readable: an id beginning
/// `mine:` was typed by the user.
const String customEntryPrefix = 'mine:';

/// The longest word the add screen accepts.
///
/// **A bound, not a target.** The dataset's longest headword is a sentence;
/// the user's field is for a word. A hundred characters is longer than any
/// English word and short enough that the field cannot be used as a notebook.
const int customWordMaxLength = 100;

/// The longest meaning the add screen accepts, and the number under the field.
///
/// **The user's artwork draws `0/500`**, so 500 is the number, not a guess.
const int customMeaningMaxLength = 500;

/// A refusal the add screen can show as a sentence.
///
/// **A typed exception rather than a bare `ArgumentError`**, because every one
/// of these is a state the user can reach by typing — an empty field, a
/// duplicate word — and the screen has to say which. The repository throws it;
/// the controller turns it into [message].
class CustomDictionaryException implements Exception {
  const CustomDictionaryException(this.message);

  /// The sentence the screen shows. Arabic, like every other string the user
  /// reads.
  final String message;

  @override
  String toString() => 'CustomDictionaryException: $message';
}

/// The stored form of a word the user typed: trimmed, one space between runs.
///
/// **The word is stored as typed**, with its case and its punctuation, because
/// the user may be entering a curriculum term whose spelling matters. The
/// *normalisation* below is only for deciding whether a word is already there.
String cleanCustomTerm(String term) =>
    term.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The form two spellings of the same word share.
///
/// **Case and spacing are not meaning.** A student who types `Serendipity`
/// after `serendipity` has typed the same word, and a dictionary with both
/// would be a dictionary that cannot be studied: the quiz would ask the same
/// word twice under two ids. The comparison is therefore lowercase, trimmed,
/// and whitespace-collapsed — the same rule [SearchMatcher] uses, minus the
/// invisible-mark stripping, which is about pasted text rather than identity.
String normaliseCustomTerm(String term) =>
    cleanCustomTerm(term).toLowerCase();

/// The id of a word the user typed.
///
/// **Stable, so progress and favourites survive.** The id is built from the
/// **normalised** term, so a word is one word across case changes, and a word
/// that is deleted and typed again returns to the same id and the same history.
///
/// **Readable, and not a hash of the meaning.** The slug is the term when the
/// term is Latin; the digest is a short FNV-1a of the normalised term and is
/// what keeps `check up` and `check-up` apart after the slug has collapsed
/// both to `check-up`. An Arabic term has no Latin slug, so the id is
/// `mine:word-<digest>` — ugly, and never shown to the user, who reads
/// [VocabEntry.term].
String customEntryId(String term) {
  final normalised = normaliseCustomTerm(term);
  final slug = normalised
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final digest = _fnv1a(normalised).toRadixString(16).padLeft(8, '0');
  return '$customEntryPrefix${slug.isEmpty ? 'word' : slug}-${digest.substring(0, 6)}';
}

/// The entry the user typed, as the rest of the app sees it.
///
/// **One translation, because the screen has one meaning field.** The artwork
/// draws «الكلمة» and «المعنى», and the meaning is stored as the first
/// translation — which is what [VocabEntry.primaryTranslation] and every study
/// surface read.
VocabEntry customEntry({required String term, required String meaning}) {
  final word = cleanCustomTerm(term);
  final definition = meaning.trim();
  return VocabEntry(
    id: customEntryId(word),
    term: word,
    translations: <String>[definition],
  );
}

/// How many words the list screen says there are.
///
/// **Arabic counts its nouns in three ranges**, and `3 كلمات` is wrong for 1,
/// 2 and 11. The screen's own count is the only place this matters, so the rule
/// is written once, here, and tested.
String customWordCountLabel(int count) {
  if (count <= 0) return 'لا كلمات بعد';
  if (count == 1) return 'كلمة واحدة';
  if (count == 2) return 'كلمتان';
  if (count <= 10) return '$count كلمات';
  return '$count كلمة';
}

/// FNV-1a, 32-bit.
///
/// **No dependency and no `dart:convert`.** The only hashing this app needs is
/// an id digest that is stable across runs and platforms; the `crypto`
/// package's SHA-1 is in the tool's dependencies, not the app's, and pulling it
/// in for six hex characters would be a dependency the app does not otherwise
/// use. FNV-1a is two operations and is specified.
int _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    // `& 0xffffffff` keeps the multiplication in 32 bits even though Dart's
    // integers are 64-bit, so the digest is the same on every platform and in
    // every future version of the language.
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}
