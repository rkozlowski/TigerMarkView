#Requires -Version 7.0
<#
    .SYNOPSIS
    The guarded winget-pkgs mutation: fork synchronization, submission branch,
    exact manifest copy, final diff, commit, and push.

    .DESCRIPTION
    Dot-source this file. Everything here writes, so nothing here runs until every
    read-only gate in WinGetPkgsClone.ps1 has passed and the published release has
    been validated. The entry point is Invoke-TigerWinGetPkgsSubmission, which the
    maintainer-facing Prepare-TigerMarkViewWinGetSubmission.ps1 calls once.

    Three rules shape all of it:

      - every operation is modelled as absent, already correct, or conflicting.
        Absent is created, already correct is verified and reported PASS, and
        conflicting stops with evidence. Nothing is silently repaired;
      - only fast-forward and additive operations are used. There is no reset, no
        force push, no branch deletion, and no rewriting of anything a human or
        another tool may have put there; and
      - the three sealed manifests are copied byte for byte and then rehashed at
        the destination. A submission that does not hash to the sealed set never
        reaches a commit.

    A second complete run makes no new commit and no new push: it recognises the
    synchronized fork, the existing branch, the identical files, the existing
    commit, and the already-pushed remote branch, and ends at the same handoff.

    The pull request itself is never created here. That decision stays with the
    human, as does publishing the GitHub release.
#>

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'TigerMarkViewWinGet.ps1')
. (Join-Path $PSScriptRoot 'WinGetPkgsClone.ps1')

function Get-TigerWinGetPkgsSubmissionBranchName {
    <#
        .SYNOPSIS
        The project-specific submission branch for a version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Version
    )

    "$($Config.branchPrefix)$Version"
}

function Get-TigerWinGetPkgsSubmissionDestination {
    <#
        .SYNOPSIS
        The winget-pkgs path a version's manifests are submitted at, in both
        repository-relative (forward slash) and filesystem form.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Version
    )

    $relative = "$($Config.manifestPath)/$Version"
    [pscustomobject][ordered]@{
        relative = $relative
        full = [IO.Path]::GetFullPath((Join-Path $Config.clonePath ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)))
    }
}

