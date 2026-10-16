# LexiLearn — Style Direction

**Authority:** `docs/design/brand-reference.md` and `docs/design/brand-reference.png`
are the source of truth. This file records the decisions taken *about* that brand
where the plan had to choose, and the explicit exclusions.

Where this file and the brand files disagree, the brand files win and the
difference is recorded in **Amendments** at the bottom.

## Identity
- Wordmark: **LexiLearn**, set in a geometric sans, preceded by an open-book mark
  in the accent amber `#F59E0B`.
- Tagline: **Learn · Practice · Grow**, shown under the wordmark and in the footer.
- The brand markdown still says "Memorize app" in places; that is the older
  working title. The artwork's wordmark is **LexiLearn** and that is what ships.
- App is **Arabic-first RTL**. English appears only as the vocabulary term being
  asked about, and is always rendered explicitly `TextDirection.ltr`.
- Chrome strings come from the brand verbatim, for example the search placeholder
  `ابحث عن كلمة...` and the footer line `تعلم اليوم ... واصنع غداً أفضل`.

## Mood
Warm and studious, not clinical. Purple carries the interface, amber carries
achievement. Calm surfaces, generous spacing, no motion for its own sake.

## Colour strategy
Two hues, fixed by the brand and not negotiable: purple `#885CF6` (light) /
`#A78BFA` (dark) for primary and active states, amber `#F59E0B` for the book
mark, the "I know it" action, and achievement accents. Amber is never used for
text on a light background — its contrast ratio fails there; it is used for
icons, fills, and dark-mode buttons only.

Support colours come from the brand's "System UI Helper Tokens": success
`#16A34A` / `#4ADE80`, error `#DC2626` / `#F87171`, border `#E5E7EB` /
`#334155`. All seventeen are pinned by hex in `lib/design/design_tokens.dart`
and pinned again by test, because a test failing on a colour is the only thing
that stops silent brand drift.

## Typography
Tajawal for all Arabic, Inter for all Latin and numerals. Bundled, never fetched.
A word being *asked about* is the largest text on its screen; its translation is
one step smaller and set RTL.

The app binds `fontFamily: 'Tajawal'` globally because every Arabic string
renders through it. Latin runs therefore always set `AppText.latin` or
`AppText.latinDisplay`, which is where `Inter` is named. Tajawal is not
*missing* Latin glyphs — its `cmap` maps 95 printable ASCII codepoints, including
`A`, `a`, `0` and `e` — but those glyphs are not the brand's Latin. Letting an
English term inherit the ambient family would set it in Tajawal's own Latin at
Tajawal's weights, which reads as an accident rather than a decision. Naming
Inter keeps every English word on one face and one type scale.

## Component style
Surfaces are rounded and separated by a **soft shadow** in light mode, and by a
1px `#334155` hairline in dark mode where a shadow is invisible. The brand's
light shadow is exactly `0 4px 12px rgba(0,0,0,0.05)`, exposed as
`AppShadows.light`; `AppShadows.none` is the dark-mode value. Pill shapes are
used for tags, synonyms, and the search field; 16px radii (`AppRadii.md`) for
cards and inputs.

A surface is built with **`AppSurface`**, not a bare `Card`. Buttons are built
with `elevation: 0` for the same reason (Amendment 5): Material's elevation
shadow is the single largest source of phantom black in a rasterised screen.

Because the golden is the template every screen task copies from, its PNG is
verified by **pixel census, not by eye**. A thumbnail hides a 3px keyline
perfectly. The check that caught this task's two defects:

```powershell
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile("$PWD\test\goldens\goldens\home_shell_user_shot.png")
$bmp.GetPixel(48, 1400).ToString("X2")   # outside a card border  -> F8F7F5, never 000000
$bmp.Dispose()
```

Two exact-colour counts are the pass condition: `#000000` must be **0** pixels,
and `#1D1B20` must be **0** pixels while `#1F2937` is present.

### The golden is a live regression surface, and this is its guard

`test/goldens/golden_test.dart` **has** to stay skipped. Golden bytes depend on
the platform's font rasteriser — Windows uses Segoe UI, Linux CI uses Roboto — so
a byte-identical match across the two is impossible by construction. That skip has
a cost, and it is worth being explicit about it: since Task 10 the golden renders
the **real `LexiLearnApp`**, not a local stand-in. So every change to the bottom
bar, the header, the search field or the theme silently invalidates the committed
PNG, and the skipped test will not say so.

So the census is a script, and it is run by hand whenever a screen task changes
anything a pixel would notice:

```powershell
powershell -ExecutionPolicy Bypass -File tool\golden_census.ps1
```

It reads the committed PNG, asserts the pass condition above, prints the brand
token table, and reports the darkest pixel in the image — a stronger statement
than the two exact counts, because if the darkest pixel is the brand ink there is
no near-black hiding either. It reads committed pixels and regenerates nothing;
regenerating is the test's job, on purpose, by commenting out its `skip:` line and
running with `--update-goldens`.

