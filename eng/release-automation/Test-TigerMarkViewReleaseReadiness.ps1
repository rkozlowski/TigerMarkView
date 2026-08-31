#Requires -Version 7.0
<#
    .SYNOPSIS
    Read-only readiness report for a TigerMarkView release preparation.

    .DESCRIPTION
    Confirms the deterministic parts of preparation are done and the tree is in a
    reviewable state, then ends with the standard review / commit / push handoff.
    It never commits, pushes, tags, or dispatches a workflow.

    Fast checks always run: required tools, source-repository identity and branch,
    the Version.props / workflow-default / no-hardcoded-version invariants, the
    release-notes source, and the shape of the working-tree diff.

    The expensive gates are opt-in and, when skipped, are reported as NOT RUN
    rather than PASS:

      -IncludeBuild      dotnet restore / build (warnings as errors) / test
      -IncludeInstaller  installer/Build-Installer.ps1 plus the metadata and
                         installer assertions
      -IncludeLab        eng/lab/Test-TigerMarkViewRelease.ps1 (TigerWinLab)
      -Full              all of the above

    .PARAMETER Version
    The release version being prepared. Defaults to Version.props.

    .PARAMETER Json
    Emit the machine-readable report instead of the rendered summary.
#>
[CmdletBinding()]
param(
    [string] $Version,
    [switch] $IncludeBuild,
    [switch] $IncludeInstaller,
    [switch] $IncludeLab,
    [switch] $Full,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ReleasePreparation.ps1')

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$constant = Get-TigerMarkViewReleaseConstant
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Read-TigerMarkViewConfiguredVersion -RepositoryRoot $repositoryRoot
}
if ($Full) { $IncludeBuild = $true; $IncludeInstaller = $true; $IncludeLab = $true }

$checks = [Collections.Generic.List[object]]::new()

function Add-Check { param($Check) $checks.Add($Check) }

function Invoke-Native {
    param([string] $FilePath, [string[]] $Arguments)
    $previous = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $output = (& $FilePath @Arguments 2>&1 | Out-String)
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $previous
        $global:LASTEXITCODE = 0
    }
}

# --- Tools ------------------------------------------------------------------

$requiredTools = @(
    @{ name = 'git'; blocking = $true }
    @{ name = 'dotnet'; blocking = $true }
    @{ name = 'gh'; blocking = $false }
    @{ name = 'winget'; blocking = $false }
)
foreach ($tool in $requiredTools) {
    $command = Get-Command $tool.name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    Add-Check (New-TigerMarkViewReleaseAssertion -Id "tool/$($tool.name)" `
        -Condition ($null -ne $command) `
        -PassObserved "$($tool.name) resolved." `
        -FailObserved "$($tool.name) is not on PATH." `
        -FailStatus $(if ($tool.blocking) { 'BLOCKED' } else { 'WARN' }) `
        -Evidence $(if ($command) { $command.Source } else { '' }) `
        -Remediation "Install $($tool.name).")
}

# --- Source repository identity and branch --------------------------------

$originUrl = (Invoke-Native git @('-C', $repositoryRoot, 'remote', 'get-url', 'origin')).Output.Trim()
$normalizedOrigin = ($originUrl -replace '\.git$', '' -replace '^git@github\.com:', 'https://github.com/').ToLowerInvariant()
Add-Check (New-TigerMarkViewReleaseAssertion -Id 'repo/origin' `
    -Condition ($normalizedOrigin -ceq $constant.repositoryUrl.ToLowerInvariant()) `
    -PassObserved "origin is $originUrl." `
    -FailObserved "origin is '$originUrl', not $($constant.repositoryUrl)." `
    -Evidence $originUrl `
    -Remediation "Run readiness from a clone of $($constant.repositoryUrl).")

$branch = (Invoke-Native git @('-C', $repositoryRoot, 'rev-parse', '--abbrev-ref', 'HEAD')).Output.Trim()
Add-Check (New-TigerMarkViewReleaseAssertion -Id 'repo/branch' `
    -Condition ($branch -ceq $constant.defaultBranch) `
    -PassObserved "HEAD is on $($constant.defaultBranch)." `
    -FailObserved "HEAD is on '$branch'; the release is prepared on $($constant.defaultBranch)." `
    -FailStatus 'WARN' -Evidence $branch `
    -Remediation "Switch to $($constant.defaultBranch) before committing the preparation.")

# --- Deterministic preparation invariants -------------------------------

foreach ($check in (Test-TigerMarkViewReleasePreparation -RepositoryRoot $repositoryRoot -Version $Version)) {
    Add-Check $check
}

# --- Working-tree diff shape ------------------------------------------

$porcelain = @((Invoke-Native git @('-C', $repositoryRoot, 'status', '--porcelain')).Output -split "\r?\n" |
    Where-Object { $_ })