function Test-TigerWinGetPkgsCommitIdentity {
    <#
        .SYNOPSIS
        Proves git can author a commit in the clone before anything is copied.

        .DESCRIPTION
        A missing user.name or user.email fails at `git commit`, after the files
        have already been written. Asking git for the identity it would use turns
        that into a preflight with an obvious repair.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config
    )

    $identity = Invoke-TigerCloneGit -ClonePath $Config.clonePath -GitArgs @('var', 'GIT_COMMITTER_IDENT')
    New-TigerMarkViewReleaseAssertion -Id 'clone/commit-identity' `
        -Condition ($identity.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($identity.Output)) `
        -PassObserved "git can author a commit in the clone as $($identity.Output)." `
        -FailObserved 'git has no committer identity for this clone, so a commit would fail after the copy.' `
        -Evidence $identity.Output `
        -Remediation ("Set one: git -C `"$($Config.clonePath)`" config user.name '<name>' and " +
            "git -C `"$($Config.clonePath)`" config user.email '<email>'.")
}

function New-TigerWinGetPkgsClone {
    <#
        .SYNOPSIS
        Creates the dedicated clone when, and only when, its path is absent.

        .DESCRIPTION
        Absent is the one state this creates. An existing directory - a partial
        clone, an unrelated repository, or a plain folder - is never adopted,
        emptied, or reconfigured here; Test-TigerWinGetPkgsCloneIdentity has
        already said what is wrong with it, and resolving that is a human decision.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config
    )

    $checks = [Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $Config.clonePath) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'clone/create' -Status 'FAIL' `
            -Observed "$($Config.clonePath) already exists, so it was not created." `
            -Remediation 'Resolve the existing directory by hand; nothing here adopts or empties one.'))
        return $checks.ToArray()
    }

    $parent = Split-Path -Parent $Config.clonePath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $clone = Invoke-TigerCloneGit -ClonePath $parent -GitArgs @('clone', $Config.forkUrl, $Config.clonePath)
    if ($clone.ExitCode -ne 0) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'clone/create' -Status 'FAIL' `
            -Observed "Cloning $($Config.forkSlug) into $($Config.clonePath) failed." `
            -Evidence ($clone.Output -replace '\s+', ' ') `
            -Remediation 'Confirm the fork exists and the session can read it, then rerun.'))
        return $checks.ToArray()
    }

    $remote = Invoke-TigerCloneGit -ClonePath $Config.clonePath `
        -GitArgs @('remote', 'add', 'upstream', $Config.upstreamUrl)
    if ($remote.ExitCode -ne 0) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'clone/create' -Status 'FAIL' `
            -Observed "The clone was created but 'upstream' could not be added." `
            -Evidence ($remote.Output -replace '\s+', ' ')))
        return $checks.ToArray()
    }

    $fetch = Invoke-TigerCloneGit -ClonePath $Config.clonePath -GitArgs @('fetch', '--quiet', 'upstream')
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'clone/create' `
        -Condition ($fetch.ExitCode -eq 0) `
        -PassObserved ("Cloned $($Config.forkSlug) into $($Config.clonePath) and added " +
            "upstream $($Config.upstreamSlug).") `
        -FailObserved "The clone was created but 'git fetch upstream' failed." `
        -Evidence ($fetch.Output -replace '\s+', ' ')))
    $checks.ToArray()
}

function Sync-TigerWinGetPkgsFork {
    <#
        .SYNOPSIS
        Fast-forwards the fork's default branch to upstream and pushes it.

        .DESCRIPTION
        Only fast-forwards. A local or fork `master` carrying commits upstream does
        not have is not rebased, reset, or force-pushed away: it is evidence that
        something unexpected happened to the clone, and it stops the run. An
        already-synchronized fork is verified and reported PASS without pushing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config
    )

    $branch = $Config.defaultBranch
    $clone = $Config.clonePath
    $checks = [Collections.Generic.List[object]]::new()
    $state = [ordered]@{ upstreamSha = $null; localSha = $null; forkSha = $null; fastForwarded = $false; pushed = $false }

    foreach ($remote in @('upstream', 'origin')) {
        $fetch = Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('fetch', '--quiet', '--prune', $remote)
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id "sync/fetch-$remote" `
            -Condition ($fetch.ExitCode -eq 0) `
            -PassObserved "Fetched $remote." `
            -FailObserved "git fetch $remote failed." `
            -Evidence ($fetch.Output -replace '\s+', ' ') `
            -Remediation 'Confirm network access and that the session can read both repositories.'))
        if ($fetch.ExitCode -ne 0) {
            return [pscustomobject]@{ checks = $checks.ToArray(); state = [pscustomobject] $state }
        }
    }

    $upstreamSha = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('rev-parse', "upstream/$branch")).Output
    $originSha = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('rev-parse', "origin/$branch")).Output
    $localSha = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('rev-parse', $branch)).Output
    $resolved = $upstreamSha -match '^[0-9a-f]{40}$' -and $originSha -match '^[0-9a-f]{40}$' -and
        $localSha -match '^[0-9a-f]{40}$'
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'sync/branches-resolved' `
        -Condition $resolved `
        -PassObserved "upstream/$branch, origin/$branch, and $branch all resolve." `
        -FailObserved ("At least one of upstream/$branch, origin/$branch, or $branch does not resolve to a " +
            "commit (upstream '$upstreamSha', origin '$originSha', local '$localSha').") `
        -Remediation "Resolve the clone's branch state by hand."))
    if (-not $resolved) {
        return [pscustomobject]@{ checks = $checks.ToArray(); state = [pscustomobject] $state }
    }
    $state.upstreamSha = $upstreamSha

    # Commits on the fork that upstream does not have. Discarding them would be a
    # rewrite, so they stop the run instead.
    $ahead = (Invoke-TigerCloneGit -ClonePath $clone `
        -GitArgs @('rev-list', '--count', "upstream/$branch..$branch")).Output
    $forkAhead = (Invoke-TigerCloneGit -ClonePath $clone `
        -GitArgs @('rev-list', '--count', "upstream/$branch..origin/$branch")).Output
    $divergent = ($ahead -cne '0') -or ($forkAhead -cne '0')
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'sync/no-fork-only-commits' `
        -Condition (-not $divergent) `
        -PassObserved "Neither $branch nor origin/$branch carries commits upstream/$branch does not have." `
        -FailObserved ("$branch is $ahead commit(s) and origin/$branch is $forkAhead commit(s) ahead of " +
            "upstream/$branch. Nothing was synchronized: discarding them would rewrite history.") `
        -Evidence "local ahead=$ahead, fork ahead=$forkAhead" `
        -Remediation 'Resolve the extra commits by hand, then rerun.'))
    if ($divergent) {
        return [pscustomobject]@{ checks = $checks.ToArray(); state = [pscustomobject] $state }
    }

    if ($localSha -cne $upstreamSha) {
        $checkout = Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('checkout', '--quiet', $branch)
        if ($checkout.ExitCode -ne 0) {
            $checks.Add((New-TigerMarkViewReleaseCheck -Id 'sync/fast-forward' -Status 'FAIL' `
                -Observed "Could not check out $branch." -Evidence ($checkout.Output -replace '\s+', ' ')))
            return [pscustomobject]@{ checks = $checks.ToArray(); state = [pscustomobject] $state }
        }
        $merge = Invoke-TigerCloneGit -ClonePath $clone `
            -GitArgs @('merge', '--ff-only', '--quiet', "upstream/$branch")
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'sync/fast-forward' `
            -Condition ($merge.ExitCode -eq 0) `
            -PassObserved "$branch fast-forwarded to upstream/$branch ($upstreamSha)." `
            -FailObserved "$branch could not be fast-forwarded to upstream/$branch." `
            -Evidence ($merge.Output -replace '\s+', ' ') `
            -Remediation 'Resolve the branch state by hand; no non-fast-forward operation is performed here.'))
        if ($merge.ExitCode -ne 0) {
            return [pscustomobject]@{ checks = $checks.ToArray(); state = [pscustomobject] $state }
        }
        $state.fastForwarded = $true
    }
    else {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'sync/fast-forward' -Status 'PASS' `
            -Observed "$branch is already at upstream/$branch ($upstreamSha)." -Evidence $upstreamSha))
    }
    $state.localSha = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('rev-parse', $branch)).Output

    if ($originSha -cne $upstreamSha) {
        $push = Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('push', '--quiet', 'origin', "${branch}:${branch}")
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'sync/push-fork' `
            -Condition ($push.ExitCode -eq 0) `
            -PassObserved "Pushed the fast-forwarded $branch to $($Config.forkSlug)." `
            -FailObserved "Pushing $branch to $($Config.forkSlug) failed." `
            -Evidence ($push.Output -replace '\s+', ' ')))
        if ($push.ExitCode -ne 0) {
            return [pscustomobject]@{ checks = $checks.ToArray(); state = [pscustomobject] $state }
        }
        $state.pushed = $true
        $null = Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('fetch', '--quiet', 'origin')
    }
    else {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'sync/push-fork' -Status 'PASS' `
            -Observed "origin/$branch is already at upstream/$branch; nothing was pushed." -Evidence $originSha))
    }

    $state.forkSha = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('rev-parse', "origin/$branch")).Output
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'sync/fork-verified' `
        -Condition ($state.forkSha -ceq $upstreamSha) `
        -PassObserved "origin/$branch is verified at $upstreamSha." `
        -FailObserved "origin/$branch is at '$($state.forkSha)', not upstream's $upstreamSha." `
        -Evidence $state.forkSha `
        -Remediation 'Resolve the fork state by hand; nothing is force-pushed here.'))

    [pscustomobject]@{ checks = $checks.ToArray(); state = [pscustomobject] $state }
}

function Set-TigerWinGetPkgsSubmissionBranch {
    <#
        .SYNOPSIS
        Puts the clone on the submission branch, creating it from current upstream.

        .DESCRIPTION
        Absent: created from upstream/<default branch>, so the branch a reviewer
        sees is a single commit on current upstream. Already correct: an existing
        branch that contains exactly current upstream plus at most one commit of
        our own is reused, which is what makes an interrupted run resumable.
        Conflicting: a branch based on something else, or carrying commits that are
        not this submission, stops the run. It is never deleted or reset here.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Version
    )

    $clone = $Config.clonePath
    $branch = Get-TigerWinGetPkgsSubmissionBranchName -Config $Config -Version $Version
    $base = "upstream/$($Config.defaultBranch)"
    $baseSha = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('rev-parse', $base)).Output
    $checks = [Collections.Generic.List[object]]::new()

    $exists = (Invoke-TigerCloneGit -ClonePath $clone `
        -GitArgs @('rev-parse', '--verify', '--quiet', "refs/heads/$branch")).ExitCode -eq 0
    if (-not $exists) {
        $create = Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('checkout', '--quiet', '-b', $branch, $base)
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'branch/create' `
            -Condition ($create.ExitCode -eq 0) `
            -PassObserved "Created $branch from $base ($baseSha)." `
            -FailObserved "Could not create $branch from $base." `
            -Evidence ($create.Output -replace '\s+', ' ')))
        return [pscustomobject]@{
            checks = $checks.ToArray()
            branch = $branch
            baseSha = $baseSha
            created = ($create.ExitCode -eq 0)
        }
    }

    # An existing branch has to be this submission's branch, on this upstream.
    $containsBase = (Invoke-TigerCloneGit -ClonePath $clone `
        -GitArgs @('merge-base', '--is-ancestor', $base, $branch)).ExitCode -eq 0
    $ownCommits = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('rev-list', '--count', "$base..$branch")).Output
    $resumable = $containsBase -and ($ownCommits -cin @('0', '1'))
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'branch/resume' `
        -Condition $resumable `
        -PassObserved ("$branch already exists on current $base with $ownCommits submission commit(s); " +
            'reusing it.') `
        -FailObserved ("$branch exists but is not a resumable submission branch: it " +
            "$(if ($containsBase) { "carries $ownCommits commits" } else { "is not based on current $base" }).") `
        -Evidence "base=$baseSha contains-base=$containsBase own-commits=$ownCommits" `
        -Remediation ("Inspect and remove that branch by hand (git -C `"$clone`" branch -D $branch) " +
            'once you are sure it is not needed; nothing here deletes or resets a branch.')))
    if (-not $resumable) {
        return [pscustomobject]@{ checks = $checks.ToArray(); branch = $branch; baseSha = $baseSha; created = $false }
    }

    $checkout = Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('checkout', '--quiet', $branch)
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'branch/checkout' `
        -Condition ($checkout.ExitCode -eq 0) `
        -PassObserved "The clone is on $branch." `
        -FailObserved "Could not check out $branch." `
        -Evidence ($checkout.Output -replace '\s+', ' ')))

    [pscustomobject]@{ checks = $checks.ToArray(); branch = $branch; baseSha = $baseSha; created = $false }
}

function Copy-TigerWinGetPkgsSubmission {
    <#
        .SYNOPSIS
        Copies the three sealed manifests to the submission path and rehashes them.

        .DESCRIPTION
        Only the sealed files are written, and only into the version directory. The
        destination is then read back with the same reader the seal used, so a copy
        that changed a byte - or a stray file already sitting there - is a stop
        rather than a surprise in review.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [object] $Submission
    )

    $destination = Get-TigerWinGetPkgsSubmissionDestination -Config $Config -Version $Version
    $checks = [Collections.Generic.List[object]]::new()

    # The destination must stay inside the clone: a manifest path that escaped it
    # would write outside the repository this run has proven anything about.
    $cloneRoot = [IO.Path]::GetFullPath($Config.clonePath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $destination.full.StartsWith($cloneRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/copy' -Status 'FAIL' `
            -Observed "The submission destination '$($destination.full)' is outside the clone." `
            -Remediation 'Correct manifestPath in eng/winget/winget-pkgs.clone.json.'))
        return [pscustomobject]@{ checks = $checks.ToArray(); destination = $destination }
    }

    New-Item -ItemType Directory -Path $destination.full -Force | Out-Null
    $copyFailure = $null
    try {
        foreach ($document in @($Submission.documents)) {
            Copy-Item -LiteralPath $document.path -Destination (Join-Path $destination.full $document.name) -Force
        }
    }
    catch {
        $copyFailure = $_.Exception.Message
    }
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/copy' `
        -Condition ($null -eq $copyFailure) `
        -PassObserved "Copied the three sealed manifests to $($destination.relative)." `
        -FailObserved "Copying the sealed manifests to $($destination.relative) failed: $copyFailure"))
    if ($null -ne $copyFailure) {
        return [pscustomobject]@{ checks = $checks.ToArray(); destination = $destination }
    }

    $placedFailure = $null
    $placed = $null
    try { $placed = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $destination.full -Version $Version }
    catch { $placedFailure = $_.Exception.Message }
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/destination-shape' `
        -Condition ($null -ne $placed) `
        -PassObserved "$($destination.relative) holds exactly the three submission manifests." `
        -FailObserved "$($destination.relative) is not a submission set: $placedFailure" `
        -Remediation 'Remove anything else under the version directory and rerun.'))
    if ($null -eq $placed) {
        return [pscustomobject]@{ checks = $checks.ToArray(); destination = $destination }
    }

    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/destination-digest' `
        -Condition ($placed.digest -ceq $Submission.digest) `
        -PassObserved "The copied manifests reproduce the sealed submission digest $($Submission.digest)." `
        -FailObserved ("The copied manifests hash to '$($placed.digest)'; the sealed set hashes to " +
            "'$($Submission.digest)'.") `
        -Evidence $placed.digest `
        -Remediation 'Never edit a manifest at the destination; rerun from the sealed set.'))

    [pscustomobject]@{ checks = $checks.ToArray(); destination = $destination; placed = $placed }
}

