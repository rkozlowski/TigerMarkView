#Requires -Version 7.0
<#
    .SYNOPSIS
    Shared result vocabulary and GitHub state queries for TigerMarkView release
    automation.

    .DESCRIPTION
    Dot-source this file. It gives every release-automation script and workflow
    step one definition of:

      - the repository, workflow, branch, tag, and asset names a release involves;
      - the PASS / WARN / BLOCKED / FAIL / READY FOR HUMAN ACTION result shape,
        rendered identically to a terminal and to JSON from one object; and
      - how a prior human action is proven before any later stage mutates: the
        release commit is on origin/main, its exact CI push run succeeded, the
        release workflow run for that version and commit succeeded, and the
        published release is a non-draft at the expected commit.

    GitHub is reached only through an authenticated GitHub CLI session. Nothing
    here accepts a token argument, reads a token from the environment, logs a
    token, or inspects a credential store. Authentication repair is always
    'gh auth login'. Tests inject a fake `gh` invoker, so no check here needs a
    live credential or a network.

        . (Join-Path $PSScriptRoot 'ReleaseAutomation.ps1')
#>

Set-StrictMode -Version Latest

function Get-TigerMarkViewReleaseConstant {
    <#
        .SYNOPSIS
        The fixed identities a TigerMarkView release is expressed in terms of.

        .DESCRIPTION
        Defined once so a script, a test, and a workflow step cannot drift into
        three slightly different opinions of which repository, which workflow, or
        which asset names a release uses.
    #>
    [CmdletBinding()]
    param()

    [pscustomobject][ordered]@{
        repository = 'rkozlowski/TigerMarkView'
        repositoryUrl = 'https://github.com/rkozlowski/TigerMarkView'
        defaultBranch = 'main'
        ciWorkflowFile = 'ci.yml'
        ciWorkflowName = 'CI'
        releaseWorkflowFile = 'release.yml'
        releaseWorkflowName = 'Release TigerMarkView'
        tagPrefix = 'v'
        releaseAssetName = { param([string] $Version) "TigerMarkView-$Version-win-x64-setup.exe" }
        releaseAssetNames = { param([string] $Version) @(
                "TigerMarkView-$Version-win-x64-setup.exe"
                'SHA256SUMS.txt'
                'release-artifacts.json'
            ) }
        releaseNotesPath = { param([string] $Version) ".github/release-notes/$Version.md" }
        versionPattern = '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'
    }
}

function Test-TigerMarkViewReleaseVersion {
    <#
        .SYNOPSIS
        True when a string is an acceptable release version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Version
    )

    -not [string]::IsNullOrWhiteSpace($Version) -and
        $Version -match (Get-TigerMarkViewReleaseConstant).versionPattern
}

# --- Result vocabulary -------------------------------------------------------

$script:TigerMarkViewReleaseStatuses = @('PASS', 'WARN', 'BLOCKED', 'FAIL')

function New-TigerMarkViewReleaseCheck {
    <#
        .SYNOPSIS
        Records one named observation with its evidence and remediation.

        .DESCRIPTION
        A check never carries 'READY FOR HUMAN ACTION': that is a property of the
        whole report, added by Get-TigerMarkViewReleaseVerdict when nothing failed
        and a human decision is the only thing left. A single check is only ever
        PASS, WARN, BLOCKED, or FAIL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Id,

        [Parameter(Mandatory)]
        [ValidateSet('PASS', 'WARN', 'BLOCKED', 'FAIL')]
        [string] $Status,

        [Parameter(Mandatory)]
        [string] $Observed,

        [string] $Expected = '',

        [string] $Evidence = '',

        [string] $Remediation = ''
    )

    [pscustomobject][ordered]@{
        id = $Id
        status = $Status
        observed = $Observed
        expected = $Expected
        evidence = $Evidence
        remediation = $Remediation
    }
}

function New-TigerMarkViewReleaseAssertion {
    <#
        .SYNOPSIS
        Turns a boolean into a PASS check or a check of a chosen negative status.

        .DESCRIPTION
        The negative status is a parameter because the two failure meanings are
        different: BLOCKED is 'a required human or external checkpoint is not done
        yet', FAIL is 'a check ran and the data is wrong'. Callers choose.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Id,

        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $PassObserved,

        [Parameter(Mandatory)]
        [string] $FailObserved,

        [ValidateSet('WARN', 'BLOCKED', 'FAIL')]
        [string] $FailStatus = 'FAIL',

        [string] $Expected = '',

        [string] $Evidence = '',

        [string] $Remediation = ''
    )

    if ($Condition) {
        New-TigerMarkViewReleaseCheck -Id $Id -Status 'PASS' -Observed $PassObserved `
            -Expected $Expected -Evidence $Evidence
    }
    else {
        New-TigerMarkViewReleaseCheck -Id $Id -Status $FailStatus -Observed $FailObserved `
            -Expected $Expected -Evidence $Evidence -Remediation $Remediation
    }
}

