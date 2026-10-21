# "My Favourites" — a pack that is derived, not stored

**The user's words:** «حزمة مفضلتي يجب ان تكون مستقلة تزداد كلماتها و تنقص كلما اضاف
المستخدم كلمة الى المفضلة او ازال كلمة اي اي بكل بساطة هي حزمة جديدة يتم ملؤها و تفريغها
من قبل المستخدم عبر اضافة كلمة او ازالة كلمة من اي من الحزمتين المدمجتين حاليا.»

So: a third pack, alongside the 297-word starter pack and the full 31,600-word
dictionary, whose contents **are** the user's favourites across both of them, and which
grows and shrinks as they star and unstar.

**This is the specification for the round that builds it.**

## The hard part, stated first

**The two packs do not live in the same place.**

- The 297-word starter pack is a row set in the **app database** (`packs`, `entries`).
- The full dictionary is a **separate read-only file** (`assets/dictionary/en_ar.db`),
  with its own `entries` and `senses` tables.

**So a favourite is not one thing.** `favorites` is keyed by `(packKey, entryId)`, and
the two packs use different id schemes. A derived pack has to merge favourites from
both sources, and it has to do it without inventing a third place to store them.

**The ruling: the pack is DERIVED, never stored.** It is computed from the favourites
table each time the pack list is read. Nothing is written to a `packs` table for it, so
it cannot drift from the favourites, and it cannot be deleted or imported.

## The id problem, and the ruling that settles it

The derived pack's entries need ids, because a pack's entries are keyed by id
everywhere — progress rows, the quiz, the flashcard deck, the backup.

**The ruling: a namespaced composite, `myfav:<sourcePackKey>:<entryId>`.**

- **Unique.** Two packs may hold the same word; the namespaced ids cannot collide.
- **Stable.** The same favourite produces the same id every time the pack is derived,
  so progress on it survives a rebuild, and the backup can carry it.
- **Honest about its origin.** Reading the id tells you which pack the word came from,
  which is what the user asked for — a favourite in either pack shows up here.

**What it must not be:** a re-hash of the word. A hash would be stable too, but it
would hide which pack the word came from, and it would collide with a real pack's ids
in the `favorites` and `progress` tables, where the key is `(packKey, entryId)` and
`packKey` would be the derived pack's own key — which is a third value nobody
expected.

## The progress of a word, and where it lives

**The ruling: a word in this pack is a view of a word in a real pack, and its
progress lives in the real pack.**

The favourites already work this way — a star toggled through this pack is
written to the row the word really belongs to. An **answer** given about one
of its words is the same thing: it is filed under the pack the word came
from, under that pack's own entry id.

So there is **one word, one record** of what the user did with it:

- the statistics count it **once**, not twice — the accuracy ring, the mastery
  count and the "words practised" figure all read the one record;
- the progress **is in the backup**, because the backup walks the packs and
  the record is filed under one of them. The document's format does not
  change, and no new pack key appears in it;
- this pack's own statistics are the source packs' rows, read for the words
  this pack holds, and **only** those rows. The rows an earlier version of
  the app filed under this pack's own key are duplicates of records that
  already live in the source packs, and reading them would count the word
  twice.

**A reset on this pack clears the progress of its words**, in the packs they
came from — the same rows the statistics read — and its own session history.

**A session — the summary of one quiz — is the exception, and it stays filed
under this pack's key.** A session row carries a pack key and no entry id, so
there is nothing to resolve it to, and a quiz over the favourites may draw
words from either integrated pack. The backup carries the whole session
history, so it travels with everything else.

## The shape of the implementation

1. **A constant** for the derived pack's key, and its title in Arabic — something
   like «مفضلتي». It must be a **reserved key** that no stored pack can claim, so a
   user's imported pack cannot collide with it.
2. **A derivation**, in the repository layer, that:
   - reads every favourite row,
   - resolves each to its `VocabEntry` — from the app database for the stored packs,
     and from the dictionary engine for the dictionary,
   - emits a `VocabEntry` per favourite with the namespaced id,
   - returns an empty list when there are none.
3. **The pack list** — the one the More screen shows and the one the quiz setup screen
   offers — includes the derived pack **only when it has at least one entry**. A pack
   with nothing in it is not a pack.
4. **The pack chooser on the quiz setup screen** lists it, and choosing it makes the
   quiz draw its questions from the favourites.
5. **The favourites themselves** keep working exactly as they do. Starring a word in
   the dictionary adds it to the derived pack; unstarring removes it. **Nothing about
   the existing favourites screen changes** — it is still a list of starred words, and
   the derived pack is a second view of the same truth.

## The open questions, and how to settle them

| | |
|---|---|
| **A dictionary word and a starter-pack word with the same English spelling** | They are two different entries in two different sources. **Both appear**, under their own namespaced ids. Say so in the report. |
| **Which pack is the active one?** | The derived pack must be selectable like any other — and **it must not become the active pack by accident**, because the active pack is what the word of the day and the flashcards draw from. |
| **The word of the day** | It draws from the active pack. With the derived pack active, it would draw a favourite. **That is correct behaviour and it should be said aloud in the report, not discovered later.** |
| **The backup** | Favourites are already exported, keyed by `(packKey, entryId)`. The derived pack adds **no rows to the favourites table**, so **the backup format does not change** — which is what PROMPT.MD's phase five demands. **Prove it: the backup codec's tests must pass untouched.** |
| **The flashcard deck** | Draws from the active pack. With the derived pack active, the deck is the favourites. **That is a feature, not a bug** — but the deck's empty state must handle a pack with one word in it. |

## What must not change

- **The `favorites` table's shape.** No new columns, no new table, no new key.
- **The backup document's format.** Same schema, same version.
- **The database schema version.** It is at 2, and this round does not need a third.
- **The two existing packs.** They behave exactly as they do.

## The test that matters most

**A favourite added to either pack appears in the derived pack, and removing it takes
it out — and the derived pack's ids stay the same across a rebuild.**

That is the whole feature in one assertion, and it is the one thing a reviewer should
check first.
