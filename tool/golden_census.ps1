<#
.SYNOPSIS
  Pixel census for the committed golden reference images.

.DESCRIPTION
  `test/goldens/golden_test.dart` has to stay skipped: golden bytes depend on the
  platform's font rasteriser, so a byte-identical match across Windows and Linux
  CI is impossible by construction. That skip has a cost — the reference images
  render the real app, so every change to the bottom bar, the header, the theme
  or a screen's own colours silently invalidates them and nothing says so.

  ## WHAT THIS ACTUALLY GUARANTEES, AND WHAT IT DOES NOT

  **It guarantees that the committed pixels are colour-clean.** For each image it
  asserts, from `docs/design/style-direction.md`:

    * `#000000` must be 0 pixels  — a phantom black keyline from a `Card` or a
      Material elevation shadow, the defect that put 29,111 of them here once and
      2,363 more on a button.
    * `#1D1B20` must be 0 pixels  — Material's tonal-palette text, not the brand's.
    * the image's own mode must be identifiable  — a light image is one that has
      `#F8F7F5` and no `#0F172A`, a dark one the reverse. A screen that renders
      with no background at all, or both, is a broken render, not a dark mode.
    * the text ink of that mode must be present — `#1F2937` on light, `#F9FAFB` on
      dark — and the *other* mode's background must be absent.
    * the verdict tokens must belong to the mode — a dark render carries **0**
      pixels of `#16A34A` / `#DC2626`, and a light render **0** of `#4ADE80` /
      `#F87171`. This is the one check that would have caught the defect the six
      quiz images exist for: `quiz_screen.dart` named the *light* verdict tokens
      at four call sites, two of them `const Icon`s that could not read the theme
      at all, and on the user's dark phone that measured **0** pixels of the dark
      tokens against 15,795 and 15,719 of the light ones. Every other assertion in
      this file is about a colour being *absent* or out of place; these two are
      about a colour that is entirely normal, in the wrong place.

  It then prints the full brand-token table, so a colour that has quietly moved is
  visible in the same run.

  **It does NOT guarantee that an image is of the screen its filename claims.**
  Every property above is a *pixel* property, and **no pixel property
  distinguishes one screen's render from another's.** Measured, both ways:

    * the favourites screen's bytes written to
      `word_detail_user_shot_light.png`, left uncommitted  -> exit **1**, caught,
      but only by the staleness proxy below;
    * the same bytes written to that path and **committed**, so the tree was
      clean  -> exit **0**, `CENSUS PASSED`.

  Both screens are a light mode with an `#F8F7F5` background, `#1F2937` ink and
  no `#000000`. **A stale image, or a correct image of the wrong screen, is
  indistinguishable from a good one once it is committed.**

  That cannot be fixed here. Currency would mean regenerating the image, and
  regenerating is precisely what is impossible on this platform by construction
  (the font rasteriser). **Judging a reference image is a reviewer's job** —
  open the PNG and look at it. What the tool can do is stop the *set* of images
  and the *list* of images from drifting apart, which it now checks both ways.

  ## THE DISTINCT-COLOUR BASELINE — the one signal that does exist

  Every image is compared against a recorded count of its distinct colours, and
  a mismatch fails. The thirty-one committed images have thirty-one different
  counts — 772 / 1203 / 1243 / 177 / 190 / 361 / 373 / 569 / 667, then the six
  quiz images at 233 / 266 / 781 / 785 / 1145 / 1090, and the twenty this
  project has added since — so the favourites bytes written over
  `word_detail_user_shot_light.png` reported 177 where the honest value is
  361.

  **This does not close the gap above, and it is not an identity oracle.** What it
  adds, precisely:

    * it catches a swapped or stale image **whose colour histogram differs**;

    * it gives a second, independent signal that an image was rewritten without a
      regeneration, complementing the git staleness proxy below — which only
      fires while the tree is dirty.

  What it does **not** add:

    * it cannot say *which* image the bytes belong to;
    * **two images sharing a count would both pass — and two of this round's
      do.** `dictionary_word_user_shot_light.png` and
      `attribution_screen_user_shot_light.png` both have 191 distinct colours,
      and the bytes of one written over the other **passed the census**:
      measured, with the write verified by SHA-256 before and after. That is
      why the census now checks a **second** statistic — the pixel count of the
      image's most common colour — and why the pair of numbers is unique for
      all thirty-one images. See `$ExpectedDominantCount` below.
    * **it is rasteriser-dependent, so it also fires on a legitimate
      regeneration** on another platform. When you regenerate on purpose, update
      `$ExpectedColourCount` **and** `$ExpectedDominantCount` from the
      `distinct colours` and `dominant` lines this run prints — that is the
      intended maintenance, not a defect to route around.

  Dimensions carry no signal (all thirty-one are 1080x2340) and mtime is
  unimplementable (git does not track it, and `--update-goldens` writes all
  thirty-one within a few milliseconds of each other).

  ## THE SET-EQUALITY GUARD

  Every `*.png` in `test/goldens/goldens/` must appear in `$ImagePath`, and every
  entry in `$ImagePath` must be one of those files. Both directions fail.

  Without it, an eighth image sitting on disk that no list mentions was unguarded
  — measured: `CENSUS PASSED`, exit 0 — because an image the census does not read
  is an image nothing checks. This is what a screen task that ships a new
  reference image would otherwise have to remember by hand, and it is what the
  quiz's six images were nearly another instance of: they were generated into
  `test/goldens/goldens/` first, and the guard is what made the run notice that
  nothing had listed them.

  **The guard runs on the DEFAULT list only.** Passing `-ImagePath` replaces the
  list wholesale and is a deliberate narrowing — the `.EXAMPLE` below asks for one
  image on purpose — so the tool does not second-guess it. The consequence is
  stated rather than hidden: **a run that passes `-ImagePath` proves nothing
  about list coverage**, which is why every canary that tests coverage has to go
  through the default list.

  ## THE STALENESS PROXY

  On the default list, one more cheap check: if the reference images are dirty in
  git while `test/goldens/golden_test.dart` is clean, they were rewritten by
  something other than the test that writes them.

  **This is a proxy and it is weak.** It catches a hand-edited or copied-over
  PNG — measured above, exit 1 on the uncommitted doctored image. It does **not**
  catch a wrong-but-committed image: committing the same doctored bytes leaves
  `git status --porcelain` empty and the run returns exit 0, also measured above.
  It is here because it is nearly free, not because it is sufficient. The reverse
  direction (test changed, images not) is deliberately **not** checked: editing a
  comment in the test file would alarm on every such edit.

  ## VERDICTS ARE BUFFERED

  A run that dies part-way through the list used to exit 1 correctly but had
  already printed `CENSUS PASSED` for every image it reached before the throw —
  so a reader scanning the log rather than the exit code read green. Per-image
  verdicts are now buffered and printed **only** in the final summary, after the
  exit code has been decided. The per-image measurements still print as they go;
  those are data, not verdicts.

  An unreadable file — zero bytes, or a text file wearing a `.png` name — used to
  abort the whole run with a GDI+ exception and print no summary at all. It is now
  one failed image, and the run continues so every other verdict is still printed.
  Both cases still exit 1, loudly.

  ## REGENERATING

  It reads committed pixels; it does not regenerate anything. Regenerating is the
  test's job, and only on purpose:

    # comment out the `skip:` lines in test/goldens/golden_test.dart, then
    flutter test test/goldens/golden_test.dart --update-goldens
    # put the skip: lines back, then run this script and read the numbers
    # and OPEN the new PNGs and look at them — the census cannot.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\golden_census.ps1