function Get-TigerMarkViewReleaseVerdict {
    <#
        .SYNOPSIS
        Reduces a check list to one status, and optionally a human handoff.

        .DESCRIPTION
        Precedence is FAIL, then BLOCKED, then WARN, then PASS. An empty check list
        is FAIL, because nothing was proven. When every check is PASS or WARN and a
        -Handoff is supplied, the report status becomes 'READY FOR HUMAN ACTION':
        automation did its part and a human decision is the only remaining step.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Checks,

        [string[]] $Handoff = @(),

        [string] $NextCommand = ''
    )

    $checks = @($Checks)
    $failed = @($checks | Where-Object { $_.status -ceq 'FAIL' })
    $blocked = @($checks | Where-Object { $_.status -ceq 'BLOCKED' })
    $warned = @($checks | Where-Object { $_.status -ceq 'WARN' })
    $passed = @($checks | Where-Object { $_.status -ceq 'PASS' })

    $status =
        if ($checks.Count -eq 0 -or $failed.Count -gt 0) { 'FAIL' }
        elseif ($blocked.Count -gt 0) { 'BLOCKED' }
        elseif ($Handoff.Count -gt 0) { 'READY FOR HUMAN ACTION' }
        elseif ($warned.Count -gt 0) { 'WARN' }
        else { 'PASS' }

    [pscustomobject][ordered]@{
        status = $status
        passed = $passed.Count
        warned = $warned.Count
        blocked = $blocked.Count
        failed = $failed.Count
        total = $checks.Count
        handoff = @($Handoff)
        nextCommand = $NextCommand
    }
}

function Get-TigerMarkViewReleaseExitCode {
    <#
        .SYNOPSIS
        The process exit code for a report status.

        .DESCRIPTION
        0 for PASS, WARN, and READY FOR HUMAN ACTION: automation completed and any
        remaining step is a human decision. 2 for BLOCKED: a checkpoint is not done.
        1 for FAIL: a check found invalid data or an operation failed. Defined once
        and asserted in tests so scripts and CI agree.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Status
    )

    switch ($Status) {
        'PASS' { 0 }
        'WARN' { 0 }
        'READY FOR HUMAN ACTION' { 0 }
        'BLOCKED' { 2 }
        'FAIL' { 1 }
        default { 1 }
    }
}

function New-TigerMarkViewReleaseReport {
    <#
        .SYNOPSIS
        Binds a title, a check list, and a verdict into one object.

        .DESCRIPTION
        This object is the single source both Format-TigerMarkViewReleaseSummary
        and the JSON form render, so a maintainer's terminal and a machine reader
        never see different results.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Title,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Checks,

        [string[]] $Handoff = @(),

        [string] $NextCommand = '',

        [hashtable] $Context = @{}
    )

    $verdict = Get-TigerMarkViewReleaseVerdict -Checks $Checks -Handoff $Handoff -NextCommand $NextCommand
    [pscustomobject][ordered]@{
        schemaVersion = 1
        title = $Title
        status = $verdict.status
        completedUtc = [DateTime]::UtcNow.ToString('o')
        context = [pscustomobject] $Context
        summary = $verdict
        checks = @($Checks)
        exitCode = Get-TigerMarkViewReleaseExitCode -Status $verdict.status
    }
}

