#Requires -Version 7.0
<#
    .SYNOPSIS
    Read-only safety checks for the dedicated winget-pkgs clone TigerMarkView
    submits its manifests from.

    .DESCRIPTION
    Dot-source this file. It owns everything that must be proven before the
    submission orchestrator is allowed to fetch, synchronize, branch, copy,
    commit, or push:

      - loading the narrowly scoped clone configuration
        (eng/winget/winget-pkgs.clone.json): clone path, fork and upstream slugs,
        default branch, branch prefix, and manifest path;
      - GitHub-slug comparison that tolerates only canonical URL-form differences;
      - detection of every interrupted Git operation in the clone;
      - clone identity: it is the expected worktree, `origin` is the fork,
        `upstream` is microsoft/winget-pkgs, the default branch is `master`, the
        worktree is clean, and nothing untracked would be overwritten; and
      - the project-specific previous-PR gate: the most recent
        microsoft/winget-pkgs pull request from the fork whose head branch starts
        `ItTiger-TigerMarkView-`. Open or draft blocks; merged or manually closed
        passes.

    Nothing here fetches, writes, resets, or pushes. Mutation belongs to
    WinGetPkgsSubmission.ps1, which runs only after every check here is PASS. The
    one thing the two share is Invoke-TigerCloneGit, so there is a single way this
    repository invokes git against the clone.
#>

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..' 'release-automation' 'ReleaseAutomation.ps1')

function Get-TigerWinGetPkgsCloneConfig {
    <#
        .SYNOPSIS
        Loads and validates the dedicated-clone configuration.

        .PARAMETER RepositoryRoot
        The TigerMarkView repository root. Defaults to two levels up.

        .PARAMETER ConfigPath
        An explicit configuration file. Defaults to
        eng/winget/winget-pkgs.clone.json.

        .PARAMETER ClonePath
        An explicit clone path that overrides the configured clonePath. This is a
        maintainer decision, so it wins - but it is still validated the same way.
    #>
    [CmdletBinding()]
    param(
        [string] $RepositoryRoot,

        [string] $ConfigPath,

        [string] $ClonePath
    )

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $PSScriptRoot 'winget-pkgs.clone.json'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "winget-pkgs clone configuration not found: $ConfigPath"
    }

    $raw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $required = @('forkSlug', 'upstreamSlug', 'defaultBranch', 'branchPrefix', 'packageIdentifier', 'manifestPath')
    foreach ($key in $required) {
        if ($null -eq $raw.PSObject.Properties[$key] -or [string]::IsNullOrWhiteSpace([string] $raw.$key)) {
            throw "winget-pkgs clone configuration '$ConfigPath' is missing '$key'."
        }
    }
    foreach ($slugKey in @('forkSlug', 'upstreamSlug')) {
        if ([string] $raw.$slugKey -notmatch '^[^/\s]+/[^/\s]+$') {
            throw "winget-pkgs clone configuration '$slugKey' must be 'owner/name'; got '$($raw.$slugKey)'."
        }
    }

    $resolvedClonePath = if (-not [string]::IsNullOrWhiteSpace($ClonePath)) {
        $ClonePath
    }
    elseif ($null -ne $raw.PSObject.Properties['clonePath'] -and -not [string]::IsNullOrWhiteSpace([string] $raw.clonePath)) {
        [string] $raw.clonePath
    }
    else {
        throw "winget-pkgs clone configuration '$ConfigPath' declares no clonePath and none was passed."
    }
    if (-not [IO.Path]::IsPathRooted($resolvedClonePath)) {
        throw "The winget-pkgs clone path must be absolute; got '$resolvedClonePath'."
    }

    $forkOwner = ([string] $raw.forkSlug -split '/')[0]

    [pscustomobject][ordered]@{
        configPath = [IO.Path]::GetFullPath($ConfigPath)
        clonePath = [IO.Path]::GetFullPath($resolvedClonePath)
        clonePathSource = if (-not [string]::IsNullOrWhiteSpace($ClonePath)) { 'the -ClonePath argument' } else { $ConfigPath }
        forkSlug = [string] $raw.forkSlug
        forkOwner = $forkOwner
        upstreamSlug = [string] $raw.upstreamSlug
        defaultBranch = [string] $raw.defaultBranch
        branchPrefix = [string] $raw.branchPrefix
        packageIdentifier = [string] $raw.packageIdentifier
        manifestPath = ([string] $raw.manifestPath) -replace '\\', '/'
        forkUrl = "https://github.com/$($raw.forkSlug)"
        upstreamUrl = "https://github.com/$($raw.upstreamSlug)"
    }
}