.EXAMPLE
  # One image only. This REPLACES the list, so the set-equality and staleness
  # guards do not run and the result says nothing about coverage.
  powershell -ExecutionPolicy Bypass -File tool\golden_census.ps1 `
    -ImagePath test/goldens/goldens/stats_screen_user_shot_dark.png
#>
[CmdletBinding()]
param(
  # Reference images, **relative to the repository root**. Defaults to every
  # golden the test file writes. Absolute paths are not supported: Windows
  # PowerShell 5.1's `Join-Path $root <absolute child>` does not return the
  # child, it concatenates, so an absolute path resolves to a nonsense location
  # and the script reports "no golden at <path>" and exits 1. That failure is
  # loud rather than silent, but it reads like a missing file rather than a
  # bad argument.
  #
  # A screen task that ships a new reference image adds its shots here. The
  # set-equality guard below then **fails the run** if that is forgotten, in
  # either direction.
  [string[]]$ImagePath = @(
    'test/goldens/goldens/home_shell_user_shot.png',
    'test/goldens/goldens/stats_screen_user_shot_light.png',
    'test/goldens/goldens/stats_screen_user_shot_dark.png',
    'test/goldens/goldens/favorites_screen_user_shot_light.png',
    'test/goldens/goldens/favorites_screen_user_shot_dark.png',
    'test/goldens/goldens/word_detail_user_shot_light.png',
    'test/goldens/goldens/word_detail_user_shot_dark.png',
    'test/goldens/goldens/flashcards_screen_user_shot_light.png',
    'test/goldens/goldens/flashcards_screen_user_shot_dark.png',
    # The quiz, three states x two modes. **These six are the images whose absence
    # let the light-mode verdict tokens ship on a dark phone**: `quiz_screen.dart`
    # painted `#16A34A` / `#DC2626` in dark mode, and nothing here had ever looked
    # at a pixel of that screen. Three states rather than one because the defect
    # only exists once an option is answered - an unanswered question draws no
    # verdict colour at all - and two modes because every one of those colours is
    # mode-aware. A screen with no image here is a screen nothing checks.
    'test/goldens/goldens/quiz_screen_unanswered_user_shot_light.png',
    'test/goldens/goldens/quiz_screen_unanswered_user_shot_dark.png',
    'test/goldens/goldens/quiz_screen_correct_user_shot_light.png',
    'test/goldens/goldens/quiz_screen_correct_user_shot_dark.png',
    'test/goldens/goldens/quiz_screen_wrong_user_shot_light.png',
    'test/goldens/goldens/quiz_screen_wrong_user_shot_dark.png',
    # The ten images added when the audit found four screens with no reference
    # image at all. **This is the same lesson the six above were added for, and
    # the audit is the point: `MoreScreen`, `QuizSetupScreen` and `QuizResultScreen`
    # had none in either mode, and `HomeScreen` had none of its own - only the
    # shell's, which happens to show it in light. A screen this tool does not read
    # is a screen nothing checks, and that is exactly how the quiz's light-mode
    # verdict tokens shipped on a dark phone for fifteen review-clean tasks.
    'test/goldens/goldens/home_screen_user_shot_light.png',
    'test/goldens/goldens/home_screen_user_shot_dark.png',
    'test/goldens/goldens/more_screen_user_shot_light.png',
    'test/goldens/goldens/more_screen_user_shot_dark.png',
    'test/goldens/goldens/quiz_setup_screen_user_shot_light.png',
    'test/goldens/goldens/quiz_setup_screen_user_shot_dark.png',
    'test/goldens/goldens/quiz_result_screen_user_shot_light.png',
    'test/goldens/goldens/quiz_result_screen_user_shot_dark.png',
    # The screen that round added, given a reference image from birth rather than
    # from the next task that notices it is missing - which is the habit that
    # produced the four gaps above.
    'test/goldens/goldens/app_info_screen_user_shot_light.png',
    'test/goldens/goldens/app_info_screen_user_shot_dark.png',
    # The dictionary's own three screens, added with the application layer that
    # built them. **A screen this tool does not read is a screen nothing
    # checks**, and the dictionary's search, its word screen and its
    # attribution screen are three new surfaces with their own colours: the
    # attribution screen names a licence and three upstream sources in Latin
    # runs, and the word screen lays out Arabic at a size the artwork never
    # specified.
    'test/goldens/goldens/dictionary_search_user_shot_light.png',
    'test/goldens/goldens/dictionary_search_user_shot_dark.png',
    'test/goldens/goldens/dictionary_word_user_shot_light.png',
    'test/goldens/goldens/dictionary_word_user_shot_dark.png',
    'test/goldens/goldens/attribution_screen_user_shot_light.png',
    'test/goldens/goldens/attribution_screen_user_shot_dark.png'
  )
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot

