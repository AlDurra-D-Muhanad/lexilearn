/// The user's own pack: every word they have starred, in either of the app's
/// two integrated packs.
///
/// **DERIVED, never stored.** There is no row for it in `packs`, no rows for it
/// in `entries`, and no rows for it in `favorites`: its contents are computed
/// from the favourites table every time the pack list is read, so it cannot
/// drift from the favourites, and it cannot be deleted or imported.
///
/// The specification is `docs/my-favourites-pack.md`; the user's own words are
/// «حزمة مفضلتي يجب ان تكون مستقلة تزداد كلماتها و تنقص كلما اضاف
/// المستخدم كلمة الى المفضلة او ازال كلمة اي اي بكل بساطة هي حزمة جديدة
/// يتم ملؤها و تفريغها من قبل المستخدم عبر اضافة كلمة او ازالة كلمة من اي
/// من الحزمتين المدمجتين حاليا».
///
/// **The two packs do not live in the same place**, and that is the whole
/// difficulty:
///
/// * the 297-word starter set is rows in the **app database** (`packs`,
///   `entries`);
/// * the full dictionary is a **separate read-only file**
///   (`assets/dictionary/en_ar.db`) with its own `entries` and `senses`
///   tables, reached through `lib/data/dictionary/dictionary_engine.dart`.
///
/// So a favourite is not one thing. `favorites` is keyed on
/// `(pack_key, entry_id)` and the two packs use different id schemes, which is
/// why this pack has to resolve each favourite against whichever source owns
/// it — `lib/data/vocab_repository.dart` → `myFavourites`.
library;

/// The pack key of the derived pack.
///
/// **Reserved, and reserved by rule.** No stored pack may claim it: the import
/// path refuses a pack whose id is this one, and a backup that carries such a
/// pack is refused before the restore opens its transaction. The key is not a
/// secret — it is in the database — it is a *namespace*, and a namespace that a
/// stored pack could claim would not be one.
///
/// It is deliberately **not** one of the two integrated packs' keys, and it is
/// deliberately **not** `dictionaryFavoritesPackKey`: that constant is the
/// dictionary's favourites seen under the dictionary's own key, which is a
/// different thing entirely. See `lib/domain/dictionary_pack.dart`.
const String myFavouritesPackKey = 'my_favourites';

/// The title of the derived pack, as the pack list shows it.
///
/// **The user's own word, verbatim: «مفضلتي».**
///
/// The two integrated packs are named for what they are — «القاموس الكامل» and
/// the starter set — and this one is named for what it is to the person reading
/// it: *my favourites*. It is the only pack in the app whose contents are the
/// user's own curation rather than a dataset, and the name says so.
const String myFavouritesPackTitle = 'مفضلتي';

/// The prefix every entry id of the derived pack carries.
///
/// **The namespaced composite, and why it is a namespace rather than a hash.**
/// A pack's entries are keyed by id everywhere — progress rows, the quiz, the
/// flashcard deck — and the id has to be:
///
/// * **unique**, because the two packs may hold the same English word and the
///   two are different entries in two different sources;
/// * **stable**, because the same favourite must produce the same id on every
///   derivation, so the progress recorded against it survives a rebuild;
/// * **honest**, because reading the id tells you which pack the word came
///   from — which is what the user asked for: a favourite in *either* pack
///   shows up here.
///
/// It must **not** be a re-hash of the word. A hash would be stable too, but it
/// would hide the source, and it could collide with a real pack's ids in
/// `favorites` and `progress`, where the key is `(pack_key, entry_id)` and
/// `pack_key` would be this pack's own key.
const String myFavouritesEntryPrefix = 'myfav:';

/// The id a favourite carries inside the derived pack.
///
/// **The source pack's key, then the source entry's own id.** A starter-pack
/// favourite is `myfav:english_ar_v1:ghost-clusters-4da03e`; a dictionary
/// favourite is `myfav:dictionary_en_ar:dict:abandon` — the dictionary's own
/// namespaced id, kept whole, so the origin is readable in both.
///
/// The composition is **not** reversible by splitting on a colon, and it is not
/// meant to be: the dictionary's entry id carries a colon of its own, and an
/// imported pack's key is whatever its file said. The repository therefore
/// never parses this id back — it **recomputes** it from the favourites table,
/// which is the only place the answer can be got right. See
/// `VocabRepository.myFavourites`.
String myFavouritesEntryId(String sourcePackKey, String sourceEntryId) =>
    '$myFavouritesEntryPrefix$sourcePackKey:$sourceEntryId';

/// The chip the pack list shows on the derived pack's row.
///
/// **Not «مدمجة», and the reason is the user's own words.** The two
/// integrated packs are «الحزمتين المدمجتين»; the derived pack is «حزمة
/// جديدة يتم ملؤها و تفريغها من قبل المستخدم». Calling it "bundled" would say
/// it is a third dataset shipped with the app, which is the opposite of what it
/// is: the words in it are the user's own curation.
const String myFavouritesPackChip = 'من المفضلة';
