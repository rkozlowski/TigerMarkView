#Requires -Version 7.0
<#
    .SYNOPSIS
    Covers the shared result vocabulary and GitHub state queries in
    eng/release-automation/ReleaseAutomation.ps1.

    .DESCRIPTION
    Every GitHub read is exercised through a fake `gh` invoker that returns the
    shapes the real endpoints return; only the transport is replaced. No test
    here needs a network, a token, or a live repository.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$automationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $automationRoot)
. (Join-Path $automationRoot 'ReleaseAutomation.ps1')

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if (-not $Condition) { throw $Message }
}

# A fake `gh`: maps an argument signature to a canned {ExitCode, StdOut, StdErr}.
# 'api' routes match the API path (gh api -H Accept:... <path>); other routes
# match on the joined argument list.
function New-FakeGh {
    param(
        [Parameter(Mandatory)]
        [hashtable] $Routes
    )

    New-TigerMarkViewGitHubCli -Invoker {
        param([string[]] $GhArgs)

        $key = $null
        if ($GhArgs.Count -ge 4 -and $GhArgs[0] -ceq 'api') {
            $key = "api $($GhArgs[3])"
        }
        else {
            $key = ($GhArgs -join ' ')
        }

        foreach ($route in $Routes.Keys) {
            if ($key -like $route) {
                $value = $Routes[$route]
                if ($value -is [scriptblock]) { return & $value $GhArgs }
                return $value
            }
        }
        [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = "fake gh: no route for '$key'" }
    }.GetNewClosure()
}

function New-GhOk {
    param([Parameter(Mandatory)] $Object)
    [pscustomobject]@{ ExitCode = 0; StdOut = ($Object | ConvertTo-Json -Depth 12); StdErr = '' }
}

function New-GhFail {
    param([string] $StdErr = 'HTTP 404')
    [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = $StdErr }
}

$commit = 'a' * 40
$otherCommit = 'b' * 40
$repository = (Get-TigerMarkViewReleaseConstant).repository

