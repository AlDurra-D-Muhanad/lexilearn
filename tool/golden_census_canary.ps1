# The canary: a block of pure black written into one of the regenerated
# reference images, the write verified independently of the census, and the
# census failing on it.  The image is then restored byte for byte from a copy
# taken before the canary - never from git, because a regenerated image is
# committed and `git checkout --` would restore the *old* bytes rather than the
# regenerated ones.
param(
  [string]$Image = 'test/goldens/goldens/home_screen_user_shot_light.png'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$full = Join-Path $root ($Image -replace '/', '\')
$name = [System.IO.Path]::GetFileName($full)
$backup = Join-Path $env:TEMP ('canary-backup-' + $name)
$work = Join-Path $env:TEMP ('canary-work-' + $name)
$out = Join-Path $env:TEMP ('canary-out-' + $name)

Copy-Item -LiteralPath $full -Destination $backup -Force
$before = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
Write-Host ("before      : {0}" -f $before)

try {
  # --- the write ----------------------------------------------------------------
  #
  # **Through a copy, never over the file GDI+ has open.** `Bitmap.FromFile`
  # holds the file it read, and `Save` back over it fails with "A generic
  # error occurred in GDI+". That is what the first version of this script
  # did, and the image was left untouched — which is the right way for that
  # particular failure to go.
  Copy-Item -LiteralPath $full -Destination $work -Force
  $bitmap = [System.Drawing.Bitmap]::FromFile($work)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.FillRectangle([System.Drawing.Brushes]::Black, 60, 560, 40, 40)
  $graphics.Dispose()
  $bitmap.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bitmap.Dispose()
  Copy-Item -LiteralPath $out -Destination $full -Force

  # --- the write, verified independently of the census --------------------------
  $check = [System.Drawing.Bitmap]::FromFile($full)
  $black = 0
  for ($y = 560; $y -lt 600; $y++) {
    for ($x = 60; $x -lt 100; $x++) {
      $c = $check.GetPixel($x, $y)
      if ($c.R -eq 0 -and $c.G -eq 0 -and $c.B -eq 0) { $black++ }
    }
  }
  $check.Dispose()
  $after = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
  Write-Host ("after       : {0}" -f $after)
  Write-Host ("verified    : {0} pure-black pixels at (60,560)-(99,599)" -f $black)
  if ($black -ne 1600) { Write-Host 'THE WRITE DID NOT LAND'; exit 2 }

  # --- the census must fail on it -----------------------------------------------
  #
  # **In its own process.** `golden_census.ps1` ends in `exit 1` when it
  # fails, and `exit` inside a called script exits the caller too - which
  # would kill this script before the restore and leave the canaried image on
  # disk.
  Write-Host ''
  Write-Host 'census on the canaried tree:'
  $censusOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'golden_census.ps1') 2>&1
  $censusExit = $LASTEXITCODE
  $censusOutput | ForEach-Object { Write-Host $_ }
  Write-Host ("census exit : {0}" -f $censusExit)
}
finally {
  # --- restore, byte for byte ---------------------------------------------------
  Copy-Item -LiteralPath $backup -Destination $full -Force
  $restored = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
  Write-Host ''
  Write-Host ("restored    : {0}" -f $restored)
  if ($restored -eq $before) {
    Write-Host 'the image is byte-identical to the one the census passed on.'
  } else {
    Write-Host '*** THE RESTORE IS NOT BYTE-IDENTICAL ***'
  }
  Remove-Item -LiteralPath $backup, $work, $out -Force -ErrorAction SilentlyContinue
}

if ($censusExit -eq 0) {
  Write-Host '*** THE CENSUS PASSED ON THE CANARY - IT CANNOT FAIL ***'
  exit 3
}
exit 0