$changedFiles = @($porcelain | ForEach-Object { ($_ -replace '^.{3}', '').Trim().Trim('"') })
$allowedForPrep = {
    param([string] $Path)
    $p = $Path -replace '\\', '/'
    $p -ceq 'Version.props' -or
    $p -ceq '.github/workflows/release.yml' -or
    $p -ceq 'README.md' -or
    $p.StartsWith('.github/release-notes/') -or
    $p.StartsWith('docs/')
}
$outside = @($changedFiles | Where-Object { -not (& $allowedForPrep $_) })
if ($changedFiles.Count -eq 0) {
    Add-Check (New-TigerMarkViewReleaseCheck -Id 'prep/diff-shape' -Status 'WARN' `
        -Observed 'The working tree is clean; no release-preparation changes are staged yet.' `
        -Remediation "Run Set-TigerMarkViewReleaseVersion.ps1 -Version $Version and write the notes.")
}
else {
    Add-Check (New-TigerMarkViewReleaseAssertion -Id 'prep/diff-shape' `
        -Condition ($outside.Count -eq 0) `
        -PassObserved "The diff touches only release-preparation files ($($changedFiles.Count) file(s))." `
        -FailObserved ("The diff touches files outside release preparation: $($outside -join ', '). " +
            'Split unrelated changes into their own commit.') `
        -FailStatus 'WARN' -Evidence ($changedFiles -join ', '))
}

# --- Local WinGet preparation availability -------------------------------

Add-Check (New-TigerMarkViewReleaseAssertion -Id 'winget/prepare-script' `
    -Condition (Test-Path -LiteralPath (Join-Path $repositoryRoot 'eng/winget/Prepare-TigerMarkViewWinGet.ps1') -PathType Leaf) `
    -PassObserved 'The local WinGet preparation script is present.' `
    -FailObserved 'eng/winget/Prepare-TigerMarkViewWinGet.ps1 is missing.' `
    -Remediation 'Restore the WinGet preparation script.')

# --- Expensive gates -------------------------------------------------

if ($IncludeBuild) {
    $build = Invoke-Native dotnet @('build', 'TigerMarkView.slnx', '--configuration', 'Release',
        '-p:ContinuousIntegrationBuild=true', '-m:1', '/nodeReuse:false')
    Add-Check (New-TigerMarkViewReleaseAssertion -Id 'build/release' `
        -Condition ($build.ExitCode -eq 0) `
        -PassObserved 'dotnet build (Release, warnings as errors) succeeded.' `
        -FailObserved "dotnet build failed (exit $($build.ExitCode)). See the build log." `
        -Evidence '')
    if ($build.ExitCode -eq 0) {
        $test = Invoke-Native dotnet @('test', 'TigerMarkView.slnx', '--configuration', 'Release',
            '--no-build', '-m:1', '/nodeReuse:false')
        Add-Check (New-TigerMarkViewReleaseAssertion -Id 'test/release' `
            -Condition ($test.ExitCode -eq 0) `
            -PassObserved 'dotnet test (Release) passed.' `
            -FailObserved "dotnet test failed (exit $($test.ExitCode)).")
    }
}
else {
    Add-Check (New-TigerMarkViewReleaseCheck -Id 'build/release' -Status 'WARN' `
        -Observed 'NOT RUN: pass -IncludeBuild or -Full to run dotnet build and test.')
}

if ($IncludeInstaller) {
    $installer = Invoke-Native pwsh @('-NoProfile', '-File',
        (Join-Path $repositoryRoot 'installer/Build-Installer.ps1'), '-Configuration', 'Release')
    Add-Check (New-TigerMarkViewReleaseAssertion -Id 'installer/build' `
        -Condition ($installer.ExitCode -eq 0) `
        -PassObserved 'installer/Build-Installer.ps1 produced the win-x64 installer.' `
        -FailObserved "installer/Build-Installer.ps1 failed (exit $($installer.ExitCode)).")
}
else {
    Add-Check (New-TigerMarkViewReleaseCheck -Id 'installer/build' -Status 'WARN' `
        -Observed 'NOT RUN: pass -IncludeInstaller or -Full to build and assert the installer.')
}

if ($IncludeLab) {
    $lab = Invoke-Native pwsh @('-NoProfile', '-File',
        (Join-Path $repositoryRoot 'eng/lab/Test-TigerMarkViewRelease.ps1'))
    Add-Check (New-TigerMarkViewReleaseAssertion -Id 'lab/release' `
        -Condition ($lab.ExitCode -eq 0) `
        -PassObserved 'TigerWinLab release scenarios passed.' `
        -FailObserved "TigerWinLab release scenarios failed (exit $($lab.ExitCode)).")
}
else {
    Add-Check (New-TigerMarkViewReleaseCheck -Id 'lab/release' -Status 'WARN' `
        -Observed 'NOT RUN: pass -IncludeLab or -Full to run the TigerWinLab release scenarios.')
}

# --- Report and handoff -------------------------------------------

$handoff = @(
    'Review the prepared release changes (git diff).'
    'Commit the complete release preparation and push it to main.'
    "Wait for the CI run on that commit to conclude success, then manually dispatch '$($constant.releaseWorkflowName)' for $Version."
)
$report = New-TigerMarkViewReleaseReport -Title "Release readiness for TigerMarkView $Version" `
    -Checks $checks.ToArray() -Handoff $handoff `
    -NextCommand "gh run watch  # after pushing; then Actions -> $($constant.releaseWorkflowName) -> Run workflow ($Version)" `
    -Context @{ version = $Version; branch = $branch }

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    (Format-TigerMarkViewReleaseSummary -Report $report -Markdown) |
        Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
}

if ($Json) {
    $report | ConvertTo-Json -Depth 12
}
else {
    foreach ($line in (Format-TigerMarkViewReleaseSummary -Report $report)) { Write-Host $line }
}

exit $report.exitCode