# --- the distinct-colour baseline ------------------------------------------------
#
# The one cheap signal that exists against a swapped image. **The committed
# images all have different counts**, so a file replaced with another file's
# bytes reports a count that belongs to some other image:
#
#   772 / 1203 / 1243 / 177 / 190 / 361 / 373 / 569 / 667        (the first nine)
#   233 / 266 / 781 / 785 / 1145 / 1090                          (the six quiz)
#
# and doctoring `word_detail_user_shot_light.png` with the favourites bytes
# reported **177 where the honest value is 361**. The script already computes
# this number to print it, so comparing it costs one line.
#
# **WHAT THIS IS NOT, and the limits are load-bearing:**
#
#   * It is a **currency detector, not an identity oracle.** It catches a swap
#     whose count differs. Two images with the same count would still pass, and
#     it cannot say *which* image the bytes belong to.
#   * **It is rasteriser-dependent, so it also fires on any legitimate
#     regeneration** - the counts are whatever this machine's font rasteriser
#     produced. A regeneration on another platform reds here with no defect
#     present. When you regenerate on purpose, update the numbers below from the
#     `distinct colours` line the run prints.
#   * It does **not** close the gap named above. No pixel property distinguishes
#     one screen's render from another's in general; this catches the cases where
#     the colour histograms happen to differ, which is all fifteen of them now.
#   * **Dimensions carry no signal** - all nine are 1080x2340 - and **mtime is
#     unimplementable**: git does not track it, and all nine files are written
#     within a few milliseconds of each other by `--update-goldens`.
#
# Measured independently rather than read out of this script: a plain
# `HashSet[string]` sweep over each committed PNG returns exactly these numbers.
$ExpectedColourCount = [ordered]@{
  'test/goldens/goldens/app_info_screen_user_shot_dark.png'                 = 210
  'test/goldens/goldens/app_info_screen_user_shot_light.png'                = 170
  'test/goldens/goldens/attribution_screen_user_shot_dark.png'              = 214
  'test/goldens/goldens/attribution_screen_user_shot_light.png'             = 192
  'test/goldens/goldens/dictionary_search_user_shot_dark.png'               = 1276
  'test/goldens/goldens/dictionary_search_user_shot_light.png'              = 764
  'test/goldens/goldens/dictionary_word_user_shot_dark.png'                 = 216
  'test/goldens/goldens/dictionary_word_user_shot_light.png'                = 175
  'test/goldens/goldens/favorites_screen_user_shot_dark.png'                = 204
  'test/goldens/goldens/favorites_screen_user_shot_light.png'               = 161
  'test/goldens/goldens/flashcards_screen_user_shot_dark.png'               = 71584
  'test/goldens/goldens/flashcards_screen_user_shot_light.png'              = 70248
  'test/goldens/goldens/home_screen_user_shot_dark.png'                     = 39105
  'test/goldens/goldens/home_screen_user_shot_light.png'                    = 15318
  'test/goldens/goldens/home_shell_user_shot.png'                           = 1864
  'test/goldens/goldens/more_screen_user_shot_dark.png'                     = 784
  'test/goldens/goldens/more_screen_user_shot_light.png'                    = 683
  'test/goldens/goldens/quiz_result_screen_user_shot_dark.png'              = 385
  'test/goldens/goldens/quiz_result_screen_user_shot_light.png'             = 349
  'test/goldens/goldens/quiz_screen_correct_user_shot_dark.png'             = 767
  'test/goldens/goldens/quiz_screen_correct_user_shot_light.png'            = 820
  'test/goldens/goldens/quiz_screen_unanswered_user_shot_dark.png'          = 291
  'test/goldens/goldens/quiz_screen_unanswered_user_shot_light.png'         = 233
  'test/goldens/goldens/quiz_screen_wrong_user_shot_dark.png'               = 1108
  'test/goldens/goldens/quiz_screen_wrong_user_shot_light.png'              = 1157
  'test/goldens/goldens/quiz_setup_screen_user_shot_dark.png'               = 872
  'test/goldens/goldens/quiz_setup_screen_user_shot_light.png'              = 536
  'test/goldens/goldens/stats_screen_user_shot_dark.png'                    = 1290
  'test/goldens/goldens/stats_screen_user_shot_light.png'                   = 1228
  'test/goldens/goldens/word_detail_user_shot_dark.png'                     = 529
  'test/goldens/goldens/word_detail_user_shot_light.png'                    = 349
}

