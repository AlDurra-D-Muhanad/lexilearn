import 'package:lexilearn/data/dictionary/dictionary_models.dart';

/// Which dictionary entries may become a flashcard or a quiz question.
///
/// **The dictionary keeps all 31,600.** A dictionary contains affixes
/// legitimately — `-able` and `-ation` are real entries, and a user looking
/// them up has to find them. **Only the study surface filters them**, because
/// a flashcard that says «-ation: …» teaches nothing and a quiz option that
/// is an affix is not a plausible answer to anything.
///
/// The rules are the dictionary's own, not a guess:
///
/// * **An affix is a headword that begins with a hyphen.** The brief's rule,
///   and the objective one: `-able`, `-ation`, `-er`, `-ese`. The dictionary
///   also carries eight prefixes that *end* with a hyphen — `anti-`, `bio-`,
///   `electro-`, `extra-`, `meso-`, `pseudo-`, `tri-`, `vice-` — and the
///   dictionary marks them with the part of speech `pref`; and two entries
///   that begin with an elision — `'s gravenhage`, `'s-Hertogenbosch`. So the
///   rule is "begins with a hyphen, or the dictionary itself calls it an
///   affix".
/// * **A proper noun is an entry every one of whose senses the dictionary
///   marks `prop. n`.** Not "has a proper-noun sense": `may` is the month and
///   a modal verb, and a learner who is asked about `may` is being asked
///   about the verb. An entry whose senses are *all* proper nouns is a name,
///   and a name is not a flashcard.
final class StudyFilter {
  const StudyFilter._();

  /// The part-of-speech markers the dictionary itself uses for an affix.
  static const Set<String> affixPartsOfSpeech = <String>{'suf', 'pref'};

  /// The part-of-speech marker the dictionary itself uses for a proper noun.
  static const String properNounPartOfSpeech = 'prop. n';

  /// Whether [entry] is an affix rather than a word.
  ///
  /// **Needs the senses.** The dictionary's own `suf` and `pref` markers live
  /// on the senses, so an entry read without them cannot be judged by them —
  /// which is why [admits] takes an entry with its senses and not a headword
  /// string.
  static bool isAffix(DictionaryEntry entry) {
    if (entry.word.startsWith('-')) return true;
    if (entry.word.startsWith("'")) return true;
    return entry.senses.any(
      (sense) => affixPartsOfSpeech.contains(sense.pos),
    );
  }

  /// Whether [entry] is a proper noun and nothing else.
  ///
  /// **Every sense, not one of them.** An entry with a proper-noun sense and
  /// a common-noun sense is a common noun as well, and it is the common noun
  /// a learner wants.
  static bool isProperNoun(DictionaryEntry entry) {
    if (entry.senses.isEmpty) return false;
    return entry.senses.every(
      (sense) => sense.pos == properNounPartOfSpeech,
    );
  }

  /// Whether [entry] may become a flashcard or a quiz question.
  static bool admits(DictionaryEntry entry) =>
      !isAffix(entry) && !isProperNoun(entry);
}
