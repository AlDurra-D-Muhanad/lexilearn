/// The dictionary, as a pack in the app's own pack table.
///
/// **The dictionary is a pack, and the starter pack stays.** The app already
/// has an active-pack concept — `HomeShell` resolves one key at start-up and
/// hands it to all four destinations — and the brief is explicit that this
/// round must use it rather than build a second one. So the dictionary is one
/// more pack in that list, and the 297-word starter set is the other.
///
/// ## Why the dictionary has a row in `packs` at all
///
/// `favorites.pack_key` is a foreign key onto `packs(pack_key)`. A favourite
/// for a dictionary word is keyed by the dictionary's pack key, and a row
/// that does not exist is rejected by SQLite — so the dictionary needs a row
/// of its own. It has **no rows in `entries`**, which is what keeps the
/// dictionary out of the backup: `exportBackupJson` walks the packs, and a
/// pack with no entries is skipped rather than exported as an empty
/// vocabulary list. The favourites are still exported, because they are the
/// user's data and not the dictionary's.
library;

/// The pack key of the dictionary.
///
/// **A namespace of its own**, so the two packs' entry ids can never collide.
/// A favourite is keyed on `(pack_key, entry_id)`, and the backup carries
/// those, so two packs that shared an entry id would share a favourite.
const String dictionaryPackKey = 'dictionary_en_ar';

/// The title of the dictionary pack, as the pack list shows it.
///
/// **The user's ruling, verbatim: «القاموس الكامل».**
///
/// The pack's key is `dictionary_en_ar`, and it was on the home screen's chip
/// in front of the user — a technical identifier, in the place the app names
/// itself. The key stays what it is (it is the foreign key every dictionary
/// favourite is filed under); **the name the user reads is this one.**
const String dictionaryPackTitle = 'القاموس الكامل';

/// The pack key of the bundled starter set.
///
/// **The 297-word pack, kept.** It is the pack the app shipped with, it is
/// small enough to hold in a phone's memory, and it is the pack a user who
/// has not finished the dictionary copy can study straight away. It is
/// labelled as a starter set in the pack list.
const String starterPackKey = 'english_ar_v1';

/// The title of the starter set, as the pack list shows it.
///
/// **"Starter set", and the words are the app's own.** The dictionary is the
/// default; the 297 words are a starting point, and saying so is honest about
/// the difference between a pack of 31,600 entries and a pack of 297.
const String starterPackTitle = 'English to Arabic — starter set';

/// The entry id of a dictionary headword.
///
/// **Namespaced, so the two packs cannot collide.** The starter pack's ids
/// are `term-slug-hash` (`ghost-clusters-4da03e`); these are `dict:<norm>`.
/// No starter id can begin with `dict:` and no dictionary id can be mistaken
/// for one.
String dictionaryEntryId(String norm) => 'dict:$norm';

/// The pack key a dictionary entry's favourite is filed under.
const String dictionaryFavoritesPackKey = dictionaryPackKey;

/// How many dictionary words the study surfaces draw from at once.
///
/// **A sample, and the number is a bound rather than a target.** A deck of ten
/// cards and a quiz of ten questions need a few dozen words; reading all
/// 31,600 of them on every screen mount would be a second of waiting for
/// nothing. The pool is a *sample* of the dictionary, and the dictionary is
/// still all there — the search reaches every one of the 31,600.
const int dictionaryStudyPoolSize = 400;