A live regression surface with a guard nobody runs is the same as no guard. Run
it.

## Navigation
**Four** bottom destinations, matching the artwork: الرئيسية (Home),
البطاقات (Flashcards), الاختبارات (Quizzes), المزيد (More). The active
destination is primary purple; inactive ones are secondary grey. Favourites is
deliberately *not* a tab — the artwork reaches it from the heart action on the
word card, and that is where it stays.

### Where المفضلة is reached from
**Favourites was not cut.** It is a shipped feature and has exactly the two
doors the artwork draws:

1. **A tile in Home's 2×2 quick-launch grid**, labelled `المفضلة`, beside
   `بطاقات التعلم` / `الاختبارات` / `إحصائياتك`. This grid is on the Home
   phone in the artwork, directly under the word-of-the-day card. Task 10
   builds it and Task 14 fills in `FavoritesScreen`, pushed with
   `Navigator.push` from that tile.
2. **The heart action on the word card / word detail screen.** Task 14 adds
   `WordDetailScreen` and pushes `FavoritesScreen` from its heart button.

`FavoritesScreen` exists at `lib/ui/favorites/favorites_screen.dart`. It is
simply not a `NavigationDestination`, which is why
`lib/ui/home_shell.dart` does not import it. **Reading the four tabs above as
"favourites was cut" is a misreading** — see Amendment 1, which records the
five-destination draft being corrected back to four, and Amendment 7 for the
icons these four carry.

## Fonts on disk
`assets/fonts/` carries the five static instances the app actually uses:

| Family | File | Declared weight |
|---|---|---|
| Tajawal | `Tajawal-Regular.ttf` | 400 |
| Tajawal | `Tajawal-Medium.ttf` | 500 |
| Tajawal | `Tajawal-Bold.ttf` | 700 |
| Inter | `Inter-Regular.ttf` | 400 |
| Inter | `Inter-SemiBold.ttf` | 600 |

All are **static** instances — no `fvar` table — so `fontWeight` really does
change the rendered weight. `AppText.latinDisplay` uses `FontWeight.w600`, which
resolves to `Inter-SemiBold.ttf`.

Both families are under the SIL Open Font License; both notices are carried in
`assets/fonts/OFL.txt`. `google_fonts` is deliberately not a dependency: it would
make the app phone home on first run and break the offline guarantee this project
depends on.

## Motion
Two durations, both from `AppDurations`: `fast` 150 ms and `standard` 250 ms.
`standard` is used by `AppSurface`, which cross-fades a surface's fill, hairline
and shadow when the app switches between light and dark, so a theme change reads
as one movement instead of a snap. `fast` is **reserved for the screen tasks**
that follow: the flashcard flip and answer reveal (Task 11), quiz option and
result transitions (Task 12), the favourite heart toggle and stat counter
(Tasks 13 and 14), and bottom-navigation tab changes (Task 9). Motion is never
decorative here — if a screen has nothing to reveal, it does not animate.

## Explicitly excluded, by user decision
- **No text-to-speech.** The artwork's speaker icon and the `/səˈrenəti/`
  pronunciation row are implemented as **static text only**, never played. Any
  future audio work must not break the offline, no-network guarantee.
- **No gradients**, despite the artwork's photo cards. The cards use a solid
  surface; photography is out of scope for an app with no image pipeline.

## Amendments
Differences between this task's plan text and the brand files, resolved in the
brand's favour:

1. **Navigation count.** The plan's draft of this file said "five bottom
   destinations: Home, Flashcards, Quizzes, Favourites, More". The artwork shows
   **four** — there is no favourites tab, and the plan's own next task is titled
   "App shell and four-tab navigation". Corrected above.
2. **Card separation.** The plan described surfaces as "separated by a soft
   shadow, **not** an outline", while the theme it then specifies sets
   `elevation: 0` and a 1px border side. The brand says both: "حدود ناعمة وظل
   خفيف" — soft borders *and* a light shadow. The theme keeps the hairline (it
   is what carries separation in dark mode, and the pinned test asserts it) and
   composes the brand shadow where the surface is built — see
   `AppSurface` in `lib/ui/theme/app_surface.dart`.
3. **Inter packaging.** The plan's pubspec snippet named
   `Inter-Regular.ttf` / `Inter-SemiBold.ttf` while the file staged in the repo
   was the *variable* `Inter-Variable.ttf`. A variable font ignores
   `fontWeight` in Flutter, so the plan's declaration would have rendered
   English at one weight forever while claiming two. Static instances were
   fetched instead; see the commit for this task.
4. **The colour scheme is not the brand palette.** The plan built both themes
   from `ColorScheme.fromSeed(seedColor: …)` and took the result as the brand's
   colours. It is not one: seeding with `#885CF6` produces a `primary` of
   `#65558F`, a dusty plum, and an `onSurface` of `#1D1B20` against the brand's
   `#1F2937`. Every screen that reads `colorScheme.primary` or
   `textTheme.bodyMedium` was rendering Material's tonal guess. The seed is now
   kept only for the roles it gets right, and every brand-pinned role is written
   over it in `AppTheme._schemeFor`.
