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

    Nothing here fetches, writes, resets, or pushes. Mutation belongs to the
    guarded submission phase, which runs only after every check here is PASS.
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
        Runs a read-only git command in a clone and returns exit code and output.
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config
    )

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

    $originUrl = (Invoke-TigerCloneGit -ClonePath $clonePath -GitArgs @('remote', 'get-url', 'origin')).Output
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/origin' `
        -Condition (Test-TigerGitHubSlugMatch -Url $originUrl -ExpectedSlug $Config.forkSlug) `
        -PassObserved "origin is $($Config.forkSlug)." `
        -FailObserved "origin is '$originUrl', not $($Config.forkSlug)." `
        -Expected $Config.forkSlug -Evidence $originUrl `
        -Remediation 'Never silently rewrite the remote; resolve the clone identity by hand.'))

    $upstreamUrl = (Invoke-TigerCloneGit -ClonePath $clonePath -GitArgs @('remote', 'get-url', 'upstream')).Output
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/upstream' `
        -Condition (Test-TigerGitHubSlugMatch -Url $upstreamUrl -ExpectedSlug $Config.upstreamSlug) `
        -PassObserved "upstream is $($Config.upstreamSlug)." `
        -FailObserved "upstream is '$upstreamUrl', not $($Config.upstreamSlug)." `
        -Expected $Config.upstreamSlug -Evidence $upstreamUrl `
        -Remediation "Add it: git -C `"$clonePath`" remote add upstream $($Config.upstreamUrl)"))

    $currentBranch = (Invoke-TigerCloneGit -ClonePath $clonePath -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')).Output
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/default-branch' `
        -Condition ($currentBranch -ceq $Config.defaultBranch) `
        -PassObserved "HEAD is on '$($Config.defaultBranch)'." `
        -FailObserved "HEAD is on '$currentBranch', not '$($Config.defaultBranch)'." `
        -FailStatus 'WARN' -Evidence $currentBranch `
        -Remediation "Check out '$($Config.defaultBranch)' before synchronizing."))

    $porcelain = (Invoke-TigerCloneGit -ClonePath $clonePath -GitArgs @('status', '--porcelain')).Output
    $dirtyLines = @($porcelain -split "\r?\n" | Where-Object { $_ })
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/clean' `
        -Condition ($dirtyLines.Count -eq 0) `
        -PassObserved 'The worktree and index are clean.' `
        -FailObserved ("The worktree has $($dirtyLines.Count) uncommitted change(s): " +
            (($dirtyLines | Select-Object -First 5) -join ' | ')) `
        -Remediation 'Commit, stash, or discard the changes so synchronization starts from a clean state.'))

    $manifestFull = Join-Path $clonePath ($Config.manifestPath -replace '/', [IO.Path]::DirectorySeparatorChar)
    $untrackedManifest = @()
    if (Test-Path -LiteralPath $manifestFull) {
        $untrackedManifest = @((Invoke-TigerCloneGit -ClonePath $clonePath `
            -GitArgs @('status', '--porcelain', '--untracked-files=all', '--', $Config.manifestPath)).Output `
            -split "\r?\n" | Where-Object { $_ })
    }
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/no-untracked-manifests' `
        -Condition ($untrackedManifest.Count -eq 0) `
        -PassObserved "Nothing untracked under $($Config.manifestPath) would be overwritten." `
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
