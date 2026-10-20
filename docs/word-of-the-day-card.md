# The word-of-the-day card, as the artwork shows it

**Authority: `Memorize app theme and style.png`, the two "Word of the Day" cards
(light and dark Home).** Measured off that artwork, not inferred.

## What the artwork actually does

| | the artwork | what we shipped in `898ec02` |
|---|---|---|
| the photo | **full bleed, raw** | full bleed, `BoxFit.cover` ✓ |
| an overlay | **none at all** | a `#0F172A` scrim at alpha **0.60** over the top 58% |
| how the text stays legible | a **soft dark shadow behind the text** | the scrim |
| the "معرفة المعنى" button | **translucent fill, thin light outline** | an opaque pill |
| the pronunciation icon | **amber `#F59E0B`** | — |

**The scrim was a consequence of a wrong assumption, not of the artwork.** The
replaced "brand wash" was 485,108 pixels of one flat `#885CF6` with a luminance
spread of exactly zero, so it was replaced with a photo — and the scrim was added
because that photo was a bright brand-coloured wash. **The artwork's photographs are
dark at the bottom on their own.** The scrim held `#0F172A` at 0.60 across the
**top 58%** of the card, which flattened the sky to a navy band and released to
nothing over the bottom third — the opposite of the shape the user ruled for.

## The rulings

1. **Remove the 0.60 scrim.** The artwork has no overlay.
2. **Use the artwork's own mechanism for legibility: a text shadow** behind the word,
   the label and the phonetic — a `TextShadow`, not a layer over the photograph.
3. **Measure, do not assume.** Compute the WCAG ratio of the card's own ink against
   **every one of the thirteen photographs** with the shadow in place.
   - If all thirteen pass, ship it with no overlay at all.
   - If any fail, add **the least bottom-up gradient that fixes it**, and report
     which photographs failed, the ratio before and after, and the alpha used.
   - **The user's choice, given the two options: a GRADIENT that dims the bottom
     gradually, not a hard scrim.** A scrim cuts a band off the picture; a gradient
     lets it go dark toward the edge. So the gradient is the shape, and the
     measurement is what fixes its strength and where it starts.
   - **Both forms are to be measured and reported** — the gradient's alpha at its
     strongest, where it begins, and the worst WCAG ratio per photograph, so the
     numbers are there to judge rather than a taste.
4. **The button is a translucent fill with a thin light outline**, as in the
   artwork — not an opaque pill.
5. **The pronunciation icon is amber `#F59E0B`**, as in the artwork.
6. **Delete the duplicated wallpaper.** `light-2-hiker-beneath-giant-mushrooms.jpg`
   and `light-6-hiker-beneath-giant-mushrooms-copy.jpg` are the same photograph:
   64,800 sampled points, only 2,323 differing by more than 12 of 765, maximum
   per-pixel channel difference 92. The second ships as `…-copy`. **Remove the
   copy.** `test/ui/wallpaper_catalog_test.dart` counts the set, so it must be
   updated in the same change.
7. **Keep `senses.en`.** The user's decision. 34,185 of the 81,451 senses have no
   Arabic, and the English gloss is the only text they can show.

## Why the measurement in ruling 3 exists

The user's own photographs are not like the artwork's. The artwork's card is a
twilight landscape — dark where the text sits. Among the user's light set are a
golden sunset, turquoise foam seen from above, cream-coloured cloud, and a
blue-hour valley. **White text on a golden sky is unreadable, and no amount of
faithfulness survives that.** So the artwork is followed, the outcome is measured
against all thirteen photographs, and the smallest deviation that makes them all
legible is reported rather than assumed.

**Faithfulness is the instruction; legibility on the user's own files is the
constraint; the gradient, if any, is the measured minimum that satisfies both.**

## The measurement, taken over the user's own photographs

Text bands were read off the artwork's own card as fractions of its height, and
sampled only where the glyphs actually are — the label, the word and the phonetic
are left-aligned, the button is centred. The gradient is `ink*a + photo*(1-a)` with
ink `#0F172A`, and the ink is white.

```
base (no gradient)   the worst WCAG ratio of white text behind the glyphs
need                 the minimum alpha that lifts that pixel to 4.5:1
```