try {
    # --- Constants -----------------------------------------------------------

    $constant = Get-TigerMarkViewReleaseConstant
    Assert-True ($constant.repository -ceq 'rkozlowski/TigerMarkView') 'The repository constant is fixed.'
    Assert-True ((& $constant.releaseAssetName '1.2.3') -ceq 'TigerMarkView-1.2.3-win-x64-setup.exe') `
        'The installer asset name is a function of the version.'
    Assert-True ((& $constant.releaseNotesPath '1.2.3') -ceq '.github/release-notes/1.2.3.md') `
        'The release-notes path is a function of the version.'
    Assert-True (Test-TigerMarkViewReleaseVersion -Version '0.9.0') 'A three-part version is valid.'
    Assert-True (-not (Test-TigerMarkViewReleaseVersion -Version 'v0.9')) 'A malformed version is rejected.'
    Write-Host 'PASS: release constants and version validation'

    # --- Verdict precedence and exit codes ---------------------------------

    $pass = New-TigerMarkViewReleaseCheck -Id 't/pass' -Status 'PASS' -Observed 'ok'
    $warn = New-TigerMarkViewReleaseCheck -Id 't/warn' -Status 'WARN' -Observed 'note'
    $blocked = New-TigerMarkViewReleaseCheck -Id 't/blocked' -Status 'BLOCKED' -Observed 'waiting'
    $fail = New-TigerMarkViewReleaseCheck -Id 't/fail' -Status 'FAIL' -Observed 'bad'

    Assert-True ((Get-TigerMarkViewReleaseVerdict -Checks @()).status -ceq 'FAIL') `
        'An empty check list proves nothing and is FAIL.'
    Assert-True ((Get-TigerMarkViewReleaseVerdict -Checks @($pass, $warn)).status -ceq 'WARN') `
        'A warning with no failure is WARN.'
    Assert-True ((Get-TigerMarkViewReleaseVerdict -Checks @($pass, $warn, $blocked)).status -ceq 'BLOCKED') `
        'A blocked check outranks a warning.'
    Assert-True ((Get-TigerMarkViewReleaseVerdict -Checks @($pass, $blocked, $fail)).status -ceq 'FAIL') `
        'A failure outranks a blocked check.'
    Assert-True ((Get-TigerMarkViewReleaseVerdict -Checks @($pass, $pass)).status -ceq 'PASS') `
        'All PASS is PASS.'
    Assert-True ((Get-TigerMarkViewReleaseVerdict -Checks @($pass) -Handoff @('do a thing')).status `
            -ceq 'READY FOR HUMAN ACTION') `
        'A clean run with a handoff is READY FOR HUMAN ACTION.'
    Assert-True ((Get-TigerMarkViewReleaseVerdict -Checks @($pass, $blocked) -Handoff @('x')).status `
            -ceq 'BLOCKED') `
        'A handoff never masks a blocked check.'

    Assert-True ((Get-TigerMarkViewReleaseExitCode -Status 'PASS') -eq 0) 'PASS exits 0.'
    Assert-True ((Get-TigerMarkViewReleaseExitCode -Status 'WARN') -eq 0) 'WARN exits 0.'
    Assert-True ((Get-TigerMarkViewReleaseExitCode -Status 'READY FOR HUMAN ACTION') -eq 0) `
        'READY FOR HUMAN ACTION exits 0.'
    Assert-True ((Get-TigerMarkViewReleaseExitCode -Status 'BLOCKED') -eq 2) 'BLOCKED exits 2.'
    Assert-True ((Get-TigerMarkViewReleaseExitCode -Status 'FAIL') -eq 1) 'FAIL exits 1.'
    Write-Host 'PASS: verdict precedence and exit-code mapping'

    # --- Report rendering: one object, two renderings ---------------------

    $report = New-TigerMarkViewReleaseReport -Title 'Test report' -Checks @($pass, $warn) `
        -Handoff @('Review the diff.', 'Commit and push main.') -NextCommand 'gh run watch'
    Assert-True ($report.status -ceq 'READY FOR HUMAN ACTION') 'The report reflects the verdict.'
    Assert-True ($report.exitCode -eq 0) 'The report carries the exit code for its status.'
    $text = (Format-TigerMarkViewReleaseSummary -Report $report) -join "`n"
    Assert-True ($text -match 'READY FOR HUMAN ACTION') 'The text summary shows the handoff banner.'
    Assert-True ($text -match '1\. Review the diff\.') 'The text summary numbers the handoff actions.'
    Assert-True ($text -match 'Then:\s*\n\s*gh run watch') 'The text summary prints the next command.'
    $markdown = (Format-TigerMarkViewReleaseSummary -Report $report -Markdown) -join "`n"
    Assert-True ($markdown -match '\| Check \| Status \| Observed \|') 'The markdown summary is a table.'
    $roundTrip = $report | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    Assert-True ($roundTrip.status -ceq $report.status) 'The report serialises to JSON without losing its status.'
    Write-Host 'PASS: a report renders identically to text, markdown, and JSON'

    # --- gh session preflight -------------------------------------------

    $goodSession = New-FakeGh -Routes @{
        'auth status'      = [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = 'Logged in to github.com account octocat' }
        'api user'         = (New-GhOk ([pscustomobject]@{ login = 'octocat' }))
        "api repos/$repository/actions/permissions" = (New-GhOk ([pscustomobject]@{ enabled = $true }))
    }
    $sessionChecks = Test-TigerMarkViewGitHubCliSession -Cli $goodSession -Repository $repository
    Assert-True (@($sessionChecks | Where-Object { $_.status -cne 'PASS' }).Count -eq 0) `
        'A healthy gh session passes every preflight check.'
    Assert-True (@($sessionChecks | Where-Object { $_.id -ceq 'gh/viewer' }).observed -match 'octocat') `
        'The viewer check names the authenticated account.'

    $unauthenticated = New-FakeGh -Routes @{
        'auth status' = [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'You are not logged into any GitHub hosts.' }
    }
    $unauthChecks = Test-TigerMarkViewGitHubCliSession -Cli $unauthenticated -Repository $repository
    $authCheck = @($unauthChecks | Where-Object { $_.id -ceq 'gh/auth-status' })[0]
    Assert-True ($authCheck.status -ceq 'BLOCKED') 'No session is BLOCKED, not FAIL.'
    Assert-True ($authCheck.remediation -match 'gh auth login') 'Repair is directed to gh auth login.'

    $wrongAccount = New-FakeGh -Routes @{
        'auth status' = [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = 'Logged in' }
        'api user'    = (New-GhOk ([pscustomobject]@{ login = 'someone-else' }))
        "api repos/$repository/actions/permissions" = (New-GhFail 'HTTP 403')
    }
    $wrongChecks = Test-TigerMarkViewGitHubCliSession -Cli $wrongAccount -Repository $repository
    Assert-True (@($wrongChecks | Where-Object { $_.id -ceq 'gh/actions-read' }).status -ceq 'BLOCKED') `
        'An account that cannot read Actions is BLOCKED.'

    $sourceText = Get-Content -LiteralPath (Join-Path $automationRoot 'ReleaseAutomation.ps1') -Raw
    Assert-True (-not ($sourceText -match 'GH_TOKEN|GITHUB_TOKEN|auth token|-GitHubToken')) `
        'The module never reads, forwards, or logs a token.'
    Write-Host 'PASS: gh preflight distinguishes missing, unauthenticated, and unauthorized sessions'

    # --- Workflow run selection for an exact commit ---------------------

    function New-RunsResponse {
        param([object[]] $Runs)
        New-GhOk ([pscustomobject]@{ total_count = $Runs.Count; workflow_runs = $Runs })
    }
    function New-Run {
        param(
            [string] $Sha = $commit,
            [string] $Status = 'completed',
            [string] $Conclusion = 'success',
            [string] $Event = 'push',
            [string] $Branch = 'main',
            [long] $RunNumber = 10
        )
        [pscustomobject]@{
            id = 1000 + $RunNumber
            run_number = $RunNumber
            status = $Status
            conclusion = $Conclusion
            event = $Event
            head_branch = $Branch
            head_sha = $Sha
            html_url = "https://github.com/$repository/actions/runs/$(1000 + $RunNumber)"
        }
    }

    $ciRoute = "api repos/$repository/actions/workflows/ci.yml/runs*"

    $noRun = New-FakeGh -Routes @{ $ciRoute = (New-RunsResponse @()) }
    $r = Get-TigerMarkViewWorkflowRunForCommit -Cli $noRun -CommitSha $commit -Repository $repository
    Assert-True ($r.check.status -ceq 'BLOCKED') 'No run yet is BLOCKED.'

    $inProgress = New-FakeGh -Routes @{ $ciRoute = (New-RunsResponse @((New-Run -Status 'in_progress' -Conclusion ''))) }
    $r = Get-TigerMarkViewWorkflowRunForCommit -Cli $inProgress -CommitSha $commit -Repository $repository
    Assert-True ($r.check.status -ceq 'BLOCKED') 'A still-running run is BLOCKED.'

    $failed = New-FakeGh -Routes @{ $ciRoute = (New-RunsResponse @((New-Run -Conclusion 'failure'))) }
    $r = Get-TigerMarkViewWorkflowRunForCommit -Cli $failed -CommitSha $commit -Repository $repository
    Assert-True ($r.check.status -ceq 'FAIL') 'A failed run is FAIL.'

    $prOnly = New-FakeGh -Routes @{ $ciRoute = (New-RunsResponse @((New-Run -Event 'pull_request'))) }
    $r = Get-TigerMarkViewWorkflowRunForCommit -Cli $prOnly -CommitSha $commit -Repository $repository
    Assert-True ($r.check.status -ceq 'BLOCKED') 'A green pull_request run does not satisfy the push gate.'

    $wrongBranch = New-FakeGh -Routes @{ $ciRoute = (New-RunsResponse @((New-Run -Branch 'topic'))) }
    $r = Get-TigerMarkViewWorkflowRunForCommit -Cli $wrongBranch -CommitSha $commit -Repository $repository
    Assert-True ($r.check.status -ceq 'BLOCKED') 'A run on another branch does not count.'

    $wrongSha = New-FakeGh -Routes @{ $ciRoute = (New-RunsResponse @((New-Run -Sha $otherCommit))) }
    $r = Get-TigerMarkViewWorkflowRunForCommit -Cli $wrongSha -CommitSha $commit -Repository $repository
    Assert-True ($r.check.status -ceq 'BLOCKED') 'A run for a different commit does not count.'

    $duplicates = New-FakeGh -Routes @{
        $ciRoute = (New-RunsResponse @(
            (New-Run -RunNumber 7 -Conclusion 'failure'),
            (New-Run -RunNumber 9 -Conclusion 'success')))
    }
    $r = Get-TigerMarkViewWorkflowRunForCommit -Cli $duplicates -CommitSha $commit -Repository $repository
    Assert-True ($r.check.status -ceq 'PASS' -and $r.run.runNumber -eq 9) `
        'The most recent run for the commit is selected, and a later success is a PASS.'
    Assert-True ($r.run.candidates -eq 2) 'The run info records how many candidates matched.'
    Write-Host 'PASS: workflow-run selection is by exact commit, push event, and default branch'

    # --- Tag dereference ---------------------------------------------------

    $version = '0.9.0'
    $annotatedSha = 'c' * 40
    $annotatedTag = New-FakeGh -Routes @{
        "api repos/$repository/git/ref/tags/v$version" =
            (New-GhOk ([pscustomobject]@{ object = [pscustomobject]@{ sha = $annotatedSha; type = 'tag' } }))
        "api repos/$repository/git/tags/$annotatedSha" =
            (New-GhOk ([pscustomobject]@{ object = [pscustomobject]@{ sha = $commit; type = 'commit' } }))
    }
    $t = Resolve-TigerMarkViewReleaseTagCommit -Cli $annotatedTag -Version $version -Repository $repository
    Assert-True ($t.check.status -ceq 'PASS' -and $t.commit -ceq $commit) `
        'An annotated tag is dereferenced to its commit.'

    $lightweightTag = New-FakeGh -Routes @{
        "api repos/$repository/git/ref/tags/v$version" =
            (New-GhOk ([pscustomobject]@{ object = [pscustomobject]@{ sha = $commit; type = 'commit' } }))
    }
    $t = Resolve-TigerMarkViewReleaseTagCommit -Cli $lightweightTag -Version $version -Repository $repository
    Assert-True ($t.commit -ceq $commit) 'A lightweight tag resolves directly.'

    $noTag = New-FakeGh -Routes @{ "api repos/$repository/git/ref/tags/v$version" = (New-GhFail) }
    $t = Resolve-TigerMarkViewReleaseTagCommit -Cli $noTag -Version $version -Repository $repository
    Assert-True ($t.check.status -ceq 'BLOCKED' -and $null -eq $t.commit) 'An absent tag is BLOCKED.'
    Write-Host 'PASS: release-tag resolution dereferences annotated tags'

    # --- Published release state ---------------------------------------

    function New-ReleaseResponse {
        param(
            [bool] $Draft = $false,
            [string] $Target = $commit,
            [string[]] $Assets = @(
                "TigerMarkView-$version-win-x64-setup.exe", 'SHA256SUMS.txt', 'release-artifacts.json')
        )
        New-GhOk ([pscustomobject]@{
            name = "TigerMarkView $version"
            draft = $Draft
            target_commitish = $Target
            published_at = '2026-08-30T10:00:00Z'
            html_url = "https://github.com/$repository/releases/tag/v$version"
            assets = @($Assets | ForEach-Object { [pscustomobject]@{ name = $_ } })
        })
    }
    $releaseRoute = "api repos/$repository/releases/tags/v$version"

    $missingRelease = New-FakeGh -Routes @{ $releaseRoute = (New-GhFail) }
    $state = Get-TigerMarkViewReleaseState -Cli $missingRelease -Version $version -ExpectedCommit $commit -Repository $repository
    Assert-True (@($state.checks | Where-Object { $_.id -ceq 'release/exists' }).status -ceq 'BLOCKED') `
        'A missing release is BLOCKED.'

    $draftRelease = New-FakeGh -Routes @{ $releaseRoute = (New-ReleaseResponse -Draft $true) }
    $state = Get-TigerMarkViewReleaseState -Cli $draftRelease -Version $version -ExpectedCommit $commit -Repository $repository
    Assert-True (@($state.checks | Where-Object { $_.id -ceq 'release/published' }).status -ceq 'BLOCKED') `
        'A draft release is BLOCKED, and automation must not publish it.'

    $wrongCommitRelease = New-FakeGh -Routes @{ $releaseRoute = (New-ReleaseResponse -Target $otherCommit) }
    $state = Get-TigerMarkViewReleaseState -Cli $wrongCommitRelease -Version $version -ExpectedCommit $commit -Repository $repository
    Assert-True (@($state.checks | Where-Object { $_.id -ceq 'release/commit' }).status -ceq 'FAIL') `
        'A release at the wrong commit is FAIL.'

    $extraAssetRelease = New-FakeGh -Routes @{
        $releaseRoute = (New-ReleaseResponse -Assets @(
            "TigerMarkView-$version-win-x64-setup.exe", 'SHA256SUMS.txt', 'release-artifacts.json',
            'ItTiger.TigerMarkView.installer.yaml'))
    }
    $state = Get-TigerMarkViewReleaseState -Cli $extraAssetRelease -Version $version -ExpectedCommit $commit -Repository $repository
    Assert-True (@($state.checks | Where-Object { $_.id -ceq 'release/assets' }).status -ceq 'FAIL') `
        'An unexpected package asset on the release is FAIL.'

    $goodRelease = New-FakeGh -Routes @{ $releaseRoute = (New-ReleaseResponse) }
    $state = Get-TigerMarkViewReleaseState -Cli $goodRelease -Version $version -ExpectedCommit $commit -Repository $repository
    Assert-True (@($state.checks | Where-Object { $_.status -cne 'PASS' }).Count -eq 0) `
        'A published non-draft release at the expected commit with the three assets passes.'
    Assert-True ($state.release.isDraft -eq $false -and $state.release.assetNames.Count -eq 3) `
        'The release info records the observed shape.'
    Write-Host 'PASS: release-state checks separate missing, draft, wrong-commit, and wrong-asset releases'

    Write-Host
    Write-Host 'PASS: release automation foundation' -ForegroundColor Green
}
catch {
    Write-Host
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
