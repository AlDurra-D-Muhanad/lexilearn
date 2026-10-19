<#
.SYNOPSIS
    Runs a command N times under tool/run-bounded.ps1 and prints one result line per run.

.DESCRIPTION
    §1 of docs/engineering-standards.md: a claim in prose is not evidence. A flake
    needs a *rate*, and a rate needs the same command run several times with the
    result line captured every time - including the runs that fail, which are the
    ones that decide the question.

    Prints, per run:  <label> run <n> :: <the last '+N -M' progress line>  :: exit=<code>

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\measure-suite.ps1 -Cmd "flutter test" -Runs 5 -TimeoutSeconds 900 -Label suite
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Cmd,
    [int] $Runs = 5,
    [int] $TimeoutSeconds = 900,
    [string] $Label = 'measure'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logDir = Join-Path $root '.superpowers\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$results = @()
for ($i = 1; $i -le $Runs; $i++) {
    $tag = '{0}-{1}' -f $Label, $i
    $log = Join-Path $logDir ("{0}.log" -f $tag)
    if (Test-Path $log) { Remove-Item $log -Force }

    $proc = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList '/c', ('{0} > "{1}" 2>&1' -f $Cmd, $log) `
        -PassThru -WindowStyle Hidden
    $finished = $proc.WaitForExit($TimeoutSeconds * 1000)

    if (-not $finished) {
        & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        Write-Output ("{0} run {1} :: TIMEOUT after {2}s :: exit=124" -f $Label, $i, $TimeoutSeconds)
        $results += '124'
        continue
    }

    $code = $proc.ExitCode
    $line = ''
    if (Test-Path $log) {
        $line = (Get-Content $log |
            Where-Object { $_ -match '\+\d+.*(-~\d+)?( -\d+)?: (All tests passed|Some tests failed)' } |
            Select-Object -Last 1)
    }
    if (-not $line) { $line = '(no result line; see ' + (Split-Path $log -Leaf) + ')' }
    Write-Output ("{0} run {1} :: {2} :: exit={3}" -f $Label, $i, $line.Trim(), $code)
    $results += $code
}

$green = ($results | Where-Object { $_ -eq 0 }).Count
Write-Output ''
Write-Output ("{0} SUMMARY :: {1}/{2} green" -f $Label, $green, $Runs)