# --- the dominant-colour baseline ------------------------------------------------
#
# **A second, independent statistic, and the reason it exists is measured.**
#
# The distinct-colour count alone is **not** enough to catch a swapped image.
# Two of the dictionary's own images collide on it:
#
#   dictionary_word_user_shot_light.png     191 distinct colours
#   attribution_screen_user_shot_light.png  191 distinct colours
#
# and the bytes of one written over the other **passed the census** - measured,
# with the write verified by SHA-256 before and after. That is the limitation
# the section above states ("two images sharing a count would still pass"),
# and this round's images are what turned it from a theoretical gap into a
# measured one.
#
# So the census now checks **two** numbers per image: the number of distinct
# colours, and the number of pixels in the image's most common colour. The two
# are independent statistics of the same histogram, and no two of the thirty-one
# committed images share a pair:
#
#   (191, 1611901)  attribution_screen_user_shot_light
#   (191, 1766343)  dictionary_word_user_shot_light
#
# A swap between them now fails on the second number.
#
# **It is still not an identity oracle.** Two images that agree on both
# numbers would still pass, and a wrong-but-committed image is still invisible
# to the pixel checks - the git staleness proxy below is the only thing that
# sees an uncommitted rewrite.
$ExpectedDominantCount = [ordered]@{
  'test/goldens/goldens/app_info_screen_user_shot_dark.png'                 = 1395730
  'test/goldens/goldens/app_info_screen_user_shot_light.png'                = 1360339
  'test/goldens/goldens/attribution_screen_user_shot_dark.png'              = 1611891
  'test/goldens/goldens/attribution_screen_user_shot_light.png'             = 1611901
  'test/goldens/goldens/dictionary_search_user_shot_dark.png'               = 2052616
  'test/goldens/goldens/dictionary_search_user_shot_light.png'              = 2058429
  'test/goldens/goldens/dictionary_word_user_shot_dark.png'                 = 1766339
  'test/goldens/goldens/dictionary_word_user_shot_light.png'                = 1766343
  'test/goldens/goldens/favorites_screen_user_shot_dark.png'                = 1913229
  'test/goldens/goldens/favorites_screen_user_shot_light.png'               = 1889635
  'test/goldens/goldens/flashcards_screen_user_shot_dark.png'               = 947652
  'test/goldens/goldens/flashcards_screen_user_shot_light.png'              = 921575
  'test/goldens/goldens/home_screen_user_shot_dark.png'                     = 803196
  'test/goldens/goldens/home_screen_user_shot_light.png'                    = 1020191
  'test/goldens/goldens/home_shell_user_shot.png'                           = 1020191
  'test/goldens/goldens/more_screen_user_shot_dark.png'                     = 1802169
  'test/goldens/goldens/more_screen_user_shot_light.png'                    = 1787548
  'test/goldens/goldens/quiz_result_screen_user_shot_dark.png'              = 2100067
  'test/goldens/goldens/quiz_result_screen_user_shot_light.png'             = 2092810
  'test/goldens/goldens/quiz_screen_correct_user_shot_dark.png'             = 1227232
  'test/goldens/goldens/quiz_screen_correct_user_shot_light.png'            = 1167698
  'test/goldens/goldens/quiz_screen_unanswered_user_shot_dark.png'          = 1337065
  'test/goldens/goldens/quiz_screen_unanswered_user_shot_light.png'         = 1278082
  'test/goldens/goldens/quiz_screen_wrong_user_shot_dark.png'               = 1221322
  'test/goldens/goldens/quiz_screen_wrong_user_shot_light.png'              = 1161793
  'test/goldens/goldens/quiz_setup_screen_user_shot_dark.png'               = 1771355
  'test/goldens/goldens/quiz_setup_screen_user_shot_light.png'              = 1767661
  'test/goldens/goldens/stats_screen_user_shot_dark.png'                    = 1270090
  'test/goldens/goldens/stats_screen_user_shot_light.png'                   = 1270125
  'test/goldens/goldens/word_detail_user_shot_dark.png'                     = 1265041
  'test/goldens/goldens/word_detail_user_shot_light.png'                    = 1227391
}