function Get-TigerGitHubSlug {
    <#
        .SYNOPSIS
        Reduces a Git remote URL to a lower-case 'owner/name', or $null.

        .DESCRIPTION
        Accepts the canonical forms only: https, ssh scp-style, and ssh:// URLs on
        github.com, with or without a trailing '.git'. Anything else returns $null,
        so an unexpected remote is a clear stop rather than a lenient guess.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Url
    )

    $value = ([string] $Url).Trim()
    $patterns = @(
        '^https://github\.com/(?<owner>[^/]+)/(?<name>[^/]+?)(?:\.git)?/?$'
        '^git@github\.com:(?<owner>[^/]+)/(?<name>[^/]+?)(?:\.git)?/?$'
        '^ssh://git@github\.com/(?<owner>[^/]+)/(?<name>[^/]+?)(?:\.git)?/?$'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($value, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return ('{0}/{1}' -f $match.Groups['owner'].Value, $match.Groups['name'].Value).ToLowerInvariant()
        }
    }
    $null
}

function Test-TigerGitHubSlugMatch {
    <#
        .SYNOPSIS
        True when a remote URL denotes the expected owner/name repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Url,

        [Parameter(Mandatory)]
        [string] $ExpectedSlug
    )

    $actual = Get-TigerGitHubSlug -Url $Url
    $null -ne $actual -and $actual -ceq $ExpectedSlug.ToLowerInvariant()
}

function Get-TigerWinGetPkgsInterruptedOperation {
    <#
        .SYNOPSIS
        Names every interrupted Git operation active in a clone.

        .DESCRIPTION
        A merge, rebase, cherry-pick, revert, bisect, or unfinished sequencer run
        means the worktree is not in a state anything may build on. Returns the
        list of active operations (empty when the clone is idle).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ClonePath
    )

    $gitDir = Join-Path $ClonePath '.git'
    if (Test-Path -LiteralPath $gitDir -PathType Leaf) {
        # A worktree/submodule .git file; resolve it.
        $pointer = (Get-Content -LiteralPath $gitDir -Raw).Trim()
        if ($pointer -match '^gitdir:\s*(.+)$') {
            $gitDir = [IO.Path]::GetFullPath((Join-Path $ClonePath $Matches[1].Trim()))
        }
    }
    if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) { return @() }

    $active = [Collections.Generic.List[string]]::new()
    $markers = [ordered]@{
        'merge'       = @('MERGE_HEAD')
        'rebase'      = @('rebase-merge', 'rebase-apply')
        'cherry-pick' = @('CHERRY_PICK_HEAD')
        'revert'      = @('REVERT_HEAD')
        'bisect'      = @('BISECT_LOG')
        'sequencer'   = @('sequencer')
    }
    foreach ($operation in $markers.Keys) {
        foreach ($marker in $markers[$operation]) {
            if (Test-Path -LiteralPath (Join-Path $gitDir $marker)) {
                $active.Add($operation)
                break
            }
        }
    }
    $active.ToArray()
}

function Invoke-TigerCloneGit {
    <#
        .SYNOPSIS
        Runs a git command in a clone and returns its exit code and output.

        .DESCRIPTION
        The one way this repository's automation invokes git against the dedicated
        clone, so failures are always values rather than terminating errors and a
        native exit code can never leak into the caller's own status. Every check
        here uses it read-only; the guarded mutation in WinGetPkgsSubmission.ps1
        uses the same function to write, which is why it lives here rather than
        being duplicated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ClonePath,

        [Parameter(Mandatory)]
        [string[]] $GitArgs
    )

    $previous = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $output = (& git -C $ClonePath @GitArgs 2>&1 | Out-String)
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output.Trim() }
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $previous
        $global:LASTEXITCODE = 0
    }
}

function Get-TigerCloneRemoteUrl {
    <#
        .SYNOPSIS
        Reads both the URL a remote declares and the URL git will really contact.

        .DESCRIPTION
        These are not always the same. `git config --get remote.<name>.url` is what
        the clone was configured with; `git remote get-url` is that value after any
        url.<base>.insteadOf rewriting. Identity is judged on the declared value,
        and a difference between the two is reported separately rather than being
        hidden behind whichever one happened to be read.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ClonePath,

        [Parameter(Mandatory)]
        [string] $Remote
    )

    $declared = (Invoke-TigerCloneGit -ClonePath $ClonePath `
        -GitArgs @('config', '--get', "remote.$Remote.url")).Output
    $effective = (Invoke-TigerCloneGit -ClonePath $ClonePath `
        -GitArgs @('remote', 'get-url', $Remote)).Output

    [pscustomobject][ordered]@{
        remote = $Remote
        declared = $declared
        effective = $effective
        isRedirected = -not [string]::IsNullOrWhiteSpace($declared) -and $effective -cne $declared
    }
}