5. **Where the shadow lives.** The plan wanted the theme to carry the shadow.
   `CardThemeData` has no shadow field — only `clipBehavior`, `color`,
   `shadowColor`, `surfaceTintColor`, `elevation`, `margin` and `shape` — so no
   theme can. `CardTheme.elevation` therefore stays at `0`, and `AppSurface`
   composes the brand shadow where surfaces are actually drawn. Material's own
   elevation shadow is not a stand-in: it is roughly four times the brand's
   umbra alpha, geometrically unrelated, and the test rasteriser strokes it as
   an opaque black keyline rather than a falloff.

   `surfaceTintColor` is listed there only to show what the type *has*. It is
   not a shadow control: it tints the **surface** by the primary colour at
   elevated elevation. It has nothing to do with shadow colour, which is what
   `shadowColor` and `modelShadowColor` set — and `material.dart` hardwires
   `modelShadowColor` to `colorScheme.shadow`.
6. **Buttons have the same defect, and the golden had it.** Fixing
   `cardTheme.elevation` removed **29,111** black pixels but left **2,363** of
   them — a 3px opaque `#000000` ring around the amber "معرفة المعنى" button,
   because `elevatedButtonTheme` still defaults to M3 elevation 1. The button
   now sets `elevation: 0` and the census is zero. The golden preview's grid
   tiles were switched from `Card` to `AppSurface` at the same time, so the
   file the screen tasks copy shows the pattern that actually works.
7. **The bar's icons are the artwork's, verified against the PNG.** The
   artwork's own bottom bar draws `الرئيسية` as a house (filled while active),
   `البطاقات` as two overlapping rounded cards, `الاختبارات` as a rounded
   square with a checkmark breaking out through its top-right corner, and
   `المزيد` as a *cluster* of marks on a 3×3 lattice. Measured by rasterising
   the Material glyphs out of `materialicons-regular.otf` and comparing mask
   overlap with the artwork, per destination:

   | Destination | Icon | Evidence |
   |---|---|---|
   | `الرئيسية` | `home_outlined` / `home` | Filled-while-active house is exactly this pair. |
   | `البطاقات` | `style_outlined` / `style` | Two overlapping rounded cards, back one offset up-right. |
   | `الاختبارات` | `check_box_outlined` / `check_box` | 25.1% mean pixel IoU, against 20.6% for the `checklist_rtl` family and 11.6% for `checklist_rtl` itself. The artwork has no text lines and no second row, which is what the checklist glyph is made of. |
   | `المزيد` | `apps` | `apps` is the only candidate that places a mark at **every** position either phone draws — 5 of 5 on the light phone, 7 of 7 on the dark one — on the same 3×3 lattice at the same relative pitch. `more_horiz` reaches 3 of 5 and 3 of 7; `blur_on`, the only other dot-shaped candidate, is a 24-dot bokeh cluster at five times the density; `grid_view` is 2×2. |

   The one residual difference is that `apps` draws each mark as a small filled
   square where the artwork's is round. At the artwork's own bar-icon render
   size — the marks are about two source pixels across — the two are not
   distinguishable, so the lattice and pitch were treated as the thing that
   actually identifies the glyph. `apps_outlined` ties `apps` on mark
   positions and loses on fill: the artwork's marks are solid, not rings.

   `test/ui/home_shell_test.dart` pins all four, so a later icon change is a
   test failure rather than silent drift.
8. **Home's 2×2 grid is in reading order, which transposes it against the
   artwork.** The mock draws `الاختبارات` top-right and `بطاقات التعلم`
   top-left, with `إحصائياتك` and `المفضلة` the other way round on the second
   row. Reproducing that arrangement would mean fighting the directional
   `GridView`, which places its first child at the RTL *start* — and what the
   mock shows is a left-to-right grid of Arabic labels, which is what a designer
   draws in Figma and not what an Arabic screen reads as. So the children are in
   reading order, top-right first: `بطاقات التعلم`, `الاختبارات`, `المفضلة`,
   `إحصائياتك` — the order the brand reference names the tiles in. **Both rows
   are transposed relative to the mock. Do not "fix" this by reordering the
   children to match the PNG**; that would break reading order to imitate a
   mock's own layout mistake.
9. **The search field's magnifier sits at the RTL start, not the end.** The
   artwork draws it at the right-hand end of the field, which is the *end* in
   RTL, and the placeholder at the start. Material's `InputDecoration` places
   `prefixIcon` at the start, so the app's field reads opposite to the mock. The
   Material convention wins, because the artwork's other left-to-right tell — the
   header's greeting pushed to the left — was resolved the same way, and because
   a magnifier is a control rather than prose: it belongs where the app puts
   every other control's leading edge. Recorded so a later task does not read the
   PNG and "correct" it.
