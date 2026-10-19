# The word-of-the-day card, as the artwork shows it

**Authority: `Memorize app theme and style.png`, the two "Word of the Day" cards
(light and dark Home).** Measured off that artwork, not inferred.

## What the artwork actually does

| | the artwork | what we shipped in `898ec02` |
|---|---|---|
| the photo | **full bleed, raw** | full bleed, `BoxFit.cover` ✓ |
| an overlay | **none at all** | a `#0F172A` scrim at alpha **0.60** over the top 58% |
| how the text stays legible | a **soft dark shadow behind the text** | the scrim |
| the "معرفة المعنى" button | **translucent dark fill, thin light outline** | an opaque pill |
| the pronunciation icon | **amber `#F59E0B`** | — |

**The scrim was a consequence of a wrong assumption, not of the artwork.** The
replaced "brand wash" was 485,108 pixels of one flat `#885CF6` with a luminance
spread of exactly zero, so it was replaced with a photo — and the scrim was added
because that photo was a bright brand-coloured wash. **The artwork's photographs are
dark at the bottom on their own.** The scrim compressed the photograph to roughly a
tenth of its contrast inside the text band, which is the thing the change was meant
to stop.

## The rulings

1. **Remove the 0.60 scrim.** The artwork has no overlay.
2. **Use the artwork's own mechanism for legibility: a text shadow** behind the word,
   the label and the phonetic — a `TextShadow`, not a layer over the photograph.
3. **Measure, do not assume.** Compute the WCAG ratio of the white ink against
   **every one of the fourteen photographs** with the shadow in place.
   - If all fourteen pass, ship it with no overlay at all.
   - If any fail, add **the least bottom-up gradient that fixes it**, and report
     which photographs failed, the ratio before and after, and the alpha used.
   - **The user's choice, given the two options: a GRADIENT that dims the bottom
     gradually, not a hard scrim.** A scrim cuts a band off the picture; a gradient
     lets it go dark toward the edge. So the gradient is the shape, and the
     measurement is what fixes its strength and where it starts.
   - **Both forms are to be measured and reported** — the gradient's alpha at its
     strongest, where it begins, and the worst WCAG ratio per photograph, so the
     numbers are there to judge rather than a taste.
4. **The button is a translucent dark fill with a thin light outline**, as in the
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
against all fourteen photographs, and the smallest deviation that makes them all
legible is reported rather than assumed.

**Faithfulness is the instruction; legibility on the user's own files is the
constraint; the gradient, if any, is the measured minimum that satisfies both.**

## The measurement, taken over the user's own fourteen photographs

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

**The label is the exception, and the artwork is the reason.** In the artwork the
"Word of the Day" label is white on a *pale* sky — `#D5E1E3` — and it is legible
only because of its text shadow. **A text shadow does not raise the WCAG ratio of
the glyph's interior**; it softens the edge. So the artwork itself accepts a
sub-AA ratio for that one small label, and this implementation should do the same
and say so.
