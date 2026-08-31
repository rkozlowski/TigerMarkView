#Requires -Version 7.0
<#
    .SYNOPSIS
    Proves the release commit is on origin/main and its exact CI push run
    succeeded, before the release workflow builds or tags anything.

    .DESCRIPTION
    This is the prerequisite gate. It never infers a human push from a nearby
    commit or a green pull-request run: it fetches origin/main and asks git
    whether the dispatched commit is reachable from it, then asks GitHub for the
    `CI` push run for that exact SHA on the default branch and requires
    status=completed, conclusion=success.

    It also confirms the dispatched version matches Version.props and that
    .github/release-notes/<version>.md is present and useful, so the workflow
    stops at this cheap gate rather than after a full build.

    GitHub is reached only through the authenticated `gh` session. In GitHub
    Actions that session is the job's scoped GITHUB_TOKEN, delivered as GH_TOKEN;
    the job needs `actions: read` and `contents: read` and nothing more.

    Exit codes: 0 = PASS, 2 = BLOCKED (a human/external step is incomplete),
    1 = FAIL (a check found invalid data).

    .PARAMETER Version
    The dispatched release version.

    .PARAMETER CommitSha
    The dispatched commit (full 40-character SHA).

    .PARAMETER Repository
    owner/name. Defaults to the release constant.

    .PARAMETER StepSummaryPath
    A file to append a Markdown summary to. Defaults to $env:GITHUB_STEP_SUMMARY.

    .PARAMETER Json
    Emit the machine-readable report instead of the rendered summary.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Version,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $CommitSha,

    [string] $Repository,

    [string] $StepSummaryPath,

    [switch] $Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ReleaseAutomation.ps1')

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$constant = Get-TigerMarkViewReleaseConstant
if ([string]::IsNullOrWhiteSpace($Repository)) { $Repository = $constant.repository }
if ([string]::IsNullOrWhiteSpace($StepSummaryPath)) { $StepSummaryPath = $env:GITHUB_STEP_SUMMARY }
$commit = $CommitSha.ToLowerInvariant()

$checks = [Collections.Generic.List[object]]::new()

# 1. The dispatched version is exactly what the tree records.
$versionProps = Join-Path $repositoryRoot 'Version.props'
$configuredVersion = ''
try {
    [xml] $props = Get-Content -LiteralPath $versionProps -Raw
    $configuredVersion = [string] $props.Project.PropertyGroup.Version
}
catch {
    $configuredVersion = ''
}
$checks.Add((New-TigerMarkViewReleaseAssertion -Id 'version/matches-props' `
    -Condition ((Test-TigerMarkViewReleaseVersion -Version $Version) -and ($configuredVersion -ceq $Version)) `
    -PassObserved "Version.props records $Version." `
    -FailObserved "Dispatched version '$Version' does not match Version.props '$configuredVersion'." `
    -Expected $Version -Evidence $configuredVersion `
    -Remediation 'Dispatch the exact version recorded in Version.props on the release commit.'))

# 2. The release-notes source exists and is useful.
$checks.Add((Test-TigerMarkViewReleaseNotes -Version $Version -RepositoryRoot $repositoryRoot))

# 3. The dispatched commit is reachable from origin/main.
$checks.Add((Test-TigerMarkViewCommitOnMain -RepositoryRoot $repositoryRoot -CommitSha $commit `
    -Branch $constant.defaultBranch -Fetch))

# 4. The CI push run for that exact commit concluded success.
$cli = $null
try {
    $cli = New-TigerMarkViewGitHubCli
}
catch {
    $checks.Add((New-TigerMarkViewReleaseCheck -Id 'ci/run' -Status 'BLOCKED' `
        -Observed "GitHub CLI is unavailable: $($_.Exception.Message)" `
        -Remediation 'Install gh and authenticate, or provide GH_TOKEN in Actions.'))
}
if ($null -ne $cli) {
    foreach ($sessionCheck in (Test-TigerMarkViewGitHubCliSession -Cli $cli -Repository $Repository)) {
        # Only surface a session problem; a healthy session needs no line here.
        if ($sessionCheck.status -cne 'PASS') { $checks.Add($sessionCheck) }
    }
    if (@($checks | Where-Object { $_.id -like 'gh/*' -and $_.status -cne 'PASS' }).Count -eq 0) {
        $run = Get-TigerMarkViewWorkflowRunForCommit -Cli $cli -CommitSha $commit -Repository $Repository `
            -WorkflowFile $constant.ciWorkflowFile -Event 'push' -Branch $constant.defaultBranch -CheckId 'ci/run'
        $checks.Add($run.check)
    }
}

$nextCommand = "Manually dispatch '$($constant.releaseWorkflowName)' for $Version on $($constant.defaultBranch)."
$report = New-TigerMarkViewReleaseReport -Title "Release prerequisites for TigerMarkView $Version" `
    -Checks $checks.ToArray() `
    -Context @{ version = $Version; commit = $commit; repository = $Repository }

if ($report.status -ceq 'PASS') {
    # Fold the handoff in only when everything passed: the release build may proceed.
    $report = New-TigerMarkViewReleaseReport -Title "Release prerequisites for TigerMarkView $Version" `
        -Checks $checks.ToArray() `
        -Handoff @("Prerequisites satisfied. The release workflow will now build and validate $Version.") `
        -NextCommand $nextCommand `
        -Context @{ version = $Version; commit = $commit; repository = $Repository }
}

if (-not [string]::IsNullOrWhiteSpace($StepSummaryPath)) {
    (Format-TigerMarkViewReleaseSummary -Report $report -Markdown) |
        Out-File -FilePath $StepSummaryPath -Encoding utf8 -Append
}

if ($Json) {
    $report | ConvertTo-Json -Depth 12
}
else {
    foreach ($line in (Format-TigerMarkViewReleaseSummary -Report $report)) { Write-Host $line }
}

exit $report.exitCode