function Get-TigerWinGetPkgsClonePlan {
    <#
        .SYNOPSIS
        The commands that would create an absent clone. Never executed here.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config
    )

    @(
        "git clone $($Config.forkUrl) `"$($Config.clonePath)`""
        "git -C `"$($Config.clonePath)`" remote add upstream $($Config.upstreamUrl)"
        "git -C `"$($Config.clonePath)`" fetch upstream"
    )
}

function Test-TigerWinGetPkgsCloneIdentity {
    <#
        .SYNOPSIS
        Proves the dedicated clone is safe to synchronize and submit from.

        .DESCRIPTION
        Returns a list of checks. An absent clone is BLOCKED (the orchestrator may
        create it from the plan); any wrong, dirty, or interrupted existing clone
        is FAIL and must be resolved by hand.

        .PARAMETER SubmissionBranch
        The submission branch this run would prepare, when there is one. A previous
        successful run deliberately leaves the clone on that branch so its diff can
        be read, so finding HEAD there is expected rather than noteworthy. Without
        it, only the default branch is expected.

        .PARAMETER SubmissionPath
        The repository-relative version directory this run owns, when there is one.
        An interrupted run can leave exactly those three files in the worktree, and
        a rerun re-copies and rehashes them before anything is committed, so they
        are resumable rather than dirty. Everything outside that directory still has
        to be clean. Without it - the standalone read-only gate - nothing at all is
        tolerated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [string] $SubmissionBranch,

        [string] $SubmissionPath
    )

    $ownedPrefix = if ([string]::IsNullOrWhiteSpace($SubmissionPath)) { $null } else { "$SubmissionPath/" }
    $isOwned = {
        param([string] $Path)
        $null -ne $ownedPrefix -and
            ($Path -replace '\\', '/').StartsWith($ownedPrefix, [StringComparison]::Ordinal)
    }.GetNewClosure()
    $porcelainPath = { param([string] $Line) ($Line -replace '^.{3}', '').Trim().Trim('"') }

    $checks = [Collections.Generic.List[object]]::new()
    $clonePath = $Config.clonePath

    if (-not (Test-Path -LiteralPath $clonePath -PathType Container)) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'clone/exists' -Status 'BLOCKED' `
            -Observed "The dedicated clone does not exist at $clonePath." `
            -Expected "a clone of $($Config.forkSlug) with an 'upstream' remote for $($Config.upstreamSlug)" `
            -Evidence ((Get-TigerWinGetPkgsClonePlan -Config $Config) -join ' ; ') `
            -Remediation "The submission command will create it: $((Get-TigerWinGetPkgsClonePlan -Config $Config)[0])"))
        return $checks.ToArray()
    }

    $topLevel = Invoke-TigerCloneGit -ClonePath $clonePath -GitArgs @('rev-parse', '--show-toplevel')
    $isWorktree = $topLevel.ExitCode -eq 0 -and
        ([IO.Path]::GetFullPath($topLevel.Output) -ceq [IO.Path]::GetFullPath($clonePath))
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/worktree' `
        -Condition $isWorktree `
        -PassObserved "$clonePath is the top level of a Git worktree." `
        -FailObserved "$clonePath is not a Git worktree root (git rev-parse --show-toplevel: '$($topLevel.Output)')." `
        -Remediation 'Remove or relocate the directory so the clone can be created cleanly.'))
    if (-not $isWorktree) { return $checks.ToArray() }

    $origin = Get-TigerCloneRemoteUrl -ClonePath $clonePath -Remote 'origin'
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/origin' `
        -Condition (Test-TigerGitHubSlugMatch -Url $origin.declared -ExpectedSlug $Config.forkSlug) `
        -PassObserved "origin is $($Config.forkSlug)." `
        -FailObserved "origin is '$($origin.declared)', not $($Config.forkSlug)." `
        -Expected $Config.forkSlug -Evidence $origin.declared `
        -Remediation 'Never silently rewrite the remote; resolve the clone identity by hand.'))

    $upstream = Get-TigerCloneRemoteUrl -ClonePath $clonePath -Remote 'upstream'
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/upstream' `
        -Condition (Test-TigerGitHubSlugMatch -Url $upstream.declared -ExpectedSlug $Config.upstreamSlug) `
        -PassObserved "upstream is $($Config.upstreamSlug)." `
        -FailObserved "upstream is '$($upstream.declared)', not $($Config.upstreamSlug)." `
        -Expected $Config.upstreamSlug -Evidence $upstream.declared `
        -Remediation "Add it: git -C `"$clonePath`" remote add upstream $($Config.upstreamUrl)"))

    # A url.<base>.insteadOf rule can send a correctly-declared remote somewhere
    # else entirely. Neither URL alone would show that, so both are read and any
    # difference is named with the address git will really contact.
    $redirected = @(@($origin, $upstream) | Where-Object { $_.isRedirected })
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/remote-redirect' `
        -Condition ($redirected.Count -eq 0) `
        -PassObserved 'Git contacts both remotes at the URLs the clone declares.' `
        -FailObserved ("Git rewrites " + (($redirected | ForEach-Object {
                "$($_.remote) '$($_.declared)' to '$($_.effective)'" }) -join '; ') +
            ' through a url.<base>.insteadOf rule, so the submission would not reach the declared repository.') `
        -FailStatus 'WARN' `
        -Evidence (($redirected | ForEach-Object { "$($_.remote)=$($_.effective)" }) -join ', ') `
        -Remediation 'Confirm the redirect is deliberate, or remove the url.<base>.insteadOf rule.'))

    $currentBranch = (Invoke-TigerCloneGit -ClonePath $clonePath -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')).Output
    $expectedBranches = @($Config.defaultBranch) +
        @(if (-not [string]::IsNullOrWhiteSpace($SubmissionBranch)) { $SubmissionBranch })
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/default-branch' `
        -Condition ($currentBranch -cin $expectedBranches) `
        -PassObserved "HEAD is on '$currentBranch'." `
        -FailObserved "HEAD is on '$currentBranch', not $(($expectedBranches | ForEach-Object { "'$_'" }) -join ' or ')." `
        -FailStatus 'WARN' -Evidence $currentBranch `
        -Remediation "Check out '$($Config.defaultBranch)' before synchronizing."))

    $porcelain = (Invoke-TigerCloneGit -ClonePath $clonePath `
        -GitArgs @('status', '--porcelain', '--untracked-files=all')).Output
    $dirtyLines = @($porcelain -split "\r?\n" | Where-Object { $_ })
    $resumableDirty = @($dirtyLines | Where-Object { & $isOwned (& $porcelainPath $_) })
    $foreignDirty = @($dirtyLines | Where-Object { -not (& $isOwned (& $porcelainPath $_)) })
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/clean' `
        -Condition ($foreignDirty.Count -eq 0) `
        -PassObserved $(if ($resumableDirty.Count -eq 0) {
                'The worktree and index are clean.'
            }
            else {
                "The worktree is clean apart from $($resumableDirty.Count) file(s) under " +
                    "$SubmissionPath, which an interrupted run leaves behind and this run re-copies " +
                    'and rehashes before committing anything.'
            }) `
        -FailObserved ("The worktree has $($foreignDirty.Count) uncommitted change(s) outside this " +
            'submission: ' + (($foreignDirty | Select-Object -First 5) -join ' | ')) `
        -Remediation 'Commit, stash, or discard the changes so synchronization starts from a clean state.'))

    $manifestFull = Join-Path $clonePath ($Config.manifestPath -replace '/', [IO.Path]::DirectorySeparatorChar)
    $untrackedManifest = @()
    if (Test-Path -LiteralPath $manifestFull) {
        $untrackedManifest = @((Invoke-TigerCloneGit -ClonePath $clonePath `
            -GitArgs @('status', '--porcelain', '--untracked-files=all', '--', $Config.manifestPath)).Output `
            -split "\r?\n" | Where-Object { $_ } | Where-Object { -not (& $isOwned (& $porcelainPath $_)) })
    }
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/no-untracked-manifests' `
        -Condition ($untrackedManifest.Count -eq 0) `
        -PassObserved ("Nothing untracked under $($Config.manifestPath)" +
            "$(if ($null -ne $ownedPrefix) { " outside $SubmissionPath" }) would be overwritten.") `
        -FailObserved ("Untracked or modified files exist under $($Config.manifestPath): " +
            (($untrackedManifest | Select-Object -First 5) -join ' | ')) `
        -Remediation 'Remove the stray manifest files before a submission branch is prepared.'))

    $interrupted = @(Get-TigerWinGetPkgsInterruptedOperation -ClonePath $clonePath)
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/no-interrupted-op' `
        -Condition ($interrupted.Count -eq 0) `
        -PassObserved 'No merge, rebase, cherry-pick, revert, bisect, or sequencer run is in progress.' `
        -FailObserved "An interrupted Git operation is active: $($interrupted -join ', ')." `
        -Remediation 'Finish or abort the operation (for example git rebase --abort) before rerunning.'))

    $checks.ToArray()
}

function Get-TigerWinGetPkgsPreviousPr {
    <#
        .SYNOPSIS
        The project-specific previous-PR gate.

        .DESCRIPTION
        Finds the most recent microsoft/winget-pkgs pull request whose head is on
        the fork and whose head branch starts with the configured prefix
        (ItTiger-TigerMarkView-). Open or draft blocks; merged or manually closed
        passes; none passes. The BLOCKED evidence carries the PR number, URL,
        state, draft flag, and head branch.

        The lookup is title- and head-scoped, never "the latest PR by the user".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Cli,

        [Parameter(Mandatory)]
        [object] $Config
    )

    $query = "repo:$($Config.upstreamSlug) is:pr New version: $($Config.packageIdentifier)"
    $search = & $Cli.tryApi ("search/issues?per_page=50&sort=created&order=desc&q=" + [Uri]::EscapeDataString($query))
    if (-not $search.ok) {
        return [pscustomobject]@{
            check = (New-TigerMarkViewReleaseCheck -Id 'winget-pkgs/previous-pr' -Status 'BLOCKED' `
                -Observed 'Could not query previous winget-pkgs pull requests.' `
                -Evidence ($search.stderr -replace '\s+', ' ') `
                -Remediation 'Confirm the gh session can read microsoft/winget-pkgs, then rerun.')
            pullRequest = $null
        }
    }

    $items = @()
    if ($null -ne $search.data -and $null -ne $search.data.PSObject.Properties['items']) {
        $items = @($search.data.items)
    }

    foreach ($item in $items) {
        if ($null -eq $item.PSObject.Properties['pull_request']) { continue }
        $number = [int] $item.number
        $pr = & $Cli.tryApi "repos/$($Config.upstreamSlug)/pulls/$number"
        if (-not $pr.ok -or $null -eq $pr.data) { continue }
        $headRef = [string] $pr.data.head.ref
        $headOwner = ''
        if ($null -ne $pr.data.head.PSObject.Properties['repo'] -and $null -ne $pr.data.head.repo) {
            $headOwner = [string] $pr.data.head.repo.owner.login
        }
        if ($headOwner.ToLowerInvariant() -cne $Config.forkOwner.ToLowerInvariant()) { continue }
        if (-not $headRef.StartsWith($Config.branchPrefix)) { continue }

        $state = [string] $pr.data.state
        $isDraft = $null -ne $pr.data.PSObject.Properties['draft'] -and [bool] $pr.data.draft
        $isMerged = $null -ne $pr.data.PSObject.Properties['merged_at'] -and
            -not [string]::IsNullOrWhiteSpace([string] $pr.data.merged_at)
        $info = [pscustomobject][ordered]@{
            number = $number
            url = [string] $pr.data.html_url
            state = $state
            draft = $isDraft
            merged = $isMerged
            headRef = $headRef
        }
        $evidence = "PR #$number ($($info.url)) state=$state draft=$isDraft merged=$isMerged head=$headRef"

        $blocking = $state -ceq 'open'
        if ($blocking) {
            return [pscustomobject]@{
                check = (New-TigerMarkViewReleaseCheck -Id 'winget-pkgs/previous-pr' -Status 'BLOCKED' `
                    -Observed ("The most recent TigerMarkView winget-pkgs PR (#$number) is " +
                        "$(if ($isDraft) { 'an open draft' } else { 'still open' }). No sync, branch, copy, commit, or push occurred.") `
                    -Expected 'the most recent matching PR merged or closed' -Evidence $evidence `
                    -Remediation "Close, merge, or withdraw PR #$number, then rerun.")
                pullRequest = $info
            }
        }
        return [pscustomobject]@{
            check = (New-TigerMarkViewReleaseCheck -Id 'winget-pkgs/previous-pr' -Status 'PASS' `
                -Observed ("The most recent TigerMarkView winget-pkgs PR (#$number) is " +
                    "$(if ($isMerged) { 'merged' } else { 'closed' }).") `
                -Evidence $evidence)
            pullRequest = $info
        }
    }

    [pscustomobject]@{
        check = (New-TigerMarkViewReleaseCheck -Id 'winget-pkgs/previous-pr' -Status 'PASS' `
            -Observed 'No prior TigerMarkView pull request to microsoft/winget-pkgs was found.')
        pullRequest = $null
    }
}