function Test-TigerMarkViewReleaseNotes {
    <#
        .SYNOPSIS
        Checks the checked-in version-specific release notes source.

        .DESCRIPTION
        A release must ship a deliberate, useful, user-facing summary. GitHub's
        generic generated notes are not enough: 0.8.1 produced only a Full
        Changelog link. This proves .github/release-notes/<version>.md exists, has
        the template's sections filled with real content, still carries no
        placeholder text, and leaks no secret or local path.

        Returns a check. The standalone Assert-ReleaseNotes.ps1 throws on anything
        but PASS; the readiness command folds the check into its report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [string] $NotesRoot
    )

    if ([string]::IsNullOrWhiteSpace($NotesRoot)) {
        $NotesRoot = Join-Path $RepositoryRoot '.github/release-notes'
    }
    $path = Join-Path $NotesRoot "$Version.md"
    $relative = ".github/release-notes/$Version.md"
    $repair = "Create $relative from .github/release-notes/TEMPLATE.md and fill every section with real, user-facing content."

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return New-TigerMarkViewReleaseCheck -Id 'release-notes/source' -Status 'FAIL' `
            -Observed "$relative does not exist." -Expected 'a version-specific release-notes file' `
            -Remediation $repair
    }

    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return New-TigerMarkViewReleaseCheck -Id 'release-notes/source' -Status 'FAIL' `
            -Observed "$relative has a UTF-8 byte-order mark." -Remediation 'Save it as UTF-8 without a BOM.'
    }
    $content = [Text.UTF8Encoding]::new($false, $false).GetString($bytes)
    $trimmed = $content.Trim()

    $sections = @([regex]::Matches($content, '(?m)^##\s+\S')).Count
    if ($sections -lt 2) {
        return New-TigerMarkViewReleaseCheck -Id 'release-notes/source' -Status 'FAIL' `
            -Observed "$relative has $sections level-2 sections; the template has at least two." `
            -Remediation $repair
    }

    $substantive = ($trimmed -replace '(?m)^\s*#.*$', '' -replace '\[[^\]]*\]\([^)]*\)', '' -replace '\s+', ' ').Trim()
    if ($substantive.Length -lt 120) {
        return New-TigerMarkViewReleaseCheck -Id 'release-notes/source' -Status 'FAIL' `
            -Observed "$relative has only $($substantive.Length) characters of prose outside headings and links." `
            -Expected 'a useful user-facing summary, not a bare Full Changelog link' -Remediation $repair
    }
    if ($trimmed -match '(?im)^\s*(\*\*)?Full Changelog(\*\*)?\s*:' -and $substantive.Length -lt 200) {
        return New-TigerMarkViewReleaseCheck -Id 'release-notes/source' -Status 'FAIL' `
            -Observed "$relative is essentially just a Full Changelog link." -Remediation $repair
    }

    $placeholder = [regex]::Match($content,
        '(?i)\b(TODO|TBD|FIXME|lorem ipsum)\b|<(describe|summari[sz]e|fill|add)[^>]*>|_placeholder_|xxx+')
    if ($placeholder.Success) {
        return New-TigerMarkViewReleaseCheck -Id 'release-notes/source' -Status 'FAIL' `
            -Observed "$relative still contains placeholder text: '$($placeholder.Value)'." -Remediation $repair
    }

    $leak = [regex]::Match($content,
        '(?i)[A-Za-z]:\\(Users|Projects)\\|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|secret|token)\s*[:=]\s*\S')
    if ($leak.Success) {
        return New-TigerMarkViewReleaseCheck -Id 'release-notes/source' -Status 'FAIL' `
            -Observed "$relative appears to contain a secret or a local path: '$($leak.Value)'." `
            -Remediation 'Remove the secret or local path before releasing.'
    }

    New-TigerMarkViewReleaseCheck -Id 'release-notes/source' -Status 'PASS' `
        -Observed "$relative has $sections sections and $($substantive.Length) characters of substantive content." `
        -Evidence $path
}

function Format-TigerMarkViewReleaseSummary {
    <#
        .SYNOPSIS
        Renders a report as plain lines, for a terminal and for a workflow summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Report,

        [switch] $Markdown
    )

    $lines = [Collections.Generic.List[string]]::new()
    if ($Markdown) {
        $lines.Add("### $($Report.title)")
        $lines.Add('')
        $lines.Add("**Status: $($Report.status)**")
        $lines.Add('')
        $lines.Add('| Check | Status | Observed |')
        $lines.Add('| --- | --- | --- |')
        foreach ($check in @($Report.checks)) {
            $observed = ([string] $check.observed) -replace '\|', '\|'
            $lines.Add("| $($check.id) | $($check.status) | $observed |")
        }
    }
    else {
        $lines.Add('')
        $lines.Add($Report.title)
        foreach ($check in @($Report.checks)) {
            $lines.Add(('  {0,-8} {1,-40} {2}' -f $check.status, $check.id, $check.observed))
            if (-not [string]::IsNullOrWhiteSpace($check.remediation)) {
                $lines.Add(('           -> {0}' -f $check.remediation))
            }
        }
        $s = $Report.summary
        $lines.Add('')
        $lines.Add(("  $($s.passed) passed, $($s.warned) warned, $($s.blocked) blocked, $($s.failed) failed"))
    }

    if (@($Report.summary.handoff).Count -gt 0) {
        $lines.Add('')
        $lines.Add('READY FOR HUMAN ACTION')
        $lines.Add('')
        $lines.Add('Required action:')
        $index = 1
        foreach ($item in @($Report.summary.handoff)) {
            $lines.Add(("{0}. {1}" -f $index, $item))
            $index++
        }
        if (-not [string]::IsNullOrWhiteSpace($Report.summary.nextCommand)) {
            $lines.Add('')
            $lines.Add('Then:')
            $lines.Add($Report.summary.nextCommand)
        }
    }
    elseif ($Report.status -cne 'PASS') {
        $lines.Add('')
        $lines.Add("$($Report.status): see the remediation lines above.")
    }

    $lines.ToArray()
}

# --- GitHub CLI adapter ----------------------------------------------------

function New-TigerMarkViewGitHubCli {
    <#
        .SYNOPSIS
        A thin, injectable wrapper around an authenticated `gh` session.

        .DESCRIPTION
        Every GitHub read this automation performs goes through one of the script
        blocks this returns, so a test can substitute a recorded `gh` without a
        network and there is exactly one place that decides how a `gh` invocation
        is run and how its exit code is interpreted.

        No token is ever read, passed, or printed. `gh` uses whatever session
        `gh auth login` established.

        .PARAMETER GhPath
        An explicit path to gh.exe. Resolved from PATH when omitted.

        .PARAMETER Invoker
        For tests only: a script block `param([string[]] $GhArgs)` returning an
        object with ExitCode, StdOut, and StdErr. When supplied, `gh` is never
        actually run.

        .PARAMETER Downloader
        For tests only: a script block `param([string[]] $GhArgs, [string] $OutFile)`
        returning an object with ExitCode and StdErr, having written the response
        body to $OutFile. Binary responses need their own route because they must
        reach a file as raw bytes rather than through a decoded string.
    #>
    [CmdletBinding()]
    param(
        [string] $GhPath,

        [scriptblock] $Invoker,

        [scriptblock] $Downloader
    )

    $resolvedPath = $null
    if ($null -eq $Invoker) {
        if ([string]::IsNullOrWhiteSpace($GhPath)) {
            $command = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($null -eq $command) {
                throw ('GitHub CLI (gh) was not found on PATH. Install it from https://cli.github.com/ ' +
                    'and run "gh auth login".')
            }
            $resolvedPath = $command.Source
        }
        else {
            $resolvedPath = [IO.Path]::GetFullPath($GhPath)
            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
                throw "GitHub CLI not found at '$resolvedPath'."
            }
        }
    }

    $runner = $Invoker
    if ($null -eq $runner) {
        $runner = {
            param([string[]] $GhArgs)

            $previousExit = $global:LASTEXITCODE
            $previousNative = $PSNativeCommandUseErrorActionPreference
            $errFile = [IO.Path]::GetTempFileName()
            try {
                $PSNativeCommandUseErrorActionPreference = $false
                $stdout = (& $resolvedPath @GhArgs 2>$errFile | Out-String)
                $exit = $LASTEXITCODE
                $stderr = ''
                if (Test-Path -LiteralPath $errFile) {
                    $stderr = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
                }
                [pscustomobject]@{
                    ExitCode = [int] $exit
                    StdOut = [string] $stdout
                    StdErr = [string] $stderr
                }
            }
            finally {
                $PSNativeCommandUseErrorActionPreference = $previousNative
                $global:LASTEXITCODE = $previousExit
                Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
            }
        }.GetNewClosure()
    }

    $downloadRunner = $Downloader
    if ($null -eq $downloadRunner) {
        if ($null -ne $Invoker) {
            # A fake session that never declared a download route must say so rather
            # than reaching for the real gh a test deliberately replaced.
            $downloadRunner = {
                param([string[]] $GhArgs, [string] $OutFile)
                throw 'This gh session was created with -Invoker but no -Downloader, so it cannot download.'
            }.GetNewClosure()
        }
        else {
            $downloadRunner = {
                param([string[]] $GhArgs, [string] $OutFile)

                # A workflow artifact is a zip, so its body must reach the file as raw
                # bytes. Piping a native command through PowerShell decodes text, which
                # would silently corrupt it; the process's stdout stream is copied
                # instead. stderr is read asynchronously so a chatty gh cannot fill its
                # pipe and deadlock the copy.
                $startInfo = [Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = $resolvedPath
                foreach ($argument in $GhArgs) { $startInfo.ArgumentList.Add($argument) }
                $startInfo.RedirectStandardOutput = $true
                $startInfo.RedirectStandardError = $true
                $startInfo.UseShellExecute = $false
                $process = [Diagnostics.Process]::Start($startInfo)
                $errorTask = $process.StandardError.ReadToEndAsync()
                $stream = [IO.File]::Create($OutFile)
                try { $process.StandardOutput.BaseStream.CopyTo($stream) }
                finally { $stream.Dispose() }
                $stderr = $errorTask.GetAwaiter().GetResult()
                $process.WaitForExit()
                [pscustomobject]@{ ExitCode = [int] $process.ExitCode; StdErr = [string] $stderr }
            }.GetNewClosure()
        }
    }

    [pscustomobject][ordered]@{
        path = $resolvedPath
        isFake = $null -ne $Invoker
        run = {
            param([Parameter(Mandatory)][string[]] $GhArgs)
            & $runner $GhArgs
        }.GetNewClosure()
        tryApi = {
            param(
                [Parameter(Mandatory)][string] $Path,
                [string[]] $ExtraArgs = @()
            )

            $arguments = @('api', '-H', 'Accept: application/vnd.github+json', $Path) + $ExtraArgs
            $result = & $runner $arguments
            $data = $null
            $parseError = $null
            if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.StdOut)) {
                try { $data = $result.StdOut | ConvertFrom-Json }
                catch { $parseError = $_.Exception.Message }
            }
            [pscustomobject][ordered]@{
                ok = $result.ExitCode -eq 0 -and $null -eq $parseError
                exitCode = $result.ExitCode
                data = $data
                stdout = $result.StdOut
                stderr = $result.StdErr
                parseError = $parseError
            }
        }.GetNewClosure()
        api = {
            param(
                [Parameter(Mandatory)][string] $Path,
                [string[]] $ExtraArgs = @()
            )

            $arguments = @('api', '-H', 'Accept: application/vnd.github+json', $Path) + $ExtraArgs
            $result = & $runner $arguments
            if ($result.ExitCode -ne 0) {
                throw ("gh api $Path failed (exit $($result.ExitCode)): " +
                    ($result.StdErr, $result.StdOut | Where-Object { $_ } | Select-Object -First 1))
            }
            try { $result.StdOut | ConvertFrom-Json }
            catch { throw "gh api $Path returned output that is not JSON: $($_.Exception.Message)" }
        }.GetNewClosure()
        downloadApi = {
            param(
                [Parameter(Mandatory)][string] $Path,
                [Parameter(Mandatory)][string] $OutFile
            )

            # gh follows the artifact endpoint's redirect to storage itself, and it
            # knows not to carry the GitHub credential across that hop.
            $arguments = @('api', '-H', 'Accept: application/vnd.github+json', $Path)
            $result = & $downloadRunner $arguments $OutFile
            if ($result.ExitCode -ne 0) {
                if (Test-Path -LiteralPath $OutFile) {
                    Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
                }
                throw ("gh api $Path could not be downloaded (exit $($result.ExitCode)): " +
                    (([string] $result.StdErr) -replace '\s+', ' '))
            }
            $OutFile
        }.GetNewClosure()
    }
}

function Test-TigerMarkViewGitHubCliSession {
    <#
        .SYNOPSIS
        Proves an authenticated `gh` session that can read this repository's
        Actions and identify its user.

        .DESCRIPTION
        Reports checks rather than throwing, so one run can show every reason a
        session is unusable. The token itself is never read: `gh auth status`
        already knows whether one exists, and `gh api user` proves it works.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Cli,

        [string] $Repository = (Get-TigerMarkViewReleaseConstant).repository
    )

    $checks = [Collections.Generic.List[object]]::new()
    $repair = 'Run "gh auth login" and choose an account authorized for this repository.'

    if (-not $Cli.isFake -and [string]::IsNullOrWhiteSpace([string] $Cli.path)) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'gh/available' -Status 'BLOCKED' `
            -Observed 'The GitHub CLI (gh) is not installed.' `
            -Expected 'gh on PATH' -Remediation 'Install it from https://cli.github.com/.'))
        return $checks.ToArray()
    }
    $checks.Add((New-TigerMarkViewReleaseCheck -Id 'gh/available' -Status 'PASS' `
        -Observed "GitHub CLI resolved$(if ($Cli.path) { " at $($Cli.path)" })."))

    $status = & $Cli.run @('auth', 'status')
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'gh/auth-status' `
        -Condition ($status.ExitCode -eq 0) `
        -PassObserved 'gh auth status reports an authenticated session.' `
        -FailObserved ('gh auth status reports no usable session: ' +
            (($status.StdErr, $status.StdOut | Where-Object { $_ } | Select-Object -First 1) -replace '\s+', ' ')) `
        -FailStatus 'BLOCKED' -Remediation $repair))
    if ($status.ExitCode -ne 0) { return $checks.ToArray() }

    $viewer = & $Cli.tryApi 'user'
    $login = if ($viewer.ok -and $null -ne $viewer.data) { [string] $viewer.data.login } else { $null }
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'gh/viewer' `
        -Condition (-not [string]::IsNullOrWhiteSpace($login)) `
        -PassObserved "Authenticated as $login." `
        -FailObserved 'gh could not identify the authenticated user (gh api user failed).' `
        -FailStatus 'BLOCKED' -Remediation $repair -Evidence $login))

    $actions = & $Cli.tryApi "repos/$Repository/actions/permissions"
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'gh/actions-read' `
        -Condition $actions.ok `
        -PassObserved "The session can read Actions for $Repository." `
        -FailObserved ("The session cannot read Actions for $Repository " +
            "(gh api repos/$Repository/actions/permissions failed).") `
        -FailStatus 'BLOCKED' `
        -Remediation 'Authenticate an account with at least read access to this repository''s Actions.'))

    $checks.ToArray()
}

# --- Prior-action verification -------------------------------------------------

function Test-TigerMarkViewCommitOnMain {
    <#
        .SYNOPSIS
        Proves a commit is reachable from origin/main.

        .DESCRIPTION
        A release stage that follows a human push must not infer the push from a
        green run or a nearby commit. This fetches origin/main and asks git whether
        the exact commit is an ancestor of, or equal to, its tip.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{40}$')]
        [string] $CommitSha,

        [string] $Branch = (Get-TigerMarkViewReleaseConstant).defaultBranch,

        [switch] $Fetch
    )

    $repair = "Push the release commit to origin/$Branch and rerun after it lands."
    $previousNative = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        if ($Fetch) {
            # Explicit refspec: a shallow or single-ref checkout (as GitHub Actions
            # produces for a dispatched SHA) has no refs/remotes/origin/<branch>
            # otherwise, and '+' keeps the remote-tracking ref updatable.
            & git -C $RepositoryRoot fetch --quiet origin "+refs/heads/${Branch}:refs/remotes/origin/${Branch}" 2>&1 | Out-Null
        }
        $tip = (& git -C $RepositoryRoot rev-parse --verify --quiet "refs/remotes/origin/$Branch" 2>&1 | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($tip)) {
            return New-TigerMarkViewReleaseCheck -Id 'commit/on-main' -Status 'BLOCKED' `
                -Observed "origin/$Branch is not known to this checkout." `
                -Expected "the release commit reachable from origin/$Branch" `
                -Remediation "Run 'git fetch origin $Branch' and rerun."
        }
        & git -C $RepositoryRoot merge-base --is-ancestor $CommitSha $tip 2>&1 | Out-Null
        $isAncestor = $LASTEXITCODE -eq 0
        New-TigerMarkViewReleaseAssertion -Id 'commit/on-main' `
            -Condition ($isAncestor -or $tip -ceq $CommitSha.ToLowerInvariant()) `
            -PassObserved "Commit $CommitSha is reachable from origin/$Branch ($tip)." `
            -FailObserved "Commit $CommitSha is not reachable from origin/$Branch ($tip)." `
            -FailStatus 'BLOCKED' -Expected "reachable from origin/$Branch" -Evidence $tip `
            -Remediation $repair
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $previousNative
        $global:LASTEXITCODE = 0
    }
}

function Get-TigerMarkViewWorkflowRunForCommit {
    <#
        .SYNOPSIS
        Selects the one workflow run for an exact commit and reports its state.

        .DESCRIPTION
        Selection is by workflow file, exact head SHA, and - by default - the
        `push` event on the default branch. A pull-request run for the same commit,
        a run for a different commit, or a merely completed run is not a success
        here. Returns a check plus the selected run's identity so a summary can
        cite the run URL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Cli,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{40}$')]
        [string] $CommitSha,

        [string] $Repository = (Get-TigerMarkViewReleaseConstant).repository,

        [string] $WorkflowFile = (Get-TigerMarkViewReleaseConstant).ciWorkflowFile,

        [string] $Event = 'push',

        [string] $Branch = (Get-TigerMarkViewReleaseConstant).defaultBranch,

        [string] $CheckId = 'ci/run'
    )

    $query = "repos/$Repository/actions/workflows/$WorkflowFile/runs?head_sha=$($CommitSha.ToLowerInvariant())&per_page=100"
    $response = & $Cli.tryApi $query
    if (-not $response.ok) {
        return [pscustomobject]@{
            check = (New-TigerMarkViewReleaseCheck -Id $CheckId -Status 'BLOCKED' `
                -Observed "Could not query $WorkflowFile runs for $CommitSha." `
                -Evidence ($response.stderr -replace '\s+', ' ') `
                -Remediation 'Confirm the gh session can read Actions, then rerun.')
            run = $null
        }
    }

    $runs = @()
    if ($null -ne $response.data -and $null -ne $response.data.PSObject.Properties['workflow_runs']) {
        $runs = @($response.data.workflow_runs)
    }
    $matching = @($runs | Where-Object {
        [string] $_.head_sha -ceq $CommitSha.ToLowerInvariant() -and
        (($Event -eq '') -or [string] $_.event -ceq $Event) -and
        (($Branch -eq '') -or [string] $_.head_branch -ceq $Branch)
    })

    if ($matching.Count -eq 0) {
        return [pscustomobject]@{
            check = (New-TigerMarkViewReleaseCheck -Id $CheckId -Status 'BLOCKED' `
                -Observed "No $Event run of $WorkflowFile on $Branch exists for $CommitSha." `
                -Expected "a completed, successful $WorkflowFile $Event run for this commit" `
                -Remediation "Wait for the $WorkflowFile run triggered by the push to finish.")
            run = $null
        }
    }

    $selected = @($matching | Sort-Object -Property @{ Expression = { [long] $_.run_number } } -Descending)[0]
    $runInfo = [pscustomobject][ordered]@{
        id = [long] $selected.id
        runNumber = [long] $selected.run_number
        status = [string] $selected.status
        conclusion = [string] $selected.conclusion
        event = [string] $selected.event
        headBranch = [string] $selected.head_branch
        headSha = ([string] $selected.head_sha).ToLowerInvariant()
        url = [string] $selected.html_url
        candidates = $matching.Count
    }

    $check =
        if ($runInfo.status -cne 'completed') {
            New-TigerMarkViewReleaseCheck -Id $CheckId -Status 'BLOCKED' `
                -Observed "$WorkflowFile run $($runInfo.runNumber) for $CommitSha is '$($runInfo.status)'." `
                -Expected 'status=completed, conclusion=success' -Evidence $runInfo.url `
                -Remediation 'Wait for the run to complete, then rerun.'
        }
        elseif ($runInfo.conclusion -cne 'success') {
            New-TigerMarkViewReleaseCheck -Id $CheckId -Status 'FAIL' `
                -Observed "$WorkflowFile run $($runInfo.runNumber) for $CommitSha concluded '$($runInfo.conclusion)'." `
                -Expected 'conclusion=success' -Evidence $runInfo.url `
                -Remediation 'Fix the cause in a new release commit, push it, and dispatch that commit.'
        }
        else {
            New-TigerMarkViewReleaseCheck -Id $CheckId -Status 'PASS' `
                -Observed "$WorkflowFile run $($runInfo.runNumber) for $CommitSha concluded success." `
                -Evidence $runInfo.url
        }

    [pscustomobject]@{ check = $check; run = $runInfo }
}

function Resolve-TigerMarkViewReleaseTagCommit {
    <#
        .SYNOPSIS
        Resolves v<version> to the commit it names, dereferencing an annotated tag.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Cli,

        [Parameter(Mandatory)]
        [string] $Version,

        [string] $Repository = (Get-TigerMarkViewReleaseConstant).repository
    )

    $tag = (Get-TigerMarkViewReleaseConstant).tagPrefix + $Version
    $reference = & $Cli.tryApi "repos/$Repository/git/ref/tags/$tag"
    if (-not $reference.ok -or $null -eq $reference.data) {
        return [pscustomobject]@{
            check = (New-TigerMarkViewReleaseCheck -Id 'release/tag' -Status 'BLOCKED' `
                -Observed "No git tag '$tag' exists in $Repository." `
                -Expected "annotated tag '$tag' at the release commit" `
                -Remediation 'The tag is created by the release workflow; dispatch it first.')
            commit = $null
            tag = $tag
        }
    }

    $sha = [string] $reference.data.object.sha
    if ([string] $reference.data.object.type -ceq 'tag') {
        $annotated = & $Cli.tryApi "repos/$Repository/git/tags/$sha"
        if ($annotated.ok -and $null -ne $annotated.data) {
            $sha = [string] $annotated.data.object.sha
        }
    }
    if ($sha -notmatch '^[0-9a-fA-F]{40}$') {
        return [pscustomobject]@{
            check = (New-TigerMarkViewReleaseCheck -Id 'release/tag' -Status 'FAIL' `
                -Observed "Tag '$tag' did not resolve to a commit SHA." -Evidence $sha)
            commit = $null
            tag = $tag
        }
    }

    [pscustomobject]@{
        check = (New-TigerMarkViewReleaseCheck -Id 'release/tag' -Status 'PASS' `
            -Observed "Tag '$tag' resolves to $($sha.ToLowerInvariant())." -Evidence $sha.ToLowerInvariant())
        commit = $sha.ToLowerInvariant()
        tag = $tag
    }
}

