# The new identity — navy and gold

**Authority: `C:\Users\user\Desktop\lexilearn notes\new theme.png`, sampled pixel by pixel.**
The user replaced the purple primary with a gold one. This file is the single
authority for that change, so that every round reads the same numbers.

## The measured palette

Sampled off the reference at named points, not read by eye:

| role | measured | note |
|---|---|---|
| page background | **`#020E24`** | deep navy; `#010D24` at the very bottom |
| surface | **`#0E2344`** | the search field's fill, the tiles' fill |
| surface, second | **`#071937`** | the card's interior |
| border | **`#061836`** | sampled where the blue border meets the background |
| bottom bar | **`#06142C`** | |
| icon badge | **`#0C1E38`** | the circle behind a tile's icon |
| **primary (gold)** | **`#F3AC43`** | the button fill; the median over the whole button is `#F3AD42`, the brightest pixel `#FFD35F` |
| text | **`#FFFFFF`** | and `#FDFDFD` for the title |

**The gold's luminance is 0.4934, so on the navy background it measures
**9.50 : 1**.** That is not a decoration colour — it can carry text.

## The rules that follow from the reference

1. **The gold is a FILL, and the ink on it is dark.** The reference's "معرفة المعنى"
   button is a solid gold pill with near-black lettering. **So the gold is never
   used as a text colour on a dark surface, and never as text on a light surface
   either** — it is a fill, and the text on it is the darkest ink in the app.
2. **The gold is the accent everywhere the reference puts it**: the primary
   button, the active bottom-bar item and its label, the tile icons, the
   pronunciation speaker, the star beside "Word of the Day", the chevron on a
   tile, and the book mark.
3. **The blue is structure, not accent** — borders, the pack chip's outline, the
   search field's outline. It is a *quiet* blue; it must not compete with the gold.
4. **The word-of-the-day card KEEPS ITS SHAPE.** The reference image shows a split
   card — photograph on one side, text on the other — **and the user has refused
   it**: «بطاقة اليوم ليست نصفان ابقها كما هي ابق التدرج و الظل». So:
   - **the photograph stays full-bleed**, filling the card edge to edge;
   - **the gradient stays** — the bottom-up ramp, `WallpaperGradient`, which the
     last round measured and whose peak alpha is 0.60;
   - **the text shadow stays** — `AppShadows.onPhoto`, the artwork's own mechanism
     for legibility;
   - **the text still sits on the photograph**, and the legibility numbers from
     `docs/word-of-the-day-card.md` still hold and still need to hold.
   **Only the colours change on this card: the gold icon, the gold button, the
   border. Its structure does not.**
5. **The four tiles gain a circular badge** around the icon, and a chevron on the
   trailing side, as the reference shows.
6. **The active bottom-bar item is a gold pill** with a gold icon and a gold
   label.

## Light mode

The reference is a dark design and does not say what light mode should be. Light
mode is not optional — the app offers `ThemeMode.system` and the user is entitled
to it — so:

- **the light palette is the same system inverted**: the light background stays
  `#F8F7F5` and the surface `#FFFFFF`, the ink stays `#1F2937`, and **the primary
  becomes the same gold** — used as a fill with the same dark ink on it, never as
  text.
- **the gold is measured for both modes.** On `#F8F7F5` the gold `#F3AC43` is
  about 1.9 : 1 as a text colour, **which is why rule 1 exists**: it is a fill
  with dark ink, and the ink on it must clear 4.5 : 1 in both modes. **Measure it
  and put the numbers in the report.**

## What this costs

**Every one of the 31 goldens changes.** That is expected and is not a reason to
hesitate — the census exists to check the new images against their baselines, and
the baselines are re-measured from the new PNGs.

**What must not change:** the dictionary, the search logic, the database, the
backups, the offline guarantee, and the app's behaviour. This is a colour and
layout change, not a behaviour change.
