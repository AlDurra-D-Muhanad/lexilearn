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
