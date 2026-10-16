<#
.SYNOPSIS
  Pixel census for the committed golden reference image.

.DESCRIPTION
  `test/goldens/golden_test.dart` has to stay skipped: golden bytes depend on the
  platform's font rasteriser, so a byte-identical match across Windows and Linux
  CI is impossible by construction. That skip has a cost — the reference image
  renders the real `LexiLearnApp`, so every change to the bottom bar, the header
  or the theme in Tasks 11-15 silently invalidates it and nothing says so.

  This script is the guard. It reads the committed PNG and asserts the two
  conditions from `docs/design/style-direction.md`:

    * `#000000` must be 0 pixels  — a phantom black keyline from a `Card` or a
      Material elevation shadow, the defect that put 29,111 of them here once and
      2,363 more on a button.
    * `#1D1B20` must be 0 pixels  — Material's tonal-palette text, not the brand's.
    * `#1F2937` must be present    — the brand's text ink actually rendering.

  It then prints the full brand-token table, so a colour that has quietly moved is
  visible in the same run.

  It reads committed pixels; it does not regenerate anything. Regenerating is the
  test's job, and only on purpose:

    # comment out the `skip:` line in test/goldens/golden_test.dart, then
    flutter test test/goldens/golden_test.dart --update-goldens
    # put the skip back, then run this script and read the numbers

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\golden_census.ps1
#>
[CmdletBinding()]
param(
  # Path to the reference image, relative to the repository root.
  [string]$ImagePath = 'test/goldens/goldens/home_shell_user_shot.png'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$full = Join-Path $root $ImagePath

if (-not (Test-Path $full)) {
  Write-Error "No golden at $full. Regenerate it before running the census."
  exit 1
}

# `H` is the built-in alias for Get-History and aliases outrank functions in
# PowerShell's resolution order, so this must not be called `H`.
function Get-PixelHex($bitmap, $x, $y) {
  $c = $bitmap.GetPixel($x, $y)
  return '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
}

$bitmap = [System.Drawing.Bitmap]::FromFile($full)
try {
  Write-Host ''
  Write-Host "Golden census - $ImagePath"
  Write-Host ("  {0} x {1} px" -f $bitmap.Width, $bitmap.Height)
  Write-Host ''

  # --- count every exact colour -------------------------------------------------
  $counts = @{}
  for ($y = 0; $y -lt $bitmap.Height; $y++) {
    for ($x = 0; $x -lt $bitmap.Width; $x++) {
      $c = $bitmap.GetPixel($x, $y)
      $hex = '{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
      if ($counts.ContainsKey($hex)) { $counts[$hex]++ } else { $counts[$hex] = 1 }
    }
  }
  Write-Host ("  {0} distinct colours" -f $counts.Count)

  function Count-Of($hex) {
    $key = $hex.TrimStart('#').ToUpperInvariant()
    if ($counts.ContainsKey($key)) { return $counts[$key] }
    return 0
  }

  # --- the pass condition -------------------------------------------------------
  $failures = @()

  $black = Count-Of '000000'
  if ($black -ne 0) {
    $failures += "#000000 is $black px, must be 0 (phantom black keyline)"
  }

  $tonal = Count-Of '1D1B20'
  if ($tonal -ne 0) {
    $failures += "#1D1B20 is $tonal px, must be 0 (Material text, not brand ink)"
  }

  $ink = Count-Of '1F2937'
  if ($ink -le 0) {
    $failures += '#1F2937 is absent, the brand text ink is not rendering'
  }

  # --- report -------------------------------------------------------------------
  Write-Host ''
  Write-Host '  Pass condition (docs/design/style-direction.md)'
  Write-Host ("    #000000 : {0,-10} {1}" -f $black, $(if ($black -eq 0) { 'ok' } else { 'FAIL' }))
  Write-Host ("    #1D1B20 : {0,-10} {1}" -f $tonal, $(if ($tonal -eq 0) { 'ok' } else { 'FAIL' }))
  Write-Host ("    #1F2937 : {0,-10} {1}" -f $ink, $(if ($ink -gt 0) { 'ok' } else { 'FAIL' }))

  Write-Host ''
  Write-Host '  Brand tokens'
  $tokens = [ordered]@{
    'F8F7F5' = 'background (light)'
    'FFFFFF' = 'surface'
    '1F2937' = 'text ink'
    '6B7280' = 'secondary text'
    'E5E7EB' = 'hairline'
    '885CF6' = 'primary (light)'
    'A78BFA' = 'primary (dark)'
    'F59E0B' = 'accent'
    '0F172A' = 'background (dark)'
    '1E293B' = 'surface (dark)'
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

  # --- darkest pixel ------------------------------------------------------------
  # A stronger statement than the two exact-colour counts: if the darkest pixel in
  # the whole image is the brand ink, there is no near-black hiding either.
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

  Write-Host ''
  if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "  FAIL: $failure" -ForegroundColor Red }
    Write-Host ''
    Write-Host '  CENSUS FAILED' -ForegroundColor Red
    exit 1
  }
  Write-Host '  CENSUS PASSED' -ForegroundColor Green
  Write-Host ''
} finally {
  $bitmap.Dispose()
}