function Test-TigerWinGetPkgsSubmissionDiff {
    <#
        .SYNOPSIS
        Proves the branch changes exactly the version directory and nothing else.

        .DESCRIPTION
        Two views have to agree before a commit: the worktree may only carry the
        expected new files, and the branch as a whole may only differ from upstream
        by those same three paths. Together they catch a stray edit in the clone and
        a leftover change from an earlier interrupted run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [object] $Submission,

        [Parameter(Mandatory)]
        [string] $Branch
    )

    $clone = $Config.clonePath
    $destination = Get-TigerWinGetPkgsSubmissionDestination -Config $Config -Version $Version
    $expected = @($Submission.documents | ForEach-Object { "$($destination.relative)/$($_.name)" })
    $checks = [Collections.Generic.List[object]]::new()

    $porcelain = (Invoke-TigerCloneGit -ClonePath $clone `
        -GitArgs @('status', '--porcelain', '--untracked-files=all')).Output
    $worktreePaths = @($porcelain -split "\r?\n" | Where-Object { $_ } |
        ForEach-Object { ($_ -replace '^.{3}', '').Trim().Trim('"') -replace '\\', '/' })
    $unexpected = @($worktreePaths | Where-Object { $_ -cnotin $expected })
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/worktree-diff' `
        -Condition ($unexpected.Count -eq 0) `
        -PassObserved ("The worktree carries only the $($worktreePaths.Count) expected submission file(s) " +
            "under $($destination.relative).") `
        -FailObserved "The worktree carries changes outside the submission: $($unexpected -join ', ')." `
        -Evidence ($worktreePaths -join ', ') `
        -Remediation 'Revert the unrelated changes in the clone, then rerun.'))

    $base = "upstream/$($Config.defaultBranch)"
    $branchPaths = @((Invoke-TigerCloneGit -ClonePath $clone `
        -GitArgs @('diff', '--name-only', "$base..$Branch")).Output -split "\r?\n" |
        Where-Object { $_ } | ForEach-Object { $_.Trim() -replace '\\', '/' })
    $branchUnexpected = @($branchPaths | Where-Object { $_ -cnotin $expected })
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/branch-diff' `
        -Condition ($branchUnexpected.Count -eq 0) `
        -PassObserved "$Branch differs from $base only under $($destination.relative)." `
        -FailObserved "$Branch changes files outside the submission: $($branchUnexpected -join ', ')." `
        -Evidence ($branchPaths -join ', ') `
        -Remediation 'Resolve the branch by hand; nothing here rewrites a commit.'))

    [pscustomobject]@{
        checks = $checks.ToArray()
        expectedPaths = $expected
        worktreePaths = $worktreePaths
        branchPaths = $branchPaths
    }
}

