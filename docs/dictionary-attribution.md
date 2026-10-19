# Dictionary attribution — LexiLearn

**Do not invent any of this text.** Every line below was read from the upstream
project's own configuration, not paraphrased from the dictionary's `meta` block.
`meta.attributionFile` points at `C:/Users/user/Desktop/en-ar/ATTRIBUTION`, which
does not exist; it was a stale path from an earlier session, and it is not a source
of truth. The upstream repository is.

## The dictionary

| | |
|---|---|
| **Upstream project** | [`DanielGregorini/koreader-dicts`](https://github.com/DanielGregorini/koreader-dicts) — "Free offline StarDict dictionaries for KOReader" |
| **The pair** | `en-ar` — *"English to Arabic, built by pivoting Princeton WordNet 3.0 through the Arabic WordNet and enriching with the English Wiktionary. Includes an inflection index."* |
| **The file we ship** | `en-ar.dict.dz` + `en-ar.idx` (StarDict 2.4.2, `sametypesequence=h`) |
| **Build** | `koreader-dicts` build 2026-09-11 |

## The three sources, and their licences

Read from `configs/sources.toml` in the upstream repository:

| id | licence | credit (verbatim) |
|---|---|---|
| `pwn30` | `WordNet-3.0` | Princeton University WordNet 3.0 |
| `omw-arb` | `CC-BY-SA-3.0` | Arabic WordNet (AWN v2), via Open Multilingual Wordnet 1.4 |
| `wikt-en-ar` | `CC-BY-SA-4.0` | English Wiktionary via kaikki.org (wiktextract) |

**The upstream's own comment on the `en-ar` pair:**

> Arabic WordNet is CC BY-SA 3.0, which upgrades to 4.0, so it bundles with
> Wiktionary without trouble.

So the shipped work is under **CC-BY-SA-4.0**:
<https://creativecommons.org/licenses/by-sa/4.0/>

**The upstream's licensing rule, which is why none of this is guessed:**

> Licence handling is not optional. An adapter must determine its licence from the
> data, not assume one. […] UNKNOWN is modelled as an excluded licence precisely so
> that guessing is impossible.

## What the attribution screen must show

1. The licence of the shipped work: **CC-BY-SA-4.0**, with its URL.
2. The three sources above, each with its own licence and its verbatim credit string.
3. The upstream project, by name and URL.
4. **The WordNet licence is not CC-BY-SA** — it is `WordNet-3.0`, a separate and
   permissive licence. Do not label Princeton's material as share-alike.

## Where it goes in the app — a ruling, already half-built

**The three-dot menu at the top of every screen** → a row labelled **النسب** with a
balance icon → a screen titled **المصادر والنسب**. It is reached the same way the app
info screen and the Telegram contact are, so the three sit together and the licence
is one tap from where the user looks for "what is this app".

The screen has three sections, in this order:

1. **الترخيص** — the licence of the shipped work, `CC-BY-SA-4.0`, with its URL as a
   link that opens the licence text.
2. **المصادر** — the three sources, each showing **its own licence** and its
   **verbatim credit string**. The three licences differ, and collapsing them into
   one share-alive line would misstate two of them.
3. **الأرقام** — what the dictionary actually contains: entries, senses, senses with
   an Arabic translation, examples, entries with an IPA transcription, and the number
   of Arabic search keys.

## The correction this ruling requires

`lib/ui/dictionary/attribution_screen.dart` exists and reads the dictionary's `meta`
table. **That is the thing to change.** `meta` carries the stale `attributionFile`
path, names the build rather than the project, and reduces three different licences
to one.

**The fix belongs in the build tool, not in the screen.** The build writes the
verified strings above into the database's `meta` table at build time — the upstream
project and its URL, the three sources with their own licences and their verbatim
credits — and the screen keeps reading the table it already reads. The screen's shape
does not change; the data under it stops being the summary and becomes the record.

**`attributionFile` must be dropped, not rendered.** It points at a path that does not
exist, and the user has confirmed it is a stale path from an earlier session.

## A note on the `meta` block

The `meta` block inside `en-ar-dictionary.json` carries the same licence and the same
three source ids, and it agrees with the upstream. It is a **summary**, not the
attribution. Use the strings above.

## Also worth knowing

`freq/en_50k.txt` — OpenSubtitles 2018 English top 50k, from
[`hermitdave/FrequencyWords`](https://github.com/hermitdave/FrequencyWords),
`CC-BY-SA-4.0` — is a **benchmark input in the upstream build, and is not shipped in
the dictionary**. It is mentioned here only because the upstream's `en-ar` config
names it under `[benchmark]`, and because it is the frequency signal available
upstream if a frequency-ordered study list is ever wanted.
