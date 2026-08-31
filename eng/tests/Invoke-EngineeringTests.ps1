#Requires -Version 7.0
<#
    .SYNOPSIS
    Runs the engineering PowerShell test suites and reports one result.

    .DESCRIPTION
    One command so the engineering automation is verified the same way locally and
    in CI, rather than as a growing list of workflow steps. Every suite is an
    ordinary script a maintainer can also run on its own.

    Two scopes, because they are verified in different places:

      Repository  Fast, self-contained suites covering the shared release
                  vocabulary, release preparation, TigerAiCore discovery, and
                  WinGet manifest generation and sealing. Normal CI runs these.

      Maintainer  The local winget-pkgs submission state machine: clone safety and
                  the guarded mutation. They build real Git repositories and the
                  submission suite runs the identity gate against the developer's
                  own Git configuration, so they belong on the maintainer machine
                  that actually performs a submission. CI does not simulate them.

    The default scope is All, which is what a maintainer should run before
    proposing a change under eng/.

    .PARAMETER Scope
    All (default), Repository, or Maintainer.

    .EXAMPLE
    pwsh eng/tests/Invoke-EngineeringTests.ps1

    .EXAMPLE
    pwsh eng/tests/Invoke-EngineeringTests.ps1 -Scope Repository
#>
[CmdletBinding()]
param(
    [ValidateSet('All', 'Repository', 'Maintainer')]
    [string] $Scope = 'All'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$suites = @(
    [pscustomobject]@{ Scope = 'Repository'; Path = 'eng/tests/TigerAiCore.Tests.ps1' }
    [pscustomobject]@{ Scope = 'Repository'; Path = 'eng/release-automation/tests/ReleaseAutomation.Tests.ps1' }
    [pscustomobject]@{ Scope = 'Repository'; Path = 'eng/release-automation/tests/ReleasePreparation.Tests.ps1' }
    [pscustomobject]@{ Scope = 'Repository'; Path = 'eng/winget/tests/TigerMarkViewWinGet.Tests.ps1' }
    [pscustomobject]@{ Scope = 'Maintainer'; Path = 'eng/winget/tests/WinGetPkgsClone.Tests.ps1' }
    [pscustomobject]@{ Scope = 'Maintainer'; Path = 'eng/winget/tests/WinGetPkgsSubmission.Tests.ps1' }
)

$selected = @($suites | Where-Object { $Scope -ceq 'All' -or $_.Scope -ceq $Scope })
if ($selected.Count -eq 0) { throw "No engineering test suite matches scope '$Scope'." }

$results = [Collections.Generic.List[object]]::new()
foreach ($suite in $selected) {
    $path = Join-Path $repositoryRoot $suite.Path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Engineering test suite is missing: $($suite.Path)"
    }

    Write-Host ''
    Write-Host "=== $($suite.Path) [$($suite.Scope)] ===" -ForegroundColor Cyan
    $elapsed = [Diagnostics.Stopwatch]::StartNew()
    # A child process per suite: each one sets its own strict mode, dot-sources its
    # own subject, and must not be able to leak state into the next.
    & pwsh -NoProfile -File $path
    $exitCode = $LASTEXITCODE
    $elapsed.Stop()
    $results.Add([pscustomobject]@{
        Suite = $suite.Path
        Scope = $suite.Scope
        Passed = $exitCode -eq 0
        Seconds = [Math]::Round($elapsed.Elapsed.TotalSeconds, 1)
    })
}

Write-Host ''
Write-Host "Engineering tests ($Scope)"
foreach ($result in $results) {
    $status = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    $colour = if ($result.Passed) { 'Green' } else { 'Red' }
    Write-Host ('  {0,-6} {1,-55} {2,5}s' -f $status, $result.Suite, $result.Seconds) -ForegroundColor $colour
}

$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -ne 0) {
    Write-Host ''
    Write-Host "FAIL: $($failed.Count) of $($results.Count) engineering test suites failed." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host "PASS: $($results.Count) engineering test suites." -ForegroundColor Green