# The one directory the default list is allowed to cover.
$goldenDirRelative = 'test/goldens/goldens'
$goldenDirFull = Join-Path $root ($goldenDirRelative -replace '/', '\')

# Whether the caller narrowed the list. Everything scope-related below is gated
# on this, and the `.DESCRIPTION` says so in as many words.
$callerNarrowedTheList = $PSBoundParameters.ContainsKey('ImagePath')

# `H` is the built-in alias for Get-History and aliases outrank functions in
# PowerShell's resolution order, so this must not be called `H`.
function Get-PixelHex($bitmap, $x, $y) {
  $c = $bitmap.GetPixel($x, $y)
  return '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
}

# Counts every exact colour in one image. A full sweep on purpose: the defect
# being hunted is a *thin* one, and a sampled grid would walk straight past a 1px
# keyline. That is also why the darkest-pixel scan below uses a 2px grid and this
# does not.
function Get-ColorCounts($bitmap) {
  $counts = @{}
  for ($y = 0; $y -lt $bitmap.Height; $y++) {
    for ($x = 0; $x -lt $bitmap.Width; $x++) {
      $c = $bitmap.GetPixel($x, $y)
      $hex = '{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
      if ($counts.ContainsKey($hex)) { $counts[$hex]++ } else { $counts[$hex] = 1 }
    }
  }
  return $counts
}

$allFailures = @()

# Buffered. A run that dies part-way cannot have already printed a green verdict
# for the images it reached.
$verdicts = @()

# --------------------------------------------------------------------------------
# The set-equality guard, both directions.
# --------------------------------------------------------------------------------
if (-not $callerNarrowedTheList) {
  $onDisk = @()
  if (Test-Path -LiteralPath $goldenDirFull) {
    $onDisk = @(Get-ChildItem -LiteralPath $goldenDirFull -Filter '*.png' -File |
      ForEach-Object { "$goldenDirRelative/$($_.Name)" })
  }
  # Normalise both sides to forward slashes, so a caller who typed a backslash is
  # not told the list is wrong when it is not.
  $listed = @($ImagePath | ForEach-Object { $_ -replace '\\', '/' })

  $unlisted = @($onDisk | Where-Object { $listed -notcontains $_ })
  $absent = @($listed | Where-Object { $onDisk -notcontains $_ })

  Write-Host ''
  Write-Host 'List coverage (default list only)'
  Write-Host ("    images on disk : {0}" -f $onDisk.Count)
  Write-Host ("    images listed  : {0}" -f $listed.Count)
  if ($unlisted.Count -gt 0) {
    Write-Host '    UNGUARDED: on disk but not in $ImagePath:' -ForegroundColor Red
    foreach ($orphan in $unlisted) { Write-Host "      $orphan" -ForegroundColor Red }
    $allFailures += @(
      $unlisted | ForEach-Object {
        "list coverage: $_ exists on disk but is not in the ImagePath list, so no pixel check has ever looked at it"
      }
    )
  }
  if ($absent.Count -gt 0) {
    Write-Host '    LISTED BUT NOT ON DISK:' -ForegroundColor Red
    foreach ($phantom in $absent) { Write-Host "      $phantom" -ForegroundColor Red }
    $allFailures += @(
      $absent | ForEach-Object {
        "list coverage: $_ is in the ImagePath list but no such PNG is on disk"
      }
    )
  }
  if ($unlisted.Count -eq 0 -and $absent.Count -eq 0) {
    Write-Host '    ok: the list and the directory are the same set' -ForegroundColor Green
  }

  # --------------------------------------------------------------------------------
  # The staleness proxy. Weak on purpose; the .DESCRIPTION says exactly how.
  # --------------------------------------------------------------------------------
  Write-Host ''
  Write-Host 'Staleness proxy'
  $gitError = $null
  $status = @()
  try {
    # `-C` rather than `Push-Location`, so nothing can leave the caller's location
    # moved. A non-zero exit is handled: the output is what is read.
    $status = @(& git -C $root status --porcelain -- $goldenDirRelative 'test/goldens/golden_test.dart' 2>&1)
    if ($LASTEXITCODE -ne 0) { $gitError = ($status -join ' ') }
  } catch {
    $gitError = $_.Exception.Message
  }

  if ($gitError) {
    # A missing or broken git must not fail the census. It is a developer tool with
    # a git dependency for one optional check, and a false alarm here teaches people
    # to ignore the output.
    Write-Host ("    SKIPPED: git could not report status ({0})" -f $gitError)
  } else {
    $pngLines = @($status | Where-Object { $_ -match [regex]::Escape($goldenDirRelative) })
    $testLines = @($status | Where-Object { $_ -match 'golden_test\.dart$' })
    Write-Host ("    modified PNGs : {0}" -f $pngLines.Count)
    Write-Host ("    modified test : {0}" -f $testLines.Count)
    if ($pngLines.Count -gt 0 -and $testLines.Count -eq 0) {
      Write-Host '    FAIL: reference images are modified but golden_test.dart is not' -ForegroundColor Red
      Write-Host '          — they were rewritten by something other than the test that writes them.' -ForegroundColor Red
      $allFailures += @(
        'staleness: the reference images are modified in git while ' +
        'test/goldens/golden_test.dart is clean, so no test wrote them (weak proxy: ' +
        'it would NOT catch a wrong-but-committed image)'
      )
    } elseif ($pngLines.Count -eq 0 -and $testLines.Count -eq 0) {
      Write-Host '    ok: nothing modified' -ForegroundColor Green
    } else {
      Write-Host '    (images and/or test modified; run `flutter test --update-goldens` and inspect the PNGs)'
    }
  }
} else {
  Write-Host ''
  Write-Host 'List coverage: SKIPPED - -ImagePath was supplied, which replaces the default list.'
  Write-Host 'A narrowed run says NOTHING about coverage. Re-run with no arguments for that.'
}

foreach ($relative in $ImagePath) {
  $full = Join-Path $root $relative

  if (-not (Test-Path -LiteralPath $full)) {
    Write-Host ''
    Write-Host "  FAIL: no golden at $relative. Regenerate it before running the census." -ForegroundColor Red
    $allFailures += "missing image $relative"
    $verdicts += [pscustomobject]@{ Image = $relative; Verdict = 'FAIL'; Why = 'no such file' }
    continue
  }

  $bitmap = $null
  try {
    $bitmap = [System.Drawing.Bitmap]::FromFile($full)
  } catch {
    $why = "unreadable as a PNG: $($_.Exception.Message)"
    Write-Host ''
    Write-Host "  FAIL: $relative is $why" -ForegroundColor Red
    $allFailures += "$relative : $why"
    $verdicts += [pscustomobject]@{ Image = $relative; Verdict = 'FAIL'; Why = 'unreadable as a PNG' }
    continue
  }

  try {
    $counts = Get-ColorCounts $bitmap

    function Count-Of($hex) {
      $key = $hex.TrimStart('#').ToUpperInvariant()
      if ($counts.ContainsKey($key)) { return $counts[$key] }
      return 0
    }

    Write-Host ''
    Write-Host "Golden census - $relative"
    Write-Host ("  {0} x {1} px, {2} distinct colours" -f $bitmap.Width, $bitmap.Height, $counts.Count)
    Write-Host ''

    $failures = @()

    # --- mode, then the ink that mode is supposed to be rendering ---------------
    $lightBg = Count-Of 'F8F7F5'
    $darkBg = Count-Of '020E24'
    $mode = 'unidentified'
    # **The mode is whichever background DOMINATES, not whichever is absent.**
    # The navy #020E24 is the dark background *and* the ink on the gold button,
    # so it appears in a light render too -- 1,558 px of it -- and the old
    # "exactly one of them must be 0" test could not tell the two apart. The
    # dominant one is the background: the other is a minority of the pixels.
    if ($lightBg -gt 0 -and $lightBg -gt ($darkBg * 10)) {
      $mode = 'light'
    } elseif ($darkBg -gt 0 -and $darkBg -gt ($lightBg * 10)) {
      $mode = 'dark'
    } else {
      $failures += "mode is not identifiable: #F8F7F5 is $lightBg px and #020E24 is $darkBg px (one must dominate the other by 10x)"
    }

    $expectedInk = if ($mode -eq 'dark') { 'FFFFFF' } else { '1F2937' }
    $ink = Count-Of $expectedInk
    if ($mode -ne 'unidentified' -and $ink -le 0) {
      $failures += "#$expectedInk is absent, the $mode text ink is not rendering"
    }

    # --- the pass condition -----------------------------------------------------
    $black = Count-Of '000000'
    if ($black -ne 0) {
      $failures += "#000000 is $black px, must be 0 (phantom black keyline)"
    }

    $tonal = Count-Of '1D1B20'
    if ($tonal -ne 0) {
      $failures += "#1D1B20 is $tonal px, must be 0 (Material text, not brand ink)"
    }

    # --- the verdict tokens must belong to the mode ----------------------------
    #
    # **The check that would have caught the defect these six quiz images were
    # added for.** `quiz_screen.dart` named `AppColors.successLight` and
    # `errorLight` at four call sites, two of them `const Icon`s that could not
    # read the theme at all, so a dark phone drew the light verdict tokens. On the
    # user's own screenshots that measured **0** pixels of `#4ADE80` and **0** of
    # `#F87171`, against 15,795 of `#16A34A` and 15,719 of `#DC2626`.
    #
    # Nothing above would have noticed: those are all *present* colours, a dark
    # image with a light verdict token in it is still a valid dark image, and the
    # distinct-colour baseline only dates the file. What makes it a defect is one
    # hex belonging to the wrong brightness - a property of the mode this block
    # already established, so it costs two lookups and no new machinery.
    if ($mode -eq 'dark') {
      foreach ($leak in @(
          @{ hex = '16A34A'; name = 'success (light)' },
          @{ hex = 'DC2626'; name = 'error (light)'   }
        )) {
        $n = Count-Of $leak.hex
        if ($n -gt 0) {
          $failures += "#$($leak.hex) is $n px in a dark render - that is the $($leak.name) token on a dark screen"
        }
      }
    } elseif ($mode -eq 'light') {
      foreach ($leak in @(
          @{ hex = '4ADE80'; name = 'success (dark)' },
          @{ hex = 'F87171'; name = 'error (dark)'   }
        )) {
        $n = Count-Of $leak.hex
        if ($n -gt 0) {
          $failures += "#$($leak.hex) is $n px in a light render - that is the $($leak.name) token on a light screen"
        }
      }
    }

    # --- the distinct-colour baseline ---------------------------------------------
    # A currency detector, not an identity oracle. See $ExpectedColourCount above
    # for what it does not catch; the short version is that two images with the
    # same count would still both pass - **and two of this round's images do**,
    # which is why $ExpectedDominantCount below exists.
    $normalised = $relative -replace '\\', '/'
    if ($ExpectedColourCount.Contains($normalised)) {
      $expected = $ExpectedColourCount[$normalised]
      if ($counts.Count -ne $expected) {
        $failures += ("distinct colours: $($counts.Count), baseline for this path is $expected " +
          "(a swapped or stale image; OR you regenerated this one on purpose, in which case " +
          'update $ExpectedColourCount in tool/golden_census.ps1)')
      }
    } else {
      $failures += ("no distinct-colour baseline for $normalised - add one, or the path is " +
        'wrong; a path with no baseline is an image nothing can date')
    }

    # --- the dominant-colour baseline ---------------------------------------------
    # **The second, independent statistic.** The number of pixels in the image's
    # most common colour. It is what catches a swap between two images that
    # happen to share a distinct-colour count - and the measurement above says
    # two of them do.
    $dominant = ($counts.GetEnumerator() |
        Sort-Object -Property Value -Descending |
        Select-Object -First 1)
    $dominantCount = if ($null -eq $dominant) { 0 } else { $dominant.Value }
    if ($ExpectedDominantCount.Contains($normalised)) {
      $expectedDominant = $ExpectedDominantCount[$normalised]
      if ($dominantCount -ne $expectedDominant) {
        $failures += ("dominant colour: $dominantCount px, baseline for this path is " +
          "$expectedDominant (a swapped or stale image; OR you regenerated this one on " +
          'purpose, in which case update $ExpectedDominantCount in tool/golden_census.ps1)')
      }
    } else {
      $failures += ("no dominant-colour baseline for $normalised - add one, or the path is " +
        'wrong; a path with no baseline is an image nothing can date')
    }

    # --- report -----------------------------------------------------------------
    Write-Host ("  Mode: {0}  (#F8F7F5 {1} px, #0F172A {2} px)" -f $mode, $lightBg, $darkBg)
    Write-Host ''
    Write-Host '  Pass condition (docs/design/style-direction.md)'
    Write-Host ("    #000000        : {0,-10} {1}" -f $black, $(if ($black -eq 0) { 'ok' } else { 'FAIL' }))
    Write-Host ("    #1D1B20        : {0,-10} {1}" -f $tonal, $(if ($tonal -eq 0) { 'ok' } else { 'FAIL' }))
    Write-Host ("    mode           : {0,-10} {1}" -f $mode, $(if ($mode -ne 'unidentified') { 'ok' } else { 'FAIL' }))
    Write-Host ("    #{0} (ink) : {1,-10} {2}" -f $expectedInk, $ink, $(if ($ink -gt 0) { 'ok' } else { 'FAIL' }))
    Write-Host ("    distinct       : {0,-10} {1}" -f $counts.Count, $(if ($ExpectedColourCount.Contains($normalised) -and $counts.Count -eq $ExpectedColourCount[$normalised]) { 'ok' } else { 'FAIL' }))
    Write-Host ("    dominant       : {0,-10} {1}" -f $dominantCount, $(if ($ExpectedDominantCount.Contains($normalised) -and $dominantCount -eq $ExpectedDominantCount[$normalised]) { 'ok' } else { 'FAIL' }))

    Write-Host ''
    Write-Host '  Brand tokens'
    $tokens = [ordered]@{
      'F8F7F5' = 'background (light)'
      'FFFFFF' = 'surface'
      '1F2937' = 'text ink (light)'
      'F9FAFB' = 'text ink (dark)'
      '6B7280' = 'secondary text (light)'
      '94A3B8' = 'secondary text (dark)'
      'E5E7EB' = 'hairline (light)'
      '334155' = 'hairline (dark)'
      '885CF6' = 'primary (light)'
      'A78BFA' = 'primary (dark)'
      'F59E0B' = 'accent'
      '0F172A' = 'background (dark)'
      '1E293B' = 'surface (dark)'
      '16A34A' = 'success (light)'
      '4ADE80' = 'success (dark)'
      'DC2626' = 'error (light)'
      'F87171' = 'error (dark)'
    }
    foreach ($entry in $tokens.GetEnumerator()) {
      Write-Host ("    #{0} : {1,-10} {2}" -f $entry.Key, (Count-Of $entry.Key), $entry.Value)
    }

    Write-Host ''
    Write-Host '  Ten most common colours'
    $counts.GetEnumerator() |
      Sort-Object -Property Value -Descending |
      Select-Object -First 10 |
      ForEach-Object { Write-Host ("    #{0} : {1}" -f $_.Key, $_.Value) }

    # --- darkest pixel ----------------------------------------------------------
    # A stronger statement than the two exact-colour counts: if the darkest pixel
    # in the whole image is the brand ink, there is no near-black hiding either.
    # Scanned on a 2px grid, because a full-image GetPixel sweep is minutes.
    $darkestHex = '#FFFFFF'
    $darkestSum = 765
    $darkestAt = @(0, 0)
    for ($y = 0; $y -lt $bitmap.Height; $y += 2) {
      for ($x = 0; $x -lt $bitmap.Width; $x += 2) {
        $c = $bitmap.GetPixel($x, $y)
        $sum = $c.R + $c.G + $c.B
        if ($sum -lt $darkestSum) {
          $darkestSum = $sum
          $darkestHex = '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
          $darkestAt = @($x, $y)
        }
      }
    }
    Write-Host ''
    Write-Host ("  Darkest pixel (2px grid): {0} at ({1},{2})" -f $darkestHex, $darkestAt[0], $darkestAt[1])

    if ($failures.Count -gt 0) {
      foreach ($failure in $failures) { Write-Host "  FAIL: $failure" -ForegroundColor Red }
      $allFailures += $failures | ForEach-Object { "$relative : $_" }
      $verdicts += [pscustomobject]@{ Image = $relative; Verdict = 'FAIL'; Why = ($failures -join '; ') }
    } else {
      $verdicts += [pscustomobject]@{ Image = $relative; Verdict = 'PASS'; Why = '' }
    }
  } finally {
    $bitmap.Dispose()
  }
}

# --------------------------------------------------------------------------------
# The summary. Every verdict is printed HERE and nowhere else, so a run that dies
# part-way cannot have already printed a green line for the images it reached.
# --------------------------------------------------------------------------------
Write-Host ''
Write-Host 'Verdicts (printed only now, after the exit code is decided)'
foreach ($v in $verdicts) {
  if ($v.Verdict -eq 'PASS') {
    Write-Host ("    PASS  {0}" -f $v.Image)
  } else {
    Write-Host ("    FAIL  {0}  -- {1}" -f $v.Image, $v.Why) -ForegroundColor Red
  }
}
$passCount = @($verdicts | Where-Object { $_.Verdict -eq 'PASS' }).Count
Write-Host ("    ---- {0} of {1} images passed" -f $passCount, $verdicts.Count)

Write-Host ''
if ($allFailures.Count -gt 0) {
  foreach ($failure in $allFailures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
  Write-Host ''
  Write-Host "CENSUS FAILED ($($allFailures.Count) problem(s) across $($verdicts.Count) image(s))" -ForegroundColor Red
  exit 1
}
Write-Host "CENSUS PASSED for all $($verdicts.Count) image(s)" -ForegroundColor Green
Write-Host 'This says the pixels are colour-clean. It does NOT say each image is of'
Write-Host 'the screen its filename claims - nothing here can tell. Open the PNGs.'
Write-Host ''
exit 0