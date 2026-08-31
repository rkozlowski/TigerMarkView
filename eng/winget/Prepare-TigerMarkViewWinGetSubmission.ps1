#Requires -Version 7.0
<#
    .SYNOPSIS
    The one post-release command: verifies a published TigerMarkView release end to
    end and leaves a pushed winget-pkgs submission branch, ready for a human to open
    the pull request.

    .DESCRIPTION
    Run this after the GitHub Release for <version> has been published. When it ends
    in PASS the only remaining action is creating and reviewing the
    microsoft/winget-pkgs pull request: there is no manual file copy, hash lookup,
    fork synchronization, branch creation, `git add`, commit, or push left to do.

    Work is ordered cheap-and-fundamental first, and nothing writes until every
    practical check has passed:

      1. an authenticated `gh` session that can read this repository's Actions;
      2. this checkout really is TigerMarkView;
      3. v<version> resolves to a commit, dereferencing the annotated tag;
      4. the CI push run for that exact commit concluded success;
      5. the Release TigerMarkView run for that exact commit concluded success;
      6. the release is published, non-draft, at that commit, with its three assets;
      7. the sealed submission set, the public installer, byte-for-byte regeneration,
         `winget validate`, and the full TigerWinLab install/uninstall scenario;
      8. the dedicated clone's identity, cleanliness, and operation state, and the
         previous TigerMarkView winget-pkgs pull request; then
      9. fork synchronization, branch, exact copy, destination validation, final
         diff, commit, and push - each of which recognises already-correct state and
         stops on conflicting state rather than overwriting it.

    Every stage after a human checkpoint proves that checkpoint happened. A missing
    publication, a green run for the wrong commit, an expired artifact, or an
    unexpected repository is BLOCKED or FAIL, never a guess.

    Nothing here publishes a release or opens a pull request. Those two decisions
    stay with the human.

    GitHub is reached only through the session `gh auth login` established. No token
    is accepted, read from the environment, or logged.

    .PARAMETER Version
    The published release version to submit. Defaults to Version.props.

    .PARAMETER ClonePath
    An explicit dedicated-clone path, overriding the configured one in
    eng/winget/winget-pkgs.clone.json. A maintainer decision rather than a guess, so
    it wins - and it is validated identically.

    .PARAMETER PlanOnly
    Runs every read-only gate and stops before any synchronization, branch, copy,
    commit, or push. It can report BLOCKED or FAIL, but it can never report a
    submission PASS or hand off a pull request, because it prepares nothing.

    .PARAMETER Refresh
    Re-downloads the sealed workflow artifact even when a retained, provenance-bound
    copy already matches everything GitHub records for it.

    .PARAMETER TigerWinLabRoot
    An explicit TigerWinLab working copy. Omit it and the lab is resolved from the
    TigerAiCore configuration named by TigerAiCoreConfig.

    .EXAMPLE
    .\eng\winget\Prepare-TigerMarkViewWinGetSubmission.ps1 -Version 0.8.1
#>
[CmdletBinding()]
param(
    [string] $Version,
    [string] $ClonePath,
    [string] $TigerWinLabRoot,
    [string] $WinGetPath,
    [ValidateRange(1, 240)]
    [int] $TimeoutMinutes = 45,
    [switch] $Refresh,
    [switch] $PlanOnly,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'WinGetReleaseValidation.ps1')
. (Join-Path $PSScriptRoot 'WinGetPkgsSubmission.ps1')

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$constant = Get-TigerMarkViewReleaseConstant
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string] (Get-TigerMarkViewWinGetVersionProperty -RepositoryRoot $repositoryRoot).Version
}

$checks = [Collections.Generic.List[object]]::new()
$context = [ordered]@{ version = $Version; planOnly = [bool] $PlanOnly }
$submissionState = $null

function Add-Check { param($Check) $script:checks.Add($Check) }

function Test-Blocking {
    @($script:checks | Where-Object { $_.status -ceq 'FAIL' -or $_.status -ceq 'BLOCKED' }).Count -gt 0
}

function Write-Report {
    param([string[]] $Handoff = @(), [string] $NextCommand = '')

    $report = New-TigerMarkViewReleaseReport `
        -Title "TigerMarkView $Version winget-pkgs submission" `
        -Checks $script:checks.ToArray() -Handoff $Handoff -NextCommand $NextCommand `
        -Context $script:context

    if ($Json) {
        [pscustomobject][ordered]@{
            report = $report
            submission = $script:submissionState
        } | ConvertTo-Json -Depth 14
    }
    else {
        foreach ($line in (Format-TigerMarkViewReleaseSummary -Report $report)) { Write-Host $line }
    }
    exit $report.exitCode
}

if (-not (Test-TigerMarkViewReleaseVersion -Version $Version)) {
    Add-Check (New-TigerMarkViewReleaseCheck -Id 'input/version' -Status 'FAIL' `
        -Observed "'$Version' is not a valid release version." `
        -Remediation 'Pass -Version <major>.<minor>.<patch>.')
    Write-Report
}

# --- 1. The authenticated session -------------------------------------------

$cli = $null
try { $cli = New-TigerMarkViewGitHubCli }
catch {
    Add-Check (New-TigerMarkViewReleaseCheck -Id 'gh/available' -Status 'BLOCKED' `
        -Observed $_.Exception.Message `
        -Remediation 'Install the GitHub CLI and run "gh auth login".')
    Write-Report
}
foreach ($check in (Test-TigerMarkViewGitHubCliSession -Cli $cli -Repository $constant.repository)) {
    Add-Check $check
}
if (Test-Blocking) { Write-Report }

# --- 2. This checkout is TigerMarkView ---------------------------------------

$originUrl = (Invoke-TigerCloneGit -ClonePath $repositoryRoot -GitArgs @('remote', 'get-url', 'origin')).Output
Add-Check (New-TigerMarkViewReleaseAssertion -Id 'repo/origin' `
    -Condition (Test-TigerGitHubSlugMatch -Url $originUrl -ExpectedSlug $constant.repository) `
    -PassObserved "This checkout's origin is $($constant.repository)." `
    -FailObserved "This checkout's origin is '$originUrl', not $($constant.repository)." `
    -Evidence $originUrl `
    -Remediation "Run the submission command from a clone of $($constant.repositoryUrl).")