function Save-TigerWinGetPkgsSubmissionCommit {
    <#
        .SYNOPSIS
        Stages exactly the version directory and commits it once.

        .DESCRIPTION
        The commit subject is deterministic, so a rerun that finds the work already
        committed recognises it and adds nothing. Only the version directory is
        staged: `git add` is path-limited, so an unrelated change someone left in
        the clone can never ride along in this commit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [string] $Branch
    )

    $clone = $Config.clonePath
    $destination = Get-TigerWinGetPkgsSubmissionDestination -Config $Config -Version $Version
    $message = "New version: $($Config.packageIdentifier) version $Version"
    $checks = [Collections.Generic.List[object]]::new()

    $add = Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('add', '--', $destination.relative)
    if ($add.ExitCode -ne 0) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/commit' -Status 'FAIL' `
            -Observed "Staging $($destination.relative) failed." -Evidence ($add.Output -replace '\s+', ' ')))
        return [pscustomobject]@{ checks = $checks.ToArray(); commitSha = $null; committed = $false }
    }

    $staged = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('diff', '--cached', '--name-only')).Output
    $hasStagedChanges = -not [string]::IsNullOrWhiteSpace($staged)
    $committed = $false
    if ($hasStagedChanges) {
        $commit = Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('commit', '--quiet', '-m', $message)
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/commit' `
            -Condition ($commit.ExitCode -eq 0) `
            -PassObserved "Committed '$message'." `
            -FailObserved "The submission commit failed." `
            -Evidence ($commit.Output -replace '\s+', ' ')))
        if ($commit.ExitCode -ne 0) {
            return [pscustomobject]@{ checks = $checks.ToArray(); commitSha = $null; committed = $false }
        }
        $committed = $true
    }

    $subject = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('log', '-1', '--format=%s', $Branch)).Output
    $commitSha = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('rev-parse', $Branch)).Output
    if (-not $committed) {
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/commit' `
            -Condition ($subject -ceq $message) `
            -PassObserved "The submission is already committed as '$message'; nothing new was committed." `
            -FailObserved ("Nothing was staged and the branch tip is '$subject', not '$message'. The branch " +
                'does not carry this submission.') `
            -Evidence $commitSha `
            -Remediation 'Resolve the branch by hand, then rerun.'))
    }

    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/commit-subject' `
        -Condition ($subject -ceq $message) `
        -PassObserved "The branch tip subject is the expected '$message'." `
        -FailObserved "The branch tip subject is '$subject', not '$message'." `
        -Evidence $commitSha))

    $clean = (Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('status', '--porcelain')).Output
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/committed-clean' `
        -Condition ([string]::IsNullOrWhiteSpace($clean)) `
        -PassObserved 'The worktree is clean after the commit.' `
        -FailObserved "The worktree still carries changes after the commit: $($clean -replace '\s+', ' ')." `
        -Remediation 'Resolve the leftover changes by hand.'))

    [pscustomobject]@{ checks = $checks.ToArray(); commitSha = $commitSha; committed = $committed; message = $message }
}

function Push-TigerWinGetPkgsSubmissionBranch {
    <#
        .SYNOPSIS
        Pushes the submission branch to the fork and verifies the remote tip.

        .DESCRIPTION
        A remote branch that already points at this commit is the resumed case and
        is reported PASS without a push. A remote branch pointing somewhere else is
        a stop: overwriting it would need a force push, which this design does not
        authorize.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Branch,

        [Parameter(Mandatory)]
        [string] $CommitSha
    )

    $clone = $Config.clonePath
    $checks = [Collections.Generic.List[object]]::new()

    $remoteLine = (Invoke-TigerCloneGit -ClonePath $clone `
        -GitArgs @('ls-remote', '--heads', 'origin', "refs/heads/$Branch")).Output
    $remoteSha = $null
    if ($remoteLine -match '^(?<sha>[0-9a-f]{40})\s') { $remoteSha = $Matches.sha }

    $pushed = $false
    if ($null -ne $remoteSha -and $remoteSha -cne $CommitSha) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/push' -Status 'FAIL' `
            -Observed ("origin/$Branch already points at $remoteSha, not the submission commit $CommitSha. " +
                'Nothing was pushed.') `
            -Expected $CommitSha -Evidence $remoteSha `
            -Remediation ("Inspect the remote branch and remove it deliberately if it is stale; " +
                'no force push is performed here.')))
        return [pscustomobject]@{ checks = $checks.ToArray(); remoteSha = $remoteSha; pushed = $false }
    }

    if ($null -eq $remoteSha) {
        $push = Invoke-TigerCloneGit -ClonePath $clone -GitArgs @('push', '--quiet', 'origin', "${Branch}:${Branch}")
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/push' `
            -Condition ($push.ExitCode -eq 0) `
            -PassObserved "Pushed $Branch to $($Config.forkSlug)." `
            -FailObserved "Pushing $Branch to $($Config.forkSlug) failed." `
            -Evidence ($push.Output -replace '\s+', ' ')))
        if ($push.ExitCode -ne 0) {
            return [pscustomobject]@{ checks = $checks.ToArray(); remoteSha = $null; pushed = $false }
        }
        $pushed = $true
    }
    else {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/push' -Status 'PASS' `
            -Observed "origin/$Branch is already at the submission commit; nothing was pushed." `
            -Evidence $remoteSha))
    }

    $verifyLine = (Invoke-TigerCloneGit -ClonePath $clone `
        -GitArgs @('ls-remote', '--heads', 'origin', "refs/heads/$Branch")).Output
    $verified = $null
    if ($verifyLine -match '^(?<sha>[0-9a-f]{40})\s') { $verified = $Matches.sha }
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/push-verified' `
        -Condition ($verified -ceq $CommitSha) `
        -PassObserved "$($Config.forkSlug) $Branch is verified at $CommitSha." `
        -FailObserved "$($Config.forkSlug) $Branch is at '$verified', not $CommitSha." `
        -Evidence $verified `
        -Remediation 'Re-check the fork branch before opening the pull request.'))

    [pscustomobject]@{ checks = $checks.ToArray(); remoteSha = $verified; pushed = $pushed }
}

