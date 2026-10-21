<#
.SYNOPSIS
  Measures the two baseline statistics for every committed golden image.

.DESCRIPTION
  `tool/golden_census.ps1` compares each committed golden against two recorded
  numbers: how many **distinct colours** it has, and how many pixels its **most
  common colour** covers. When a golden is regenerated on purpose, those two
  numbers change and the tables in the census have to be updated.

  **This script is where the new numbers come from, and it is deliberately a
  separate program from the census.** The census's own run prints the numbers
  it measured, but reading a baseline out of the thing that checks the baseline
  makes the check and its own evidence one measurement: a census that measured
  a wrong number and was then told to expect that wrong number would agree
  with itself and be wrong. A **standalone sweep** over the committed PNGs is
  an independent measurement, and the two agreeing is the point.

  **The sweep is a full one, not a sampled grid**, because the defects these
  numbers date are thin ones — a 1px keyline — and a grid walks straight past
  them. The pixel loop is **compiled C#** rather than PowerShell: 33 images of
  1080x2340 is 83 million `GetPixel` calls, and at PowerShell's per-call cost
  that is measured in tens of minutes. The compiled loop does the same work in
  seconds, so the measurement is cheap enough to be run whenever a golden
  changes.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\golden_baseline_sweep.ps1
#>
[CmdletBinding()]
param(
  # The directory to sweep. Relative to the repository root.
  [string] $GoldenDir = 'test/goldens/goldens'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# The pixel loop, compiled. Two numbers out: the number of distinct colours,
# and the number of pixels in the most common one.
#
# **`-ReferencedAssemblies System.Drawing` is not optional.** The C# compiler
# `Add-Type` uses does not resolve `System.Drawing` from the GAC on its own,
# and without the reference the compile fails with *"the namespace name
# 'Imaging' does not exist"* — which is the whole of the sweep, not a detail of
# it.
$source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;

public static class GoldenSweep
{
    public static int[] Measure(string path)
    {
        using (Bitmap bitmap = new Bitmap(path))
        {
            BitmapData rect = bitmap.LockBits(
                new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                int width = bitmap.Width;
                int height = bitmap.Height;
                int stride = rect.Stride;
                byte[] buffer = new byte[Math.Abs(stride) * height];
                System.Runtime.InteropServices.Marshal.Copy(rect.Scan0, buffer, 0, buffer.Length);

                Dictionary<int, int> counts = new Dictionary<int, int>(1024);
                for (int y = 0; y < height; y++)
                {
                    int row = y * stride;
                    for (int x = 0; x < width; x++)
                    {
                        int i = row + x * 4;
                        int key = (buffer[i + 3] << 24) | (buffer[i + 2] << 16) | (buffer[i + 1] << 8) | buffer[i];
                        int n;
                        counts.TryGetValue(key, out n);
                        counts[key] = n + 1;
                    }
                }

                int distinct = counts.Count;
                int dominant = 0;
                foreach (int value in counts.Values)
                {
                    if (value > dominant) dominant = value;
                }
                return new int[] { distinct, dominant };
            }
            finally
            {
                bitmap.UnlockBits(rect);
            }
        }
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.Drawing.dll'

$root = Split-Path -Parent $PSScriptRoot
$dirFull = Join-Path $root ($GoldenDir -replace '/', '\')

if (-not (Test-Path -LiteralPath $dirFull)) {
  Write-Host "No golden directory at $GoldenDir" -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host ("Golden baseline sweep - {0}" -f $GoldenDir)
Write-Host '  distinct = the number of distinct colours; dominant = the pixels in the most common one'
Write-Host ''

$rows = @()
foreach ($file in (Get-ChildItem -LiteralPath $dirFull -Filter '*.png' -File | Sort-Object Name)) {
  try {
    $measured = [GoldenSweep]::Measure($file.FullName)
  } catch {
    Write-Host ("  FAIL: {0} is unreadable as a PNG: {1}" -f $file.Name, $_.Exception.Message) -ForegroundColor Red
    exit 1
  }
  $rows += [pscustomobject]@{
    Path     = "$GoldenDir/$($file.Name)"
    Distinct = $measured[0]
    Dominant = $measured[1]
  }
}

foreach ($row in $rows) {
  Write-Host ("  {0,-62} distinct {1,-7} dominant {2}" -f $row.Path, $row.Distinct, $row.Dominant)
}

Write-Host ''
Write-Host ("{0} image(s) swept." -f $rows.Count)
exit 0
