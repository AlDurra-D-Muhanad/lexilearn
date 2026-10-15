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
renders through it. Tajawal has no usable Latin coverage, so a Latin run that
does not explicitly ask for Inter falls back to the system font and stops
matching the brand. Latin runs therefore always set `AppText.latin` or
`AppText.latinDisplay`, which is where `Inter` is named.

## Component style
Surfaces are rounded and separated by a **soft shadow** in light mode, and by a
1px `#334155` hairline in dark mode where a shadow is invisible. The brand's
light shadow is exactly `0 4px 12px rgba(0,0,0,0.05)`, exposed as
`AppShadows.light`; `AppShadows.none` is the dark-mode value. Pill shapes are
used for tags, synonyms, and the search field; 16px radii (`AppRadii.md`) for
cards and inputs.

## Navigation
**Four** bottom destinations, matching the artwork: الرئيسية (Home),
بطاقات (Flashcards), الاختبارات (Quizzes), المزيد (More). The active
destination is primary purple; inactive ones are secondary grey. Favourites is
deliberately *not* a tab — the artwork reaches it from the heart action on the
word card, and that is where it stays.

## Fonts on disk
`assets/fonts/` carries the four static instances the app actually uses:

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
   turns light-mode elevation on so the brand's soft shadow actually renders.
3. **Inter packaging.** The plan's pubspec snippet named
   `Inter-Regular.ttf` / `Inter-SemiBold.ttf` while the file staged in the repo
   was the *variable* `Inter-Variable.ttf`. A variable font ignores
   `fontWeight` in Flutter, so the plan's declaration would have rendered
   English at one weight forever while claiming two. Static instances were
   fetched instead; see the commit for this task.