if (Test-Blocking) { Write-Report }

# --- 3-5. The tag, the CI run, and the release run for that exact commit ------

$tag = Resolve-TigerMarkViewReleaseTagCommit -Cli $cli -Version $Version
Add-Check $tag.check
if (Test-Blocking) { Write-Report }
$context.commit = $tag.commit
$context.tag = $tag.tag

$ci = Get-TigerMarkViewWorkflowRunForCommit -Cli $cli -CommitSha $tag.commit `
    -WorkflowFile $constant.ciWorkflowFile -Event 'push' -Branch $constant.defaultBranch -CheckId 'ci/run'
Add-Check $ci.check

$releaseRun = Get-TigerMarkViewWorkflowRunForCommit -Cli $cli -CommitSha $tag.commit `
    -WorkflowFile $constant.releaseWorkflowFile -Event 'workflow_dispatch' `
    -Branch $constant.defaultBranch -CheckId 'release/run'
Add-Check $releaseRun.check
if (Test-Blocking) { Write-Report }
$context.releaseRunUrl = $releaseRun.run.url

# --- 6. The published release ------------------------------------------------

$releaseState = Get-TigerMarkViewReleaseState -Cli $cli -Version $Version -ExpectedCommit $tag.commit `
    -Repository $constant.repository
foreach ($check in $releaseState.checks) { Add-Check $check }
if (Test-Blocking) { Write-Report }
$context.releaseUrl = $releaseState.release.htmlUrl

# --- 7. The sealed set, the public installer, winget validate, and the lab ----

$client = New-TigerMarkViewGitHubClient -Cli $cli -RepositoryUrl $constant.repositoryUrl
$validation = Invoke-TigerMarkViewWinGetReleaseValidation `
    -RepositoryRoot $repositoryRoot `
    -Version $Version `
    -Client $client `
    -TigerWinLabRoot $TigerWinLabRoot `
    -WinGetPath $WinGetPath `
    -TimeoutMinutes $TimeoutMinutes `
    -Refresh:$Refresh
foreach ($check in @($validation.report.checks)) { Add-Check $check }
if (Test-Blocking) { Write-Report }
$context.submissionDigest = $validation.submission.digest
$context.validationResult = $validation.resultPath

# --- 8-9. The dedicated clone, the previous-PR gate, and the guarded mutation --

$cloneConfig = $null
try { $cloneConfig = Get-TigerWinGetPkgsCloneConfig -RepositoryRoot $repositoryRoot -ClonePath $ClonePath }
catch {
    Add-Check (New-TigerMarkViewReleaseCheck -Id 'clone/config' -Status 'FAIL' `
        -Observed $_.Exception.Message `
        -Remediation 'Correct eng/winget/winget-pkgs.clone.json, or pass an explicit -ClonePath.')
    Write-Report
}
Add-Check (New-TigerMarkViewReleaseCheck -Id 'clone/config' -Status 'PASS' `
    -Observed "The dedicated clone is $($cloneConfig.clonePath), from $($cloneConfig.clonePathSource)." `
    -Evidence $cloneConfig.configPath)
$context.clonePath = $cloneConfig.clonePath

$submission = Invoke-TigerWinGetPkgsSubmission -Cli $cli -Config $cloneConfig -Version $Version `
    -Submission $validation.submission -PlanOnly:$PlanOnly
foreach ($check in $submission.checks) { Add-Check $check }
$submissionState = $submission.state
$context.branch = $submission.state.branch
if (Test-Blocking) { Write-Report }

# --- The one remaining human action -----------------------------------------

Write-Report -Handoff @(
    ("Create the pull request to $($cloneConfig.upstreamSlug) from " +
        "$($cloneConfig.forkOwner):$($submission.state.branch) (commit $($submission.state.commitSha)).")
    'Review its diff: it must add only the three manifests under ' +
        "$($cloneConfig.manifestPath)/$Version."
    'Nothing else remains. The release is published, the sealed manifests are pushed, and no ' +
        'further local step is required.'
) -NextCommand $submission.state.pullRequestCommand