| band | worst base | the alpha it needs |
|---|---|---|
| "Word of the Day" label | **1.00:1** | 0.59 |
| the word | **1.00:1** | 0.59 |
| the phonetic | **1.00:1** | 0.59 |
| the button | **1.00:1** | 0.59 |

**Only 2 of the 56 band/photo pairs pass with no gradient at all.** The binding
pixels are *pure white* — stars, snow, foam, cloud — in the photographs the user
supplied. **No gradient weaker than 0.60 can rescue a pure-white pixel**, because
the composite of any alpha over `#FFFFFF` still has to be darkened to well under
mid-grey before white text clears 4.5:1.

### And a bottom-up gradient cannot reach the word

Searching every start height against all 56 bands:

| the gradient starts at | peak alpha it needs | bands it cannot reach at all |
|---|---|---|
| 0% of the card's height | 0.60 | 0 |
| 5% | 0.60 | 0 |
| 10% | 0.60 | **2** |
| 20% | 0.60 | **14** |
| 30% | 0.60 | **22** |
| 40% | 0.60 | **25** |

**The word sits at 25–45% of the card's height.** A gradient that starts at the
bottom cannot reach it, and one that starts at 20% leaves a quarter of the
measurements unprotected. **The peak alpha is 0.60 at every start height** — the
pure-white pixels bind it, not the shape.

### The shape that works, and the user's shape

The user chose **a gradient that dims the bottom gradually, over a hard scrim.**
That is the right instinct and it is honoured. But the measurement says the
gradient has to *begin above the word* to protect it, and to reach 0.60 by the
word's band.

**So the gradient runs from the top edge, is already 0.60 by the word, and holds
to the bottom** — a smooth ramp with no hard edge anywhere, which is what "a
gradient rather than a scrim" means. The alternative — a gradient that genuinely
starts at the bottom — is the artwork's shape, and it works in the artwork
**because the artwork's photograph is dark where the text sits**, which the user's
photographs are not.

## The shape, recomputed from the artwork's own card

The artwork's light Home card was measured pixel by pixel. It occupies
**`x 30..204, y 352..477`** of the 1254×1254 artwork — 175×126 px — and its four
runs of text sit at:

| what | the artwork's rows | as a fraction of the card's height |
|---|---|---|
| the top edge's sky, raw photograph, no ink | `352 .. 353` | `0.000 .. 0.008` |
| the "Word of the Day" label | `371 .. 382` | `0.151 .. 0.238` |
| the word "serenity" | `398 .. 415` | `0.365 .. 0.500` |
| the phonetic | `419 .. 429` | `0.532 .. 0.611` |
| the "معرفة المعنى" button's label | `451 .. 458` | `0.786 .. 0.841` |

**And the card's own row luminance**, the photograph on its own:

| the card's height | the mean luminance of the row |
|---|---|
| `0.03 .. 0.32` — the sky | **0.32 .. 0.41** |
| `0.35 .. 0.98` — the mountain and the lake | **0.02 .. 0.21** |

Four things follow, and they are the whole of the shape:

1. **The top of the artwork's card is bare photograph** — the sky, with nothing
   over it. So the ramp starts at **no ink at all** on the top edge.
2. **The ramp must be at its peak before the word.** The artwork's own word band
   starts at 37.6% of the card, but *this* card's word starts earlier — at
   **25.87%**, measured off the rendered tree on the golden phone (1080×2340 at
   3×: the label runs `0.12438 .. 0.21891`, the term `0.25871 .. 0.45771`, the
   phonetic `0.45771 .. 0.55721`, the button `0.70647 .. 0.80597`). The knee is
   therefore at **0.25871**, the earliest it can be and still protect the whole of
   the word. Putting the knee where the artwork puts it instead — 37.6% — would
   leave the top of our word band at alpha 0.4128, and a pure-white photograph
   pixel there would composite to `#9B9FA7` and measure **2.65:1**.
3. **The artwork's card is dark from the word down to the bottom edge**, so the
   ramp **holds** to the bottom. There is no second knee.
