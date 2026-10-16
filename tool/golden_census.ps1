<#
.SYNOPSIS
  Pixel census for the committed golden reference images.

.DESCRIPTION
  `test/goldens/golden_test.dart` has to stay skipped: golden bytes depend on the
  platform's font rasteriser, so a byte-identical match across Windows and Linux
  CI is impossible by construction. That skip has a cost — the reference images
  render the real app, so every change to the bottom bar, the header, the theme
  or a screen's own colours silently invalidates them and nothing says so.

  This script is the guard. For each image it asserts, from
  `docs/design/style-direction.md`:

    * `#000000` must be 0 pixels  — a phantom black keyline from a `Card` or a
      Material elevation shadow, the defect that put 29,111 of them here once and
      2,363 more on a button.
    * `#1D1B20` must be 0 pixels  — Material's tonal-palette text, not the brand's.
    * the image's own mode must be identifiable  — a light image is one that has
      `#F8F7F5` and no `#0F172A`, a dark one the reverse. A screen that renders
      with no background at all, or both, is a broken render, not a dark mode.
    * the text ink of that mode must be present — `#1F2937` on light, `#F9FAFB` on
      dark — and the *other* mode's background must be absent.

  It then prints the full brand-token table, so a colour that has quietly moved is
  visible in the same run.

  It reads committed pixels; it does not regenerate anything. Regenerating is the
  test's job, and only on purpose:

    # comment out the `skip:` line in test/goldens/golden_test.dart, then
    flutter test test/goldens/golden_test.dart --update-goldens
    # put the skip back, then run this script and read the numbers

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\golden_census.ps1

.EXAMPLE
  # One image only
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
  [string[]]$ImagePath = @(
    'test/goldens/goldens/home_shell_user_shot.png',
    'test/goldens/goldens/stats_screen_user_shot_light.png',
    'test/goldens/goldens/stats_screen_user_shot_dark.png'
  )
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot

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

foreach ($relative in $ImagePath) {
  $full = Join-Path $root $relative

  if (-not (Test-Path $full)) {
    Write-Host ''
    Write-Host "  FAIL: no golden at $relative. Regenerate it before running the census." -ForegroundColor Red
    $allFailures += "missing image $relative"
    continue
  }

  $bitmap = [System.Drawing.Bitmap]::FromFile($full)
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
    $darkBg = Count-Of '0F172A'
    $mode = 'unidentified'
    if ($lightBg -gt 0 -and $darkBg -eq 0) {
      $mode = 'light'
    } elseif ($darkBg -gt 0 -and $lightBg -eq 0) {
      $mode = 'dark'
    } else {
      $failures += "mode is not identifiable: #F8F7F5 is $lightBg px and #0F172A is $darkBg px (expected exactly one to be 0)"
    }

    $expectedInk = if ($mode -eq 'dark') { 'F9FAFB' } else { '1F2937' }
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

    # --- report -----------------------------------------------------------------
    Write-Host ("  Mode: {0}  (#F8F7F5 {1} px, #0F172A {2} px)" -f $mode, $lightBg, $darkBg)
    Write-Host ''
    Write-Host '  Pass condition (docs/design/style-direction.md)'
    Write-Host ("    #000000        : {0,-10} {1}" -f $black, $(if ($black -eq 0) { 'ok' } else { 'FAIL' }))
    Write-Host ("    #1D1B20        : {0,-10} {1}" -f $tonal, $(if ($tonal -eq 0) { 'ok' } else { 'FAIL' }))
    Write-Host ("    mode           : {0,-10} {1}" -f $mode, $(if ($mode -ne 'unidentified') { 'ok' } else { 'FAIL' }))
    Write-Host ("    #{0} (ink) : {1,-10} {2}" -f $expectedInk, $ink, $(if ($ink -gt 0) { 'ok' } else { 'FAIL' }))

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
    } else {
      Write-Host ''
      Write-Host '  CENSUS PASSED' -ForegroundColor Green
    }
  } finally {
    $bitmap.Dispose()
  }
}

Write-Host ''
if ($allFailures.Count -gt 0) {
  foreach ($failure in $allFailures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
  Write-Host ''
  Write-Host "CENSUS FAILED ($($allFailures.Count) problem(s) across $($ImagePath.Count) image(s))" -ForegroundColor Red
  exit 1
}
Write-Host "CENSUS PASSED for all $($ImagePath.Count) image(s)" -ForegroundColor Green
Write-Host ''
exit 0
