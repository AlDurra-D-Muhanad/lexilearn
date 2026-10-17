<#
.SYNOPSIS
    Runs a command under a hard wall-clock deadline and kills it if it overruns.

.DESCRIPTION
    This project hangs in four distinct ways, and only one of them is a test failing:

      1. a test awaiting a real future inside a fake-async zone -> hangs forever.
         flutter_test's testWidgets defaults to Timeout.none, and `flutter test --timeout`
         explicitly does NOT apply to the suite-loading timeout, so a test-level bound
         does not reliably catch this.
      2. an orphaned flutter_tester / dart still holding
         build\native_assets\windows\sqlite3.dll, so the next run blocks on startup.
      3. Gradle or the Flutter tool waiting on something that will never arrive.
      4. a toolchain flake with no cause at all.

    A shell-level deadline catches all four. A test-level timeout catches, at best, one.

    Takes a single command LINE rather than an array, because this must be invocable
    from `powershell -ExecutionPolicy Bypass -File ...` where array binding is awkward.

    Exit codes:
      0   the command succeeded
      N   the command failed and returned N  (a failure is NEVER flattened into 124)
      124 TIMEOUT  - the process tree was killed at the deadline
      125 SPAWN    - the command could not be started

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\run-bounded.ps1 -Cmd "flutter analyze" -TimeoutSeconds 300
    powershell -ExecutionPolicy Bypass -File tool\run-bounded.ps1 -Cmd "flutter test" -TimeoutSeconds 900 -Label suite
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Cmd,
    [Parameter(Mandatory = $true)] [int]    $TimeoutSeconds,
    [string] $Label,
    [switch] $Quiet,
    [switch] $ShowOutput
)

$ErrorActionPreference = 'Stop'

# ---- log --------------------------------------------------------------------
$logDir = Join-Path $PSScriptRoot '..\.superpowers\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
if (-not $Label) { $Label = ($Cmd -replace '[^\w.-]+', '_') }
if ($Label.Length -gt 60) { $Label = $Label.Substring(0, 60) }
$log = Join-Path $logDir ("{0}-{1}.log" -f $Label, (Get-Date -Format 'yyyyMMdd-HHmmss'))

# ---- spawn ------------------------------------------------------------------
# cmd.exe gives us one process whose TREE we can kill wholesale.
$proc = Start-Process -FilePath 'cmd.exe' `
    -ArgumentList '/c', ('{0} > "{1}" 2>&1' -f $Cmd, $log) `
    -PassThru -WindowStyle Hidden

Write-Host ("[bounded] {0}s  {1}" -f $TimeoutSeconds, $Label)

$finished = $proc.WaitForExit($TimeoutSeconds * 1000)

if (-not $finished) {
    Write-Warning ("[bounded] TIMEOUT after {0}s - killing the tree." -f $TimeoutSeconds)

    # Kill the WHOLE tree. Killing cmd.exe alone leaves dart / flutter_tester / java
    # running, and those are exactly what keep sqlite3.dll locked for the next run.
    & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    Write-Host ''
    Write-Host ('[bounded] ---- where it stopped (last 40 lines) ----') -ForegroundColor Yellow
    if (Test-Path $log) { Get-Content $log -Tail 40 | ForEach-Object { "    $_" } }
    Write-Host ('[bounded] ------------------------------------------') -ForegroundColor Yellow
    Write-Host ("[bounded] full log: {0}" -f $log)
    exit 124
}

$code = $proc.ExitCode

if ($ShowOutput -and (Test-Path $log)) { Get-Content $log | ForEach-Object { $_ } }

if ($code -ne 0) {
    Write-Host ('[bounded] ---- failure output (last 40 lines) ----') -ForegroundColor Red
    if (Test-Path $log) { Get-Content $log -Tail 40 | ForEach-Object { "    $_" } }
    Write-Host ('[bounded] -----------------------------------------') -ForegroundColor Red
}

if ($Quiet) { Write-Host ("[bounded] exit={0}  log={1}" -f $code, (Split-Path $log -Leaf)) }
exit $code