function Get-TigerMarkViewReleaseState {
    <#
        .SYNOPSIS
        Reports whether the GitHub release for a version is a published non-draft
        at the expected commit with exactly the expected assets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Cli,

        [Parameter(Mandatory)]
        [string] $Version,

        [string] $ExpectedCommit,

        [string] $Repository = (Get-TigerMarkViewReleaseConstant).repository
    )

    $constant = Get-TigerMarkViewReleaseConstant
    $tag = $constant.tagPrefix + $Version
    $expectedAssets = & $constant.releaseAssetNames $Version

    $checks = [Collections.Generic.List[object]]::new()
    $response = & $Cli.tryApi "repos/$Repository/releases/tags/$tag"
    if (-not $response.ok -or $null -eq $response.data) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'release/exists' -Status 'BLOCKED' `
            -Observed "No GitHub release is tagged '$tag' in $Repository." `
            -Expected "a published release tagged '$tag'" `
            -Remediation 'Publish the draft release, then rerun.'))
        return [pscustomobject]@{ checks = $checks.ToArray(); release = $null }
    }

    $release = $response.data
    $isDraft = $null -ne $release.PSObject.Properties['draft'] -and [bool] $release.draft
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'release/published' `
        -Condition (-not $isDraft) `
        -PassObserved "Release '$tag' is published (isDraft=false)." `
        -FailObserved "Release '$tag' is still a draft." `
        -FailStatus 'BLOCKED' -Evidence ([string] $release.html_url) `
        -Remediation 'The human publishes the draft; automation never does.'))

    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit)) {
        $target = [string] $release.target_commitish
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'release/commit' `
            -Condition ($target -ceq $ExpectedCommit -or $target -ceq (Get-TigerMarkViewReleaseConstant).defaultBranch) `
            -PassObserved "Release '$tag' targets '$target'." `
            -FailObserved "Release '$tag' targets '$target', not the expected commit." `
            -Expected $ExpectedCommit -Evidence $target `
            -Remediation 'Resolve the release identity explicitly; never move a release tag.'))
    }

    $assetNames = @()
    if ($null -ne $release.PSObject.Properties['assets'] -and $null -ne $release.assets) {
        $assetNames = @($release.assets | ForEach-Object { [string] $_.name })
    }
    $missing = @($expectedAssets | Where-Object { $_ -cnotin $assetNames })
    $unexpected = @($assetNames | Where-Object { $_ -cnotin $expectedAssets })
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'release/assets' `
        -Condition ($missing.Count -eq 0 -and $unexpected.Count -eq 0) `
        -PassObserved "Release '$tag' has exactly the three expected assets." `
        -FailObserved ("Release '$tag' asset set is wrong. Missing: $($missing -join ', '); " +
            "unexpected: $($unexpected -join ', ').") `
        -Evidence ($assetNames -join ', ')))

    [pscustomobject]@{
        checks = $checks.ToArray()
        release = [pscustomobject][ordered]@{
            tag = $tag
            name = [string] $release.name
            isDraft = $isDraft
            targetCommitish = [string] $release.target_commitish
            htmlUrl = [string] $release.html_url
            publishedAt = [string] $release.published_at
            assetNames = $assetNames
        }
    }
}
