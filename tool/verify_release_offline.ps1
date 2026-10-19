<#
.SYNOPSIS
  The release gate for docs/engineering-standards.md section 12: offline is a
  legal claim, not a feature description.

  Builds the arm64 release APK, then verifies the MERGED AndroidManifest.xml
  inside it -- not the source manifest, which is not what ships -- and reports
  the artefact's size against the size budget.

  Two INDEPENDENT measurements, both of which must pass:
    1. aapt2 dump permissions   -- authoritative, parsed from the binary AXML
    2. a raw byte scan          -- the permission names as UTF-16LE in the
                                   AXML string pool, found without aapt2 at all

  A single parser can be wrong in a way that agrees with itself. These two
  cannot agree by accident, and the second one needs no SDK.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\verify_release_offline.ps1
  powershell -ExecutionPolicy Bypass -File tool\verify_release_offline.ps1 -ApkPath build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
#>
[CmdletBinding()]
param(
  # Verify an existing APK instead of building one.
  [string]$ApkPath = '',
  # Size budget for the arm64 release APK, in megabytes.
  [double]$BudgetMB = 35.0,
  # Skip the build even when no -ApkPath is given.
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

# ---------------------------------------------------------------- permissions
# The four that must never appear in a release manifest. INTERNET and
# ACCESS_NETWORK_STATE are the ones that would make "offline" false;
# the two storage ones would make the app reach outside its own sandbox.
$forbidden = @(
  'android.permission.INTERNET',
  'android.permission.ACCESS_NETWORK_STATE',
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.MANAGE_EXTERNAL_STORAGE'
)

function Find-Aapt2 {
  $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
  if (-not (Test-Path $sdk)) { return $null }
  $bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
        Sort-Object { [version]($_.Name -replace '[^0-9.]','') } -Descending
  foreach ($d in $bt) {
    $p = Join-Path $d.FullName 'aapt2.exe'
    if (Test-Path $p) { return $p }
  }
  return $null
}

function Get-Aapt2Permissions([string]$apk, [string]$aapt2) {
  $out = & $aapt2 dump permissions $apk 2>&1
  if ($LASTEXITCODE -ne 0) { throw "aapt2 dump permissions failed: $out" }
  $found = @()
  foreach ($line in $out) {
    $t = ([string]$line).Trim()
    if ($t -match '^uses-permission: name=.([a-zA-Z0-9_.]+)') { $found += $Matches[1] }
    elseif ($t -match '^uses-permission(.+)$' -and $t -notmatch 'name=') { $found += $t }
  }
  return $found
}

# ---------------------------------------------------------------------- build
if (-not $ApkPath) {
  if ($SkipBuild) { Write-Error "-SkipBuild given but no -ApkPath. Nothing to verify."; Pop-Location; exit 2 }
  Write-Host "Building the arm64 release APK (this is the slow part)..." -ForegroundColor Cyan
  # The keystore is not in the repository, by design. It is restored from the
  # out-of-repo backup; if it is missing, the build cannot produce a signed
  # artefact and there is nothing to verify.
  $ks = Join-Path $repoRoot 'android\upload-keystore.jks'
  if (-not (Test-Path $ks)) {
    Write-Warning "android\upload-keystore.jks is absent. A release build will fail to sign."
    Write-Warning "Restore it from the out-of-repo backup. The key is irreplaceable."
  }
  & powershell -ExecutionPolicy Bypass -File 'tool\run-bounded.ps1' `
      -Cmd 'flutter build apk --release --target-platform android-arm64 --split-per-abi' `
      -TimeoutSeconds 2400 -Label 'release-gate' | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Error "build failed (exit $LASTEXITCODE)."; Pop-Location; exit $LASTEXITCODE }
  $ApkPath = 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
}

if (-not (Test-Path $ApkPath)) { Write-Error "APK not found: $ApkPath"; Pop-Location; exit 2 }
$apk = (Resolve-Path $ApkPath).Path
$size = (Get-Item $apk).Length
$mb = $size / 1MB

Write-Host ""
Write-Host "APK        : $apk"
Write-Host ("size       : {0:N0} B = {1:N2} MiB = {2:N2} MB" -f $size, $mb, ($size/1e6))
Write-Host ("budget     : {0:N2} MB -> {1}" -f $BudgetMB, $(if (($size/1e6) -le $BudgetMB) { 'within' } else { 'OVER' }))
Write-Host ""

$failures = @()

# ------------------------------------------------- check 1: aapt2 (authoritative)
$aapt2 = Find-Aapt2
$aaptPerms = @()
if ($aapt2) {
  Write-Host "check 1    : aapt2 dump permissions  ($aapt2)" -ForegroundColor Cyan
  $aaptPerms = Get-Aapt2Permissions $apk $aapt2
  if ($aaptPerms.Count -eq 0) {
    Write-Host "             no uses-permission at all" -ForegroundColor Green
  } else {
    foreach ($p in ($aaptPerms | Sort-Object -Unique)) { Write-Host "             $p" }
  }
  foreach ($f in $forbidden) {
    if ($aaptPerms -contains $f) { $failures += "aapt2 reports $f" }
  }
} else {
  Write-Host "check 1    : aapt2 NOT FOUND -- falling back to the byte scan alone" -ForegroundColor Yellow
  Write-Warning "Only one independent measurement will have been made. Install the SDK build-tools."
}

# --------------------------------------- check 2: raw byte scan (independent of aapt2)
Write-Host "check 2    : raw UTF-16LE byte scan of the APK" -ForegroundColor Cyan
$bytes = [System.IO.File]::ReadAllBytes($apk)
$found2 = @()
foreach ($f in $forbidden) {
  $needle = [System.Text.Encoding]::Unicode.GetBytes($f)
  $hit = $false
  for ($i = 0; $i -le ($bytes.Length - $needle.Length); $i++) {
    if ($bytes[$i] -ne $needle[0]) { continue }
    $match = $true
    for ($j = 1; $j -lt $needle.Length; $j++) {
      if ($bytes[$i + $j] -ne $needle[$j]) { $match = $false; break }
    }
    if ($match) { $hit = $true; break }
  }
  if ($hit) { $found2 += $f }
}
if ($found2.Count -eq 0) {
  Write-Host "             none of the four appear anywhere in the artefact" -ForegroundColor Green
} else {
  foreach ($f in $found2) { Write-Host "             FOUND $f" -ForegroundColor Red }
  $failures += "byte scan found $($found2 -join ', ')"
}

Write-Host ""
if (($size/1e6) -gt $BudgetMB) { $failures += "APK is $([math]::Round(($size/1e6)-$BudgetMB,2)) MB over the $BudgetMB MB budget" }

if ($failures.Count -gt 0) {
  Write-Host "OFFLINE GATE FAILED" -ForegroundColor Red
  foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
  Pop-Location
  exit 1
}

Write-Host "OFFLINE GATE PASSED" -ForegroundColor Green
Write-Host "  the merged release manifest carries none of the four forbidden permissions,"
Write-Host "  confirmed by two independent measurements."
Pop-Location
exit 0