function Invoke-TigerWinGetPkgsSubmission {
    <#
        .SYNOPSIS
        The whole guarded winget-pkgs preparation, from clone safety to pushed
        branch, stopping before the pull request.

        .DESCRIPTION
        Order matters: every read-only gate runs first, then the previous-PR gate,
        and only then does anything write. A BLOCKED or FAIL result at any point
        returns immediately with the evidence, so no partially-prepared branch is
        left behind by a check that was going to fail anyway.

        -PlanOnly performs every read-only gate and stops. It can report BLOCKED or
        FAIL, but never a submission PASS: no branch, copy, commit, or push occurs,
        so there is nothing for a human to open a pull request from.

        .PARAMETER ValidateCommand
        The manifest validator to run against the copied destination. Defaults to
        `winget validate`. Tests substitute a stub so no test needs WinGet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Cli,

        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [object] $Submission,

        [scriptblock] $ValidateCommand,

        [switch] $PlanOnly
    )

    $checks = [Collections.Generic.List[object]]::new()
    $state = [ordered]@{
        clonePath = $Config.clonePath
        branch = Get-TigerWinGetPkgsSubmissionBranchName -Config $Config -Version $Version
        commitSha = $null
        remoteSha = $null
        pushed = $false
        planOnly = [bool] $PlanOnly
        compareUrl = $null
        pullRequestCommand = $null
    }
    $stop = {
        [pscustomobject]@{ checks = $checks.ToArray(); state = [pscustomobject] $state }
    }
    $blocking = { @($checks | Where-Object { $_.status -ceq 'FAIL' -or $_.status -ceq 'BLOCKED' }).Count -gt 0 }

    # 1. The clone. An absent one is created here (that is the only creation this
    #    performs); a wrong, dirty, or interrupted one is never adopted.
    $ownedPath = (Get-TigerWinGetPkgsSubmissionDestination -Config $Config -Version $Version).relative
    $identity = @(Test-TigerWinGetPkgsCloneIdentity -Config $Config -SubmissionBranch $state.branch `
        -SubmissionPath $ownedPath)
    $absent = @($identity | Where-Object { $_.id -ceq 'clone/exists' -and $_.status -ceq 'BLOCKED' }).Count -gt 0
    if ($absent -and -not $PlanOnly) {
        foreach ($check in (New-TigerWinGetPkgsClone -Config $Config)) { $checks.Add($check) }
        if (& $blocking) { return & $stop }
        $identity = @(Test-TigerWinGetPkgsCloneIdentity -Config $Config -SubmissionBranch $state.branch `
            -SubmissionPath $ownedPath)
    }
    foreach ($check in $identity) { $checks.Add($check) }
    if (& $blocking) { return & $stop }

    $checks.Add((Test-TigerWinGetPkgsCommitIdentity -Config $Config))
    if (& $blocking) { return & $stop }

    # 2. The previous-PR gate, before any fetch, synchronization, or branch work.
    $previous = Get-TigerWinGetPkgsPreviousPr -Cli $Cli -Config $Config
    $checks.Add($previous.check)
    if (& $blocking) { return & $stop }

    if ($PlanOnly) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/plan-only' -Status 'BLOCKED' `
            -Observed ('-PlanOnly was requested: every read-only gate passed and nothing was ' +
                'synchronized, branched, copied, committed, or pushed.') `
            -Expected 'a complete run that prepares the submission branch' `
            -Remediation 'Rerun without -PlanOnly to prepare the submission.'))
        return & $stop
    }

    # 3. Fork synchronization, fast-forward only.
    $sync = Sync-TigerWinGetPkgsFork -Config $Config
    foreach ($check in $sync.checks) { $checks.Add($check) }
    if (& $blocking) { return & $stop }

    # 4. The submission branch, created from current upstream or resumed.
    $branchResult = Set-TigerWinGetPkgsSubmissionBranch -Config $Config -Version $Version
    foreach ($check in $branchResult.checks) { $checks.Add($check) }
    $state.branch = $branchResult.branch
    if (& $blocking) { return & $stop }

    # 5. The exact sealed bytes, rehashed where they landed.
    $copy = Copy-TigerWinGetPkgsSubmission -Config $Config -Version $Version -Submission $Submission
    foreach ($check in $copy.checks) { $checks.Add($check) }
    if (& $blocking) { return & $stop }

    # 6. WinGet's opinion of the destination, not just of the source directory.
    $validationFailure = $null
    try {
        if ($null -eq $ValidateCommand) {
            $null = Invoke-TigerMarkViewWinGetValidation -ManifestDirectory $copy.destination.full
        }
        else {
            $null = & $ValidateCommand $copy.destination.full
        }
    }
    catch {
        $validationFailure = $_.Exception.Message
    }
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/destination-validate' `
        -Condition ($null -eq $validationFailure) `
        -PassObserved "winget validate accepts $($copy.destination.relative) in the clone." `
        -FailObserved "winget validate rejected $($copy.destination.relative): $validationFailure"))
    if (& $blocking) { return & $stop }

    # 7. The final diff, before anything is committed.
    $diff = Test-TigerWinGetPkgsSubmissionDiff -Config $Config -Version $Version `
        -Submission $Submission -Branch $state.branch
    foreach ($check in $diff.checks) { $checks.Add($check) }
    if (& $blocking) { return & $stop }

    # 8. One deterministic commit, or the recognition that it already exists.
    $commit = Save-TigerWinGetPkgsSubmissionCommit -Config $Config -Version $Version -Branch $state.branch
    foreach ($check in $commit.checks) { $checks.Add($check) }
    $state.commitSha = $commit.commitSha
    if (& $blocking) { return & $stop }

    # 9. The push, and proof the fork now carries exactly that commit.
    $push = Push-TigerWinGetPkgsSubmissionBranch -Config $Config -Branch $state.branch -CommitSha $commit.commitSha
    foreach ($check in $push.checks) { $checks.Add($check) }
    $state.remoteSha = $push.remoteSha
    $state.pushed = $push.pushed
    if (& $blocking) { return & $stop }

    $state.compareUrl = ("https://github.com/$($Config.upstreamSlug)/compare/$($Config.defaultBranch)..." +
        "$($Config.forkOwner):$($state.branch)?expand=1")
    $state.pullRequestCommand = ("gh pr create --repo $($Config.upstreamSlug) " +
        "--base $($Config.defaultBranch) --head $($Config.forkOwner):$($state.branch) " +
        "--title `"$($commit.message)`"")

    & $stop
}