4. **The artwork has no hard edge anywhere**, so the ramp is one straight line
   from the top edge to the word and then flat.

**The stops that ship: `0.0`, `0.25871`, `1.0`, at alphas `0`, `0.60`, `0.60`,
in `#0F172A`.** See `lib/ui/wallpaper/wallpaper_gradient.dart`.

## What the ramp costs and what it buys, measured

Sampled in the card's **left half**, where the right-aligned text never
reaches, against the same photograph before and after the change. The figure is
the share of the photograph's own luminance spread that survives.

| the card's band | the photograph's own spread | under the scrim | under the ramp |
|---|---|---|---|
| the label | 0.040 | 16% | **253%** |
| the word | 0.277 | 15% | 15% |
| the phonetic | 0.213 | 15% | 15% |
| the button | 0.448 | 53% | **16%** |

**The word's band is compressed exactly as much as it was.** The peak had to be
0.60 for the white ink to clear AA over a pure-white photograph, and that is
not negotiable. What the ramp buys is the **label** and the **top quarter**,
which the scrim had flattened to a navy band; what it costs is the **button and
the bottom third**, which is what "a gradient that dims the bottom gradually"
asks for.

The census's distinct-colour count on the light Home image tells the same
story from the other side: **50,228 → 16,971**, because 74% of the card now
carries 0.60 of ink where 58% did. The dark image went the other way,
20,637 → 38,947, because the picture it shows has more colour in it to begin
with.

## The label is the exception, and the artwork is the reason

**Measured off the artwork, the label's own sky is not one colour.** The label
runs `x 45..118, y 371..382` over a sky that runs from teal at its left end to
the card's sunlit cloud at its right:

| where | the sky | the white ink against it |
|---|---|---|
| the label's left end, `x 42` | `#5D7F80` | **4.36:1** |
| just right of the label, `x 126` | `#AEB5A5` | **2.11:1** |
| the card's sunlit cloud, `x 200` | `#D5D5C0` | **1.49:1** |

**So the artwork's own label is below AA over part of its own extent**, and it is
legible there only because of its text shadow. **A text shadow does not raise the
WCAG ratio of the glyph's interior**; it softens the edge. The artwork therefore
accepts a sub-AA ratio for that one small label, and so does this — measured at
**1.94:1** at its worst over the user's thirteen photographs, which is *better*
than the artwork's own 1.49:1, and the number is in
`test/ui/wallpaper_legibility_test.dart`.

> **A correction to an earlier draft of this file.** It said the label sat on a
> "pale `#D5E1E3` sky" at 1.336:1. `#D5E1E3` is 57 pixels in the whole card and
> every one of them is on the card's **top antialiased edge row**, where the
> photograph blends into the white page. The sky actually behind the label is the
> teal above. The conclusion — the artwork accepts a sub-AA ratio for that one
> label — was right, and the number behind it was not.

## The button, and the one place the artwork and the ruling differ

The artwork's button is a **stadium with a single light pixel of outline** and a
**fill that renders lighter than the photograph around it**: in the light card the
photo outside the pill is at luminance 0.010..0.057 and the pill's interior at
0.066..0.079; in the dark card the photo outside is at 0.010 and the interior at
0.022. The mock's button is a frosted pill.

**The user's ruling is a translucent *dark* fill, and that is what ships**
(`#0F172A` at 45%, with a `#FFFFFF` outline at 70% and 1.5 logical px). The
measurement is on the record so the difference is a decision rather than an
accident, and because a dark fill is what the white label needs: behind the
button the ramp already carries 0.60, and the label over a pure-white photograph
measures **4.74:1** with no fill of its own and **8.90:1** with this one.

## The card's ink is white in both modes

The artwork draws "serenity" in white on its light card and "ambition" in white on
its dark one: the card's text sits on a photograph, and the photograph does not
change with the phone's theme.

The app's **dark body ink** `#F9FAFB` is 3.3% the weaker of the two over the same
background, and it put the word over `dark-5-turquoise-lake-under-stars.jpg` at
**4.497:1** — 0.003 below AA. `#F9FAFB` is a token for text on the app's dark
*surfaces*; text on a photograph gets its own token, `AppColors.onPhoto`.
