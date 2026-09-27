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

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Action,

        [Parameter(Mandatory)]
        [string] $MessagePattern
    )

    try { & $Action }
    catch {
        Assert-True ($_.Exception.Message -match $MessagePattern) `
            "Expected failure matching '$MessagePattern'; received '$($_.Exception.Message)'."
        return
    }
    throw "Expected an exception matching '$MessagePattern'."
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
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('TigerReleaseAutomation-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

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

    # The release workflow's job token: gh sees a session, but it has no user and
    # no administration access, exactly as the 0.10.0 release run observed.
    $actionsTokenRoutes = @{
        'auth status' = [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = 'Logged in to github.com account github-actions[bot] (GH_TOKEN)' }
        'api user'    = (New-GhFail 'Resource not accessible by integration (HTTP 403)')
        "api repos/$repository/actions/permissions" = (New-GhFail 'Resource not accessible by integration (HTTP 403)')
    }
    $workflowChecks = Test-TigerMarkViewGitHubCliSession -Cli (New-FakeGh -Routes $actionsTokenRoutes) `
        -Repository $repository -GitHubSession Workflow
    Assert-True (@($workflowChecks | Where-Object { $_.status -cne 'PASS' }).Count -eq 0) `
        'A workflow job token passes the Workflow preflight without a user identity or administration access.'
    Assert-True (@($workflowChecks | Where-Object { $_.id -in @('gh/viewer', 'gh/actions-read') }).Count -eq 0) `
        'The Workflow preflight never asks a job token for a user or the Actions settings.'
    $maintainerChecks = Test-TigerMarkViewGitHubCliSession -Cli (New-FakeGh -Routes $actionsTokenRoutes) `
        -Repository $repository
    Assert-True (@($maintainerChecks | Where-Object { $_.status -ceq 'BLOCKED' }).id -join ',' -ceq 'gh/viewer,gh/actions-read') `
        'The default Maintainer preflight still demands a user identity and Actions read access.'

    $workflowUnauthenticated = Test-TigerMarkViewGitHubCliSession -Cli $unauthenticated `
        -Repository $repository -GitHubSession Workflow
    $workflowAuth = @($workflowUnauthenticated | Where-Object { $_.id -ceq 'gh/auth-status' })[0]
    Assert-True ($workflowAuth.status -ceq 'BLOCKED') 'A workflow step with no token for gh is BLOCKED.'
    Assert-True ($workflowAuth.remediation -match 'github\.token' -and $workflowAuth.remediation -notmatch 'gh auth login') `
        'Workflow repair points at the job token, never at an interactive login.'
    Assert-Throws { Test-TigerMarkViewGitHubCliSession -Cli $goodSession -GitHubSession 'Auto' } `
        -MessagePattern 'GitHubSession'
    Write-Host 'PASS: the session kind is explicit, and a workflow job token needs no user identity'

    $sourceText = Get-Content -LiteralPath (Join-Path $automationRoot 'ReleaseAutomation.ps1') -Raw
    Assert-True (-not ($sourceText -match 'GH_TOKEN|GITHUB_TOKEN|auth token|-GitHubToken')) `
        'The module never reads, forwards, or logs a token.'
    Write-Host 'PASS: gh preflight distinguishes missing, unauthenticated, and unauthorized sessions'

    # --- Binary download through the same session -----------------------

    # A workflow artifact is a zip, so it needs its own route: piping a native
    # command's output through PowerShell would decode it as text. The route still
    # goes through the one session, and still carries no token.
    $downloadRoot = Join-Path $testRoot 'download'
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    $downloadedArgs = $null
    $downloadingCli = New-TigerMarkViewGitHubCli -Invoker {
        param([string[]] $GhArgs)
        [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'not used' }
    } -Downloader {
        param([string[]] $GhArgs, [string] $OutFile)
        $script:downloadedArgs = $GhArgs
        [IO.File]::WriteAllBytes($OutFile, [byte[]] (1, 2, 3, 4))
        [pscustomobject]@{ ExitCode = 0; StdErr = '' }
    }
    $downloadTarget = Join-Path $downloadRoot 'artifact.zip'
    $returned = & $downloadingCli.downloadApi 'repos/o/n/actions/artifacts/7/zip' $downloadTarget
    Assert-True ($returned -ceq $downloadTarget) 'downloadApi returns the file it wrote.'
    Assert-True ([IO.File]::ReadAllBytes($downloadTarget).Length -eq 4) 'The response body reaches the file as raw bytes.'
    Assert-True ($script:downloadedArgs[0] -ceq 'api' -and
        $script:downloadedArgs[-1] -ceq 'repos/o/n/actions/artifacts/7/zip') `
        'The download goes through gh api with the requested path.'

    $failingDownload = New-TigerMarkViewGitHubCli -Invoker {
        param([string[]] $GhArgs)
        [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'not used' }
    } -Downloader {
        param([string[]] $GhArgs, [string] $OutFile)
        [IO.File]::WriteAllBytes($OutFile, [byte[]] (9))
        [pscustomobject]@{ ExitCode = 1; StdErr = 'HTTP 403' }
    }
    $partial = Join-Path $downloadRoot 'partial.zip'
    Assert-Throws -MessagePattern 'HTTP 403' -Action { & $failingDownload.downloadApi 'repos/o/n/x' $partial }
    Assert-True (-not (Test-Path -LiteralPath $partial)) 'A failed download leaves no partial file behind.'

    $noDownloadRoute = New-FakeGh -Routes @{ 'auth status' = [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' } }
    Assert-Throws -MessagePattern 'no -Downloader' -Action {
        & $noDownloadRoute.downloadApi 'repos/o/n/x' (Join-Path $downloadRoot 'never.zip')
    }
    Write-Host 'PASS: artifact downloads use the same session and never fall back to a real gh'

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

    # --- The release prerequisite gate, end to end ---------------------------

    # The gate script runs from a throwaway repository whose origin is a local bare
    # clone, so version, notes, and commit-on-main are real checks against real git
    # while GitHub is the fake job-token session above.
    function Invoke-FixtureGit {
        param([string] $Root, [string[]] $GitArgs)
        $previous = $PSNativeCommandUseErrorActionPreference
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            $out = (& git -C $Root @GitArgs 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
            $out.Trim()
        }
        finally { $PSNativeCommandUseErrorActionPreference = $previous; $global:LASTEXITCODE = 0 }
    }

    $gateVersion = '9.9.9'
    $gateOrigin = Join-Path $testRoot 'gate-origin.git'
    $gateRoot = Join-Path $testRoot 'gate'
    New-Item -ItemType Directory -Path $gateOrigin, (Join-Path $gateRoot 'eng/release-automation'), `
        (Join-Path $gateRoot '.github/release-notes') -Force | Out-Null
    Invoke-FixtureGit -Root $gateOrigin -GitArgs @('init', '--quiet', '--bare', '-b', 'main') | Out-Null
    foreach ($name in @('Assert-ReleaseCommitReady.ps1', 'ReleaseAutomation.ps1')) {
        Copy-Item -LiteralPath (Join-Path $automationRoot $name) -Destination (Join-Path $gateRoot 'eng/release-automation')
    }
    Set-Content -LiteralPath (Join-Path $gateRoot 'Version.props') -Encoding utf8NoBOM `
        -Value "<Project>`n  <PropertyGroup>`n    <Version>$gateVersion</Version>`n  </PropertyGroup>`n</Project>"
    Set-Content -LiteralPath (Join-Path $gateRoot ".github/release-notes/$gateVersion.md") -Encoding utf8NoBOM -Value @"
## Highlights

TigerMarkView $gateVersion improves how the viewer renders wide tables and adds a
running-head option to the tiger-mark command line for exported PDFs.

## Fixed

- The reload indicator no longer sticks after a file is deleted and recreated.
"@
    Invoke-FixtureGit -Root $gateRoot -GitArgs @('init', '--quiet', '-b', 'main') | Out-Null
    Invoke-FixtureGit -Root $gateRoot -GitArgs @('config', 'user.email', 'test@example.com') | Out-Null
    Invoke-FixtureGit -Root $gateRoot -GitArgs @('config', 'user.name', 'Test') | Out-Null
    Invoke-FixtureGit -Root $gateRoot -GitArgs @('add', '-A') | Out-Null
    Invoke-FixtureGit -Root $gateRoot -GitArgs @('commit', '--quiet', '-m', 'release fixture') | Out-Null
    Invoke-FixtureGit -Root $gateRoot -GitArgs @('remote', 'add', 'origin', $gateOrigin) | Out-Null
    Invoke-FixtureGit -Root $gateRoot -GitArgs @('push', '--quiet', 'origin', 'main') | Out-Null
    $gateCommit = Invoke-FixtureGit -Root $gateRoot -GitArgs @('rev-parse', 'HEAD')
    $gateScript = Join-Path $gateRoot 'eng/release-automation/Assert-ReleaseCommitReady.ps1'
    $gateSummary = Join-Path $testRoot 'gate-summary.md'

    function Invoke-Gate {
        param([object] $Cli, [string] $GitHubSession)
        # Omitting the session exercises the script's own default.
        $extra = @{}
        if ($GitHubSession) { $extra.GitHubSession = $GitHubSession }
        # The script ends with `exit`, which returns here and sets LASTEXITCODE.
        # An explicit summary path keeps a CI run's own step summary untouched.
        $json = & $gateScript -Version $gateVersion -CommitSha $gateCommit -Repository $repository `
            -StepSummaryPath $gateSummary -Json -GitHubCli $Cli @extra | Out-String
        $exitCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        [pscustomobject]@{ exitCode = $exitCode; report = ($json | ConvertFrom-Json) }
    }
    function Get-GateStatus {
        param([object] $Report, [string] $Id)
        $found = @($Report.checks | Where-Object { $_.id -ceq $Id })
        if ($found.Count -eq 0) { return '' }
        [string] $found[0].status
    }

    $jobTokenRoutes = @{} + $actionsTokenRoutes
    $jobTokenRoutes[$ciRoute] = (New-RunsResponse @((New-Run -Sha $gateCommit)))
    $jobTokenRoutes["api repos/$repository/git/ref/tags/v$gateVersion"] = (New-GhFail 'Not Found (HTTP 404)')

    $hosted = Invoke-Gate -Cli (New-FakeGh -Routes $jobTokenRoutes) -GitHubSession Workflow
    Assert-True ($hosted.exitCode -eq 0 -and $hosted.report.status -ceq 'READY FOR HUMAN ACTION') `
        "The hosted gate passes on a job token alone; got $($hosted.report.status): $(@($hosted.report.checks | ForEach-Object { "$($_.id)=$($_.status)" }) -join ', ')"
    foreach ($id in @('version/matches-props', 'release-notes/source', 'commit/on-main', 'ci/run', 'tag/available')) {
        Assert-True ((Get-GateStatus $hosted.report $id) -ceq 'PASS') "The hosted gate still proves '$id'."
    }
    Assert-True (@($hosted.report.checks | Where-Object { $_.id -like 'gh/*' }).Count -eq 0) `
        'A healthy hosted session adds no gh lines to the report.'
    Assert-True ((Get-Content -LiteralPath $gateSummary -Raw) -match 'ci/run') 'The hosted gate writes its step summary.'

    # The same job token without the explicit Workflow session reproduces the 0.10.0 failure.
    $asMaintainer = Invoke-Gate -Cli (New-FakeGh -Routes $jobTokenRoutes)
    Assert-True ($asMaintainer.exitCode -eq 2) 'A job token judged as a maintainer session is BLOCKED.'
    Assert-True ((Get-GateStatus $asMaintainer.report 'gh/viewer') -ceq 'BLOCKED' -and
        (Get-GateStatus $asMaintainer.report 'gh/actions-read') -ceq 'BLOCKED') `
        'Maintainer mode still requires a user identity and Actions read access.'
    Assert-True ([string]::IsNullOrEmpty((Get-GateStatus $asMaintainer.report 'ci/run'))) `
        'An unusable maintainer session stops before the GitHub queries.'

    $maintainerRoutes = @{} + $jobTokenRoutes
    $maintainerRoutes['api user'] = (New-GhOk ([pscustomobject]@{ login = 'octocat' }))
    $maintainerRoutes["api repos/$repository/actions/permissions"] = (New-GhOk ([pscustomobject]@{ enabled = $true }))
    $maintainerGate = Invoke-Gate -Cli (New-FakeGh -Routes $maintainerRoutes)
    Assert-True ($maintainerGate.exitCode -eq 0 -and $maintainerGate.report.status -ceq 'READY FOR HUMAN ACTION') 'A maintainer login passes the local gate.'

    $failedRoutes = @{} + $jobTokenRoutes
    $failedRoutes[$ciRoute] = (New-RunsResponse @((New-Run -Sha $gateCommit -Conclusion 'failure')))
    $failedCi = Invoke-Gate -Cli (New-FakeGh -Routes $failedRoutes) -GitHubSession Workflow
    Assert-True ($failedCi.exitCode -eq 1 -and (Get-GateStatus $failedCi.report 'ci/run') -ceq 'FAIL') `
        'The hosted gate still fails when the exact commit''s CI run failed.'

    $unreadableRoutes = @{} + $jobTokenRoutes
    $unreadableRoutes[$ciRoute] = (New-GhFail 'Resource not accessible by integration (HTTP 403)')
    $unreadable = Invoke-Gate -Cli (New-FakeGh -Routes $unreadableRoutes) -GitHubSession Workflow
    Assert-True ($unreadable.exitCode -eq 2 -and (Get-GateStatus $unreadable.report 'ci/run') -ceq 'BLOCKED') `
        'A job token that cannot read Actions blocks on the CI query itself.'

    $taggedRoutes = @{} + $jobTokenRoutes
    $taggedRoutes["api repos/$repository/git/ref/tags/v$gateVersion"] =
        (New-GhOk ([pscustomobject]@{ object = [pscustomobject]@{ sha = $gateCommit; type = 'commit' } }))
    $tagged = Invoke-Gate -Cli (New-FakeGh -Routes $taggedRoutes) -GitHubSession Workflow
    Assert-True ((Get-GateStatus $tagged.report 'tag/available') -ceq 'BLOCKED') `
        'The hosted gate still refuses a version whose tag already exists.'

    Invoke-FixtureGit -Root $gateRoot -GitArgs @('commit', '--quiet', '--allow-empty', '-m', 'not pushed') | Out-Null
    $gateCommit = Invoke-FixtureGit -Root $gateRoot -GitArgs @('rev-parse', 'HEAD')
    $offMainRoutes = @{} + $jobTokenRoutes
    $offMainRoutes[$ciRoute] = (New-RunsResponse @((New-Run -Sha $gateCommit)))
    $offMain = Invoke-Gate -Cli (New-FakeGh -Routes $offMainRoutes) -GitHubSession Workflow
    Assert-True ($offMain.exitCode -eq 2 -and (Get-GateStatus $offMain.report 'commit/on-main') -ceq 'BLOCKED') `
        'The hosted gate still refuses a commit that is not on origin/main.'
    Write-Host 'PASS: the release gate runs on a workflow job token and still proves version, notes, commit, CI, and tag'

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

    # --- Workflow script references -----------------------------------

    # A workflow step is only ever a call into a script here, so the one thing the
    # workflows can get wrong on their own is naming a script that is missing or
    # untracked. That is checked here rather than as a CI-only step.
    $workflowFiles = @(
        Join-Path $repositoryRoot '.github/workflows/ci.yml'
        Join-Path $repositoryRoot '.github/workflows/release.yml'
    )
    $referenced = [Collections.Generic.List[string]]::new()
    foreach ($workflowFile in $workflowFiles) {
        $text = Get-Content -LiteralPath $workflowFile -Raw
        foreach ($match in [regex]::Matches($text, '\./(?<path>(?:eng|installer)/[^\s''"]+\.ps1)')) {
            $path = $match.Groups['path'].Value
            if (-not $referenced.Contains($path)) { $referenced.Add($path) }
        }
    }
    Assert-True ($referenced.Count -ge 5) `
        "The workflows must call the release scripts; only $($referenced.Count) references were found."
    # Existence is the whole check, and it is a complete one: this suite also runs in
    # CI, where a checkout contains only committed files, so a script that was never
    # committed fails here rather than in the middle of a release. An ignored path
    # would pass locally and vanish in CI, so it is refused outright.
    foreach ($path in $referenced) {
        Assert-True (Test-Path -LiteralPath (Join-Path $repositoryRoot $path) -PathType Leaf) `
            "A workflow calls '$path', which does not exist in this checkout."
        $previousNative = $PSNativeCommandUseErrorActionPreference
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            & git -C $repositoryRoot check-ignore --quiet -- $path
            $ignored = $LASTEXITCODE -eq 0
        }
        finally {
            $PSNativeCommandUseErrorActionPreference = $previousNative
            $global:LASTEXITCODE = 0
        }
        Assert-True (-not $ignored) "A workflow calls '$path', which Git ignores and CI would never see."
    }
    Write-Host "PASS: every script the workflows call is present and committable ($($referenced.Count) scripts)"

    # --- Release artifact set ------------------------------------------

    # The release workflow no longer stages, copies, or hashes anything itself:
    # these two scripts close the artifact set and prove it, and the transfer
    # check is what makes "the same bytes" checkable across the artifact upload.
    $artifactVersion = '0.9.0'
    $artifactCommit = 'd' * 40
    $installerName = "TigerMarkView-$artifactVersion-win-x64-setup.exe"
    $buildRoot = Join-Path $testRoot 'build'
    $releaseRoot = Join-Path $testRoot 'release'
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    $builtInstaller = Join-Path $buildRoot $installerName
    [IO.File]::WriteAllBytes($builtInstaller, [byte[]] (1..64))

    # A leftover file from an earlier attempt must not survive into the set.
    New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $releaseRoot 'stale.txt') -Value 'left over' -Encoding utf8NoBOM

    $outputFile = Join-Path $testRoot 'artifact-output.txt'
    & (Join-Path $automationRoot 'New-ReleaseArtifactManifest.ps1') `
        -InstallerPath $builtInstaller `
        -ArtifactDirectory $releaseRoot `
        -Version $artifactVersion `
        -CommitSha $artifactCommit `
        -GitHubOutput $outputFile | Out-Null

    $releaseNames = @(Get-ChildItem -LiteralPath $releaseRoot -File | ForEach-Object Name | Sort-Object)
    $expectedNames = @(@('SHA256SUMS.txt', 'release-artifacts.json', $installerName) | Sort-Object)
    Assert-True (($releaseNames -join ',') -ceq ($expectedNames -join ',')) `
        "Staging must leave exactly the closed set; it left $($releaseNames -join ', ')."

    $recordedHash = @(Get-Content -LiteralPath $outputFile |
        Where-Object { $_ -match '^manifest_sha256=(?<hash>[0-9a-f]{64})$' } |
        ForEach-Object { $Matches['hash'] })
    Assert-True ($recordedHash.Count -eq 1) 'Closing the set must publish exactly one manifest_sha256.'

    & (Join-Path $automationRoot 'Assert-ReleaseArtifactManifest.ps1') `
        -ArtifactDirectory $releaseRoot `
        -ExpectedVersion $artifactVersion `
        -ExpectedCommit $artifactCommit `
        -ExpectedManifestSha256 $recordedHash[0] | Out-Null
    Write-Host 'PASS: the artifact set is staged, closed, and verified against its recorded manifest'

    Assert-Throws -MessagePattern 'changed in transit' -Action {
        & (Join-Path $automationRoot 'Assert-ReleaseArtifactManifest.ps1') `
            -ArtifactDirectory $releaseRoot `
            -ExpectedVersion $artifactVersion `
            -ExpectedCommit $artifactCommit `
            -ExpectedManifestSha256 ('0' * 64) | Out-Null
    }
    Write-Host 'PASS: a manifest that is not the validated one fails the transfer check'

    $wrongName = Join-Path $buildRoot 'TigerMarkView-setup.exe'
    Copy-Item -LiteralPath $builtInstaller -Destination $wrongName
    Assert-Throws -MessagePattern 'must be named' -Action {
        & (Join-Path $automationRoot 'New-ReleaseArtifactManifest.ps1') `
            -InstallerPath $wrongName `
            -ArtifactDirectory (Join-Path $testRoot 'release-wrong') `
            -Version $artifactVersion `
            -CommitSha $artifactCommit | Out-Null
    }
    Write-Host 'PASS: only the expected release installer can close the set'

    Write-Host
    Write-Host 'PASS: release automation foundation' -ForegroundColor Green
}
catch {
    Write-Host
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
