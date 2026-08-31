#Requires -Version 7.0
<#
    .SYNOPSIS
    Covers the guarded winget-pkgs mutation in eng/winget/WinGetPkgsSubmission.ps1.

    .DESCRIPTION
    Everything runs against local bare Git repositories and a fake `gh` invoker. No
    test contacts the real fork, the real upstream, GitHub, WinGet, or TigerWinLab.

    The clone's remotes still carry the canonical github.com URLs, because the
    identity checks are part of what is under test. Fetch and push reach the local
    bare repositories through url.<local>.insteadOf rules in a temporary
    GIT_CONFIG_GLOBAL, so the production code paths run unchanged and the
    developer's own Git configuration is never touched.

    The last section is the point of the file: a complete run, then a second
    complete run over the same state, which must make no new commit and no new push
    and must still end with the pull request as the only remaining action.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$wingetRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $wingetRoot 'WinGetPkgsSubmission.ps1')

function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Git {
    param([string] $Root, [string[]] $GitArgs)
    $previous = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $out = (& git @($(if ($Root) { @('-C', $Root) } else { @() }) + $GitArgs) 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
        $out.Trim()
    }
    finally { $PSNativeCommandUseErrorActionPreference = $previous; $global:LASTEXITCODE = 0 }
}

function Get-CheckStatus {
    param([object[]] $Checks, [string] $Id)
    $match = @($Checks | Where-Object { $_.id -ceq $Id })
    if ($match.Count -eq 0) { return $null }
    $match[0].status
}

# Every fixture reaches its local bare repositories through url.insteadOf, which
# the clone-identity gate correctly reports as a redirect. That one WARN is the
# fixture's own signature, so it is the only non-PASS a healthy run may carry.
function Get-Unexpected {
    param([object[]] $Checks)
    @($Checks | Where-Object { $_.status -cne 'PASS' -and $_.id -cne 'clone/remote-redirect' })
}

function Format-Checks {
    param([object[]] $Checks)
    (@(Get-Unexpected $Checks | ForEach-Object { "$($_.id)=$($_.status): $($_.observed)" }) -join ' | ')
}

# A fake gh whose only route that matters here is the previous-PR search.
function New-PrCli {
    param([hashtable] $Routes)
    New-TigerMarkViewGitHubCli -Invoker {
        param([string[]] $GhArgs)
        $key = if ($GhArgs.Count -ge 4 -and $GhArgs[0] -ceq 'api') { "api $($GhArgs[3])" } else { ($GhArgs -join ' ') }
        foreach ($route in $Routes.Keys) {
            if ($key -like $route) {
                return [pscustomobject]@{ ExitCode = 0; StdOut = ($Routes[$route] | ConvertTo-Json -Depth 12); StdErr = '' }
            }
        }
        [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = "no route for $key" }
    }.GetNewClosure()
}

$noPreviousPr = New-PrCli @{ 'api search/issues*' = [pscustomobject]@{ items = @() } }
$version = '9.9.9'
$packageIdentifier = 'ItTiger.TigerMarkView'
$manifestNames = @(
    "$packageIdentifier.installer.yaml"
    "$packageIdentifier.locale.en-US.yaml"
    "$packageIdentifier.yaml"
)
# The validator is stubbed: WinGet's own opinion of a manifest is covered by
# TigerMarkViewWinGet.Tests.ps1, and no test here may need winget.exe.
$acceptValidation = { param([string] $ManifestDirectory) $ManifestDirectory }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('TigerWinGetPkgsSubmission-' + [Guid]::NewGuid().ToString('N'))
$originalGlobalConfig = $env:GIT_CONFIG_GLOBAL

function New-SealedSubmission {
    <#
        A sealed set in the shape Read-TigerMarkViewWinGetSubmissionSet returns:
        three documents with their paths, lengths, and digests, plus the combined
        submission digest the copy has to reproduce at the destination.
    #>
    param([Parameter(Mandatory)][string] $Directory, [string] $Marker = 'sealed')

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $documents = foreach ($name in $manifestNames) {
        $path = Join-Path $Directory $name
        $body = "# $Marker $name`nPackageIdentifier: $packageIdentifier`nPackageVersion: $version`n"
        [IO.File]::WriteAllText($path, $body, [Text.UTF8Encoding]::new($false))
        [pscustomobject][ordered]@{
            name = $name
            path = $path
            length = [long] (Get-Item -LiteralPath $path).Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
        }
    }
    $documents = @($documents)
    [pscustomobject][ordered]@{
        directory = $Directory
        documents = $documents
        digest = Get-TigerMarkViewWinGetSubmissionDigest -Documents $documents
    }
}

function New-SubmissionFixture {
    <#
        upstream.git + fork.git bare repositories and a clone whose remotes carry
        the canonical github.com URLs. Returns the clone config.
    #>
    $dir = Join-Path $testRoot ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $upstream = Join-Path $dir 'upstream.git'
    $fork = Join-Path $dir 'fork.git'
    $clone = Join-Path $dir 'clone'
    Invoke-Git -Root '' -GitArgs @('init', '--quiet', '--bare', '-b', 'master', $upstream) | Out-Null
    Invoke-Git -Root '' -GitArgs @('init', '--quiet', '--bare', '-b', 'master', $fork) | Out-Null

    $seed = Join-Path $dir 'seed'
    Invoke-Git -Root '' -GitArgs @('clone', '--quiet', $upstream, $seed) | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $seed 'doc') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $seed 'doc/README.md') -Value 'winget-pkgs' -Encoding utf8NoBOM
    Invoke-Git -Root $seed -GitArgs @('add', '-A') | Out-Null
    Invoke-Git -Root $seed -GitArgs @('commit', '--quiet', '-m', 'seed') | Out-Null
    Invoke-Git -Root $seed -GitArgs @('push', '--quiet', 'origin', 'master') | Out-Null
    Invoke-Git -Root $seed -GitArgs @('push', '--quiet', $fork, 'master') | Out-Null

    # The insteadOf rules name these two bare repositories, and every fixture uses
    # the same canonical URLs, so only one fixture's rules can be in effect at a
    # time. GIT_CONFIG_GLOBAL is repointed here: a fixture is usable until the next
    # one is created, which is how the tests below are ordered.
    $globalConfig = Join-Path $dir 'gitconfig'
    $forkUrl = ($fork -replace '\\', '/')
    $upstreamUrl = ($upstream -replace '\\', '/')
    Set-Content -LiteralPath $globalConfig -Encoding utf8NoBOM -Value @(
        '[user]'
        '    name = Tiger Test'
        '    email = test@example.com'
        '[init]'
        '    defaultBranch = master'
        "[url `"$forkUrl`"]"
        '    insteadOf = https://github.com/rkozlowski/winget-pkgs'
        "[url `"$upstreamUrl`"]"
        '    insteadOf = https://github.com/microsoft/winget-pkgs'
    )
    $env:GIT_CONFIG_GLOBAL = $globalConfig

    Invoke-Git -Root '' -GitArgs @('clone', '--quiet', 'https://github.com/rkozlowski/winget-pkgs', $clone) | Out-Null
    Invoke-Git -Root $clone -GitArgs @('remote', 'add', 'upstream', 'https://github.com/microsoft/winget-pkgs') | Out-Null
    Invoke-Git -Root $clone -GitArgs @('fetch', '--quiet', 'upstream') | Out-Null

    $configFile = Join-Path $dir 'winget-pkgs.clone.json'
    Set-Content -LiteralPath $configFile -Encoding utf8NoBOM -Value (@{
        clonePath = $clone
        forkSlug = 'rkozlowski/winget-pkgs'
        upstreamSlug = 'microsoft/winget-pkgs'
        defaultBranch = 'master'
        branchPrefix = 'ItTiger-TigerMarkView-'
        packageIdentifier = $packageIdentifier
        manifestPath = 'manifests/i/ItTiger/TigerMarkView'
    } | ConvertTo-Json)

    $config = Get-TigerWinGetPkgsCloneConfig -ConfigPath $configFile -ClonePath $clone
    Add-Member -InputObject $config -NotePropertyName upstreamRepositoryPath -NotePropertyValue $upstream
    Add-Member -InputObject $config -NotePropertyName forkRepositoryPath -NotePropertyValue $fork
    Add-Member -InputObject $config -NotePropertyName seedPath -NotePropertyValue $seed
    $config
}

function Add-UpstreamCommit {
    param([Parameter(Mandatory)][object] $Config, [string] $Text = 'moved on')
    Invoke-Git -Root $Config.seedPath -GitArgs @('pull', '--quiet', '--ff-only', 'origin', 'master') | Out-Null
    Add-Content -LiteralPath (Join-Path $Config.seedPath 'doc/README.md') -Value $Text -Encoding utf8NoBOM
    Invoke-Git -Root $Config.seedPath -GitArgs @('commit', '--quiet', '-am', $Text) | Out-Null
    Invoke-Git -Root $Config.seedPath -GitArgs @('push', '--quiet', 'origin', 'master') | Out-Null
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $sealed = New-SealedSubmission -Directory (Join-Path $testRoot 'sealed')

    # --- Names and destinations are derived, never typed twice ---------------

    $names = New-SubmissionFixture
    Assert-True ((Get-TigerWinGetPkgsSubmissionBranchName -Config $names -Version $version) -ceq
        "ItTiger-TigerMarkView-$version") 'The branch name is the configured prefix plus the version.'
    $destination = Get-TigerWinGetPkgsSubmissionDestination -Config $names -Version $version
    Assert-True ($destination.relative -ceq "manifests/i/ItTiger/TigerMarkView/$version") `
        'The submission path is the configured manifest path plus the version.'
    Write-Host 'PASS: the branch name and submission path are derived from configuration'

    # --- An absent clone is created; an existing directory is never adopted ---

    $creating = New-SubmissionFixture
    $absentPath = Join-Path (Split-Path -Parent $creating.clonePath) 'created-clone'
    $absentConfig = Get-TigerWinGetPkgsCloneConfig -ConfigPath $creating.configPath -ClonePath $absentPath
    $createChecks = @(New-TigerWinGetPkgsClone -Config $absentConfig)
    Assert-True ((Get-CheckStatus $createChecks 'clone/create') -ceq 'PASS') `
        "An absent clone is created: $(Format-Checks $createChecks)"
    Assert-True ((Invoke-Git -Root $absentPath -GitArgs @('config', '--get', 'remote.upstream.url')) -ceq
        'https://github.com/microsoft/winget-pkgs') 'The created clone declares the upstream remote.'
    $identityChecks = @(Test-TigerWinGetPkgsCloneIdentity -Config $absentConfig)
    Assert-True (@(Get-Unexpected $identityChecks).Count -eq 0) `
        "A freshly created clone passes every identity check: $(Format-Checks $identityChecks)"
    Assert-True ((Get-CheckStatus $identityChecks 'clone/remote-redirect') -ceq 'WARN') `
        'A url.insteadOf redirect is reported rather than hidden.'

    $occupied = Join-Path (Split-Path -Parent $creating.clonePath) 'occupied'
    New-Item -ItemType Directory -Path $occupied -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $occupied 'something.txt') -Value 'mine' -Encoding utf8NoBOM
    $occupiedConfig = Get-TigerWinGetPkgsCloneConfig -ConfigPath $creating.configPath -ClonePath $occupied
    $occupiedChecks = @(New-TigerWinGetPkgsClone -Config $occupiedConfig)
    Assert-True ((Get-CheckStatus $occupiedChecks 'clone/create') -ceq 'FAIL') `
        'An existing directory is never adopted or emptied.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $occupied 'something.txt') -Raw).Trim() -ceq 'mine') `
        'The existing directory is left exactly as it was.'
    Write-Host 'PASS: an absent clone is created and an occupied path is refused'

    # --- Fork synchronization is fast-forward only --------------------------

    $sync = New-SubmissionFixture
    $already = Sync-TigerWinGetPkgsFork -Config $sync
    Assert-True (@(Get-Unexpected $already.checks).Count -eq 0) `
        "An already-synchronized fork passes: $(Format-Checks $already.checks)"
    Assert-True (-not $already.state.fastForwarded -and -not $already.state.pushed) `
        'An already-synchronized fork is verified without a fast-forward or a push.'

    Add-UpstreamCommit -Config $sync
    $advanced = Sync-TigerWinGetPkgsFork -Config $sync
    Assert-True (@(Get-Unexpected $advanced.checks).Count -eq 0) `
        "A behind fork fast-forwards: $(Format-Checks $advanced.checks)"
    Assert-True ($advanced.state.fastForwarded -and $advanced.state.pushed) `
        'A behind fork is fast-forwarded and pushed.'
    $upstreamHead = Invoke-Git -Root $sync.upstreamRepositoryPath -GitArgs @('rev-parse', 'master')
    $forkHead = Invoke-Git -Root $sync.forkRepositoryPath -GitArgs @('rev-parse', 'master')
    Assert-True ($forkHead -ceq $upstreamHead) 'The fork really is at upstream after synchronization.'

    $divergent = New-SubmissionFixture
    Set-Content -LiteralPath (Join-Path $divergent.clonePath 'doc/README.md') -Value 'fork only' -Encoding utf8NoBOM
    Invoke-Git -Root $divergent.clonePath -GitArgs @('commit', '--quiet', '-am', 'fork-only work') | Out-Null
    $divergentSha = Invoke-Git -Root $divergent.clonePath -GitArgs @('rev-parse', 'master')
    $divergentSync = Sync-TigerWinGetPkgsFork -Config $divergent
    Assert-True ((Get-CheckStatus $divergentSync.checks 'sync/no-fork-only-commits') -ceq 'FAIL') `
        'A fork carrying its own commits stops synchronization.'
    Assert-True ((Invoke-Git -Root $divergent.clonePath -GitArgs @('rev-parse', 'master')) -ceq $divergentSha) `
        'The fork-only commit is never discarded.'
    Write-Host 'PASS: fork synchronization fast-forwards, verifies, and refuses to rewrite'

    # --- Branch creation, resume, and refusal -------------------------------

    $branching = New-SubmissionFixture
    $null = Sync-TigerWinGetPkgsFork -Config $branching
    $created = Set-TigerWinGetPkgsSubmissionBranch -Config $branching -Version $version
    Assert-True ($created.created -and (Get-CheckStatus $created.checks 'branch/create') -ceq 'PASS') `
        "An absent branch is created from upstream: $(Format-Checks $created.checks)"
    $resumed = Set-TigerWinGetPkgsSubmissionBranch -Config $branching -Version $version
    Assert-True ((Get-CheckStatus $resumed.checks 'branch/resume') -ceq 'PASS') `
        "An existing branch on current upstream is reused: $(Format-Checks $resumed.checks)"

    # A branch based on something else is a conflict, and is left untouched.
    $stale = New-SubmissionFixture
    $null = Sync-TigerWinGetPkgsFork -Config $stale
    Invoke-Git -Root $stale.clonePath -GitArgs @('checkout', '--quiet', '-b', "ItTiger-TigerMarkView-$version") | Out-Null
    Set-Content -LiteralPath (Join-Path $stale.clonePath 'doc/README.md') -Value 'unrelated' -Encoding utf8NoBOM
    Invoke-Git -Root $stale.clonePath -GitArgs @('commit', '--quiet', '-am', 'unrelated work') | Out-Null
    Invoke-Git -Root $stale.clonePath -GitArgs @('checkout', '--quiet', 'master') | Out-Null
    Add-UpstreamCommit -Config $stale -Text 'upstream moved'
    $null = Sync-TigerWinGetPkgsFork -Config $stale
    $staleBranchSha = Invoke-Git -Root $stale.clonePath -GitArgs @('rev-parse', "ItTiger-TigerMarkView-$version")
    $conflicting = Set-TigerWinGetPkgsSubmissionBranch -Config $stale -Version $version
    Assert-True ((Get-CheckStatus $conflicting.checks 'branch/resume') -ceq 'FAIL') `
        'A branch that is not based on current upstream is a conflict.'
    Assert-True ((Invoke-Git -Root $stale.clonePath -GitArgs @('rev-parse', "ItTiger-TigerMarkView-$version")) -ceq
        $staleBranchSha) 'A conflicting branch is never deleted or reset.'
    Write-Host 'PASS: the submission branch is created, resumed, or refused - never rewritten'

    # --- The copy is exact, and the diff is path-limited --------------------

    $copying = New-SubmissionFixture
    $null = Sync-TigerWinGetPkgsFork -Config $copying
    $copyBranch = Set-TigerWinGetPkgsSubmissionBranch -Config $copying -Version $version
    $copy = Copy-TigerWinGetPkgsSubmission -Config $copying -Version $version -Submission $sealed
    Assert-True (@(Get-Unexpected $copy.checks).Count -eq 0) `
        "The sealed set copies cleanly: $(Format-Checks $copy.checks)"
    Assert-True ($copy.placed.digest -ceq $sealed.digest) 'The destination reproduces the sealed digest.'
    foreach ($document in $sealed.documents) {
        $placedBytes = [IO.File]::ReadAllBytes((Join-Path $copy.destination.full $document.name))
        $sealedBytes = [IO.File]::ReadAllBytes($document.path)
        Assert-True ([Linq.Enumerable]::SequenceEqual($placedBytes, $sealedBytes)) `
            "$($document.name) is not byte-identical at the destination."
    }

    $diff = Test-TigerWinGetPkgsSubmissionDiff -Config $copying -Version $version -Submission $sealed `
        -Branch $copyBranch.branch
    Assert-True (@(Get-Unexpected $diff.checks).Count -eq 0) `
        "A clean submission diff passes: $(Format-Checks $diff.checks)"

    # An unrelated edit anywhere else in the clone stops the run before the commit.
    Set-Content -LiteralPath (Join-Path $copying.clonePath 'doc/README.md') -Value 'stray edit' -Encoding utf8NoBOM
    $strayDiff = Test-TigerWinGetPkgsSubmissionDiff -Config $copying -Version $version -Submission $sealed `
        -Branch $copyBranch.branch
    Assert-True ((Get-CheckStatus $strayDiff.checks 'submission/worktree-diff') -ceq 'FAIL') `
        'An unrelated change in the clone fails the worktree diff.'
    Invoke-Git -Root $copying.clonePath -GitArgs @('checkout', '--', 'doc/README.md') | Out-Null

    # A stray file inside the version directory is not a submission set.
    $strayManifest = Join-Path $copy.destination.full 'stray.yaml'
    Set-Content -LiteralPath $strayManifest -Value 'stray' -Encoding utf8NoBOM
    $strayCopy = Copy-TigerWinGetPkgsSubmission -Config $copying -Version $version -Submission $sealed
    Assert-True ((Get-CheckStatus $strayCopy.checks 'submission/destination-shape') -ceq 'FAIL') `
        'A stray file under the version directory fails the destination shape check.'
    Remove-Item -LiteralPath $strayManifest -Force
    Write-Host 'PASS: the copy is byte-exact and the diff admits only the version directory'

    # --- The commit is deterministic and the push is verified ---------------

    $commit = Save-TigerWinGetPkgsSubmissionCommit -Config $copying -Version $version -Branch $copyBranch.branch
    Assert-True (@(Get-Unexpected $commit.checks).Count -eq 0) `
        "The submission commits cleanly: $(Format-Checks $commit.checks)"
    Assert-True ($commit.committed -and $commit.message -ceq "New version: $packageIdentifier version $version") `
        'The commit subject is the deterministic winget-pkgs subject.'
    $recommit = Save-TigerWinGetPkgsSubmissionCommit -Config $copying -Version $version -Branch $copyBranch.branch
    Assert-True (-not $recommit.committed -and $recommit.commitSha -ceq $commit.commitSha) `
        'A rerun over an already-committed submission commits nothing new.'

    $push = Push-TigerWinGetPkgsSubmissionBranch -Config $copying -Branch $copyBranch.branch `
        -CommitSha $commit.commitSha
    Assert-True ($push.pushed -and $push.remoteSha -ceq $commit.commitSha) `
        "The branch is pushed and verified: $(Format-Checks $push.checks)"
    $repush = Push-TigerWinGetPkgsSubmissionBranch -Config $copying -Branch $copyBranch.branch `
        -CommitSha $commit.commitSha
    Assert-True (-not $repush.pushed -and (Get-CheckStatus $repush.checks 'submission/push') -ceq 'PASS') `
        'An already-pushed branch is recognised rather than pushed again.'

    # A remote branch pointing somewhere else is never force-pushed over.
    $hijacked = Push-TigerWinGetPkgsSubmissionBranch -Config $copying -Branch $copyBranch.branch `
        -CommitSha ('f' * 40)
    Assert-True ((Get-CheckStatus $hijacked.checks 'submission/push') -ceq 'FAIL') `
        'A remote branch at a different commit is a stop, not a force push.'
    Assert-True ((Invoke-Git -Root $copying.forkRepositoryPath `
        -GitArgs @('rev-parse', $copyBranch.branch)) -ceq $commit.commitSha) `
        'The remote branch is left exactly where it was.'
    Write-Host 'PASS: the commit is deterministic, the push is verified, and neither is repeated'

    # --- The previous-PR gate stops before anything is written --------------

    $gated = New-SubmissionFixture
    $blockingCli = New-PrCli @{
        'api search/issues*' = [pscustomobject]@{ items = @([pscustomobject]@{ number = 55; pull_request = [pscustomobject]@{} }) }
        'api repos/microsoft/winget-pkgs/pulls/55' = [pscustomobject]@{
            number = 55
            html_url = 'https://github.com/microsoft/winget-pkgs/pull/55'
            state = 'open'
            draft = $false
            merged_at = ''
            head = [pscustomobject]@{
                ref = 'ItTiger-TigerMarkView-0.0.1'
                repo = [pscustomobject]@{ owner = [pscustomobject]@{ login = 'rkozlowski' } }
            }
        }
    }
    $gatedRun = Invoke-TigerWinGetPkgsSubmission -Cli $blockingCli -Config $gated -Version $version `
        -Submission $sealed -ValidateCommand $acceptValidation
    Assert-True ((Get-CheckStatus $gatedRun.checks 'winget-pkgs/previous-pr') -ceq 'BLOCKED') `
        'An open previous PR blocks the submission.'
    Assert-True ($null -eq (Get-CheckStatus $gatedRun.checks 'branch/create')) `
        'No branch is created once the previous-PR gate blocks.'
    Assert-True (-not (Test-Path -LiteralPath (Get-TigerWinGetPkgsSubmissionDestination `
        -Config $gated -Version $version).full)) 'No manifest is copied once the previous-PR gate blocks.'
    Write-Host 'PASS: the previous-PR gate stops the run before any write'

    # --- -PlanOnly diagnoses and prepares nothing ---------------------------

    $planning = New-SubmissionFixture
    $plan = Invoke-TigerWinGetPkgsSubmission -Cli $noPreviousPr -Config $planning -Version $version `
        -Submission $sealed -ValidateCommand $acceptValidation -PlanOnly
    Assert-True ((Get-CheckStatus $plan.checks 'submission/plan-only') -ceq 'BLOCKED') `
        '-PlanOnly can never report a submission PASS.'
    $planReport = New-TigerMarkViewReleaseReport -Title 'plan' -Checks $plan.checks `
        -Handoff @('this must not survive a BLOCKED check')
    Assert-True ($planReport.status -ceq 'BLOCKED') '-PlanOnly never reaches READY FOR HUMAN ACTION.'
    Assert-True ((Invoke-Git -Root $planning.clonePath -GitArgs @('branch', '--list')) -notmatch 'ItTiger') `
        '-PlanOnly creates no branch.'
    Write-Host 'PASS: -PlanOnly diagnoses without synchronizing, branching, copying, or pushing'

    # --- A complete run, then an identical second run -----------------------

    $end = New-SubmissionFixture
    Add-UpstreamCommit -Config $end -Text 'upstream advanced before the release'
    $first = Invoke-TigerWinGetPkgsSubmission -Cli $noPreviousPr -Config $end -Version $version `
        -Submission $sealed -ValidateCommand $acceptValidation
    Assert-True (@(Get-Unexpected $first.checks).Count -eq 0) `
        "A complete run passes every check: $(Format-Checks $first.checks)"
    Assert-True ($first.state.pushed) 'The first run pushes the submission branch.'
    Assert-True ($first.state.remoteSha -ceq $first.state.commitSha) 'The pushed branch is verified.'
    Assert-True ($first.state.compareUrl -match 'microsoft/winget-pkgs/compare' -and
        $first.state.pullRequestCommand -match 'gh pr create') `
        'The run hands off a compare URL and a pull-request command.'

    $forkBranchSha = Invoke-Git -Root $end.forkRepositoryPath -GitArgs @('rev-parse', $first.state.branch)
    Assert-True ($forkBranchSha -ceq $first.state.commitSha) 'The fork carries exactly the submission commit.'
    $changed = @((Invoke-Git -Root $end.clonePath `
        -GitArgs @('diff', '--name-only', "upstream/master..$($first.state.branch)")) -split "\r?\n" |
        Where-Object { $_ })
    Assert-True ($changed.Count -eq 3) 'The branch changes exactly the three manifests.'
    foreach ($name in $manifestNames) {
        Assert-True ($changed -contains "manifests/i/ItTiger/TigerMarkView/$version/$name") `
            "$name is missing from the submission diff."
    }

    # The rerun is the acceptance criterion: same state, no new commit, no new push,
    # same handoff.
    $second = Invoke-TigerWinGetPkgsSubmission -Cli $noPreviousPr -Config $end -Version $version `
        -Submission $sealed -ValidateCommand $acceptValidation
    Assert-True (@(Get-Unexpected $second.checks).Count -eq 0) `
        "A second complete run passes every check: $(Format-Checks $second.checks)"
    Assert-True ($second.state.commitSha -ceq $first.state.commitSha) 'The rerun makes no new commit.'
    Assert-True (-not $second.state.pushed) 'The rerun pushes nothing.'
    Assert-True ($second.state.remoteSha -ceq $first.state.commitSha) 'The rerun re-verifies the pushed branch.'
    $commitCount = Invoke-Git -Root $end.clonePath `
        -GitArgs @('rev-list', '--count', "upstream/master..$($second.state.branch)")
    Assert-True ($commitCount -ceq '1') 'The branch still carries exactly one submission commit.'
    Write-Host 'PASS: a complete run pushes the submission and a rerun changes nothing'

    # --- Interruption boundaries all resume ---------------------------------

    # Each of these leaves the clone as an interruption would and reruns the whole
    # command; every one must reach the same pushed branch without a second commit.
    $boundaries = [ordered]@{
        'after the branch was created' = {
            param($Config)
            $null = Sync-TigerWinGetPkgsFork -Config $Config
            $null = Set-TigerWinGetPkgsSubmissionBranch -Config $Config -Version $version
        }
        'after the files were copied but not committed' = {
            param($Config)
            $null = Sync-TigerWinGetPkgsFork -Config $Config
            $null = Set-TigerWinGetPkgsSubmissionBranch -Config $Config -Version $version
            $null = Copy-TigerWinGetPkgsSubmission -Config $Config -Version $version -Submission $sealed
        }
        'after the commit but before the push' = {
            param($Config)
            $null = Sync-TigerWinGetPkgsFork -Config $Config
            $branch = Set-TigerWinGetPkgsSubmissionBranch -Config $Config -Version $version
            $null = Copy-TigerWinGetPkgsSubmission -Config $Config -Version $version -Submission $sealed
            $null = Save-TigerWinGetPkgsSubmissionCommit -Config $Config -Version $version -Branch $branch.branch
        }
    }
    foreach ($boundary in $boundaries.Keys) {
        $fixture = New-SubmissionFixture
        & $boundaries[$boundary] $fixture
        $resumedRun = Invoke-TigerWinGetPkgsSubmission -Cli $noPreviousPr -Config $fixture -Version $version `
            -Submission $sealed -ValidateCommand $acceptValidation
        Assert-True (@(Get-Unexpected $resumedRun.checks).Count -eq 0) `
            "A run interrupted $boundary must resume cleanly: $(Format-Checks $resumedRun.checks)"
        Assert-True ($resumedRun.state.remoteSha -ceq $resumedRun.state.commitSha) `
            "A run interrupted $boundary must end with the branch pushed and verified."
        $count = Invoke-Git -Root $fixture.clonePath `
            -GitArgs @('rev-list', '--count', "upstream/master..$($resumedRun.state.branch)")
        Assert-True ($count -ceq '1') "A run interrupted $boundary must not produce a second commit."
    }
    Write-Host 'PASS: every interruption boundary resumes to one commit and one pushed branch'

    # --- An interrupted git operation stops before anything is written ------

    $interrupted = New-SubmissionFixture
    New-Item -ItemType File -Path (Join-Path $interrupted.clonePath '.git/MERGE_HEAD') -Force | Out-Null
    $interruptedRun = Invoke-TigerWinGetPkgsSubmission -Cli $noPreviousPr -Config $interrupted -Version $version `
        -Submission $sealed -ValidateCommand $acceptValidation
    Assert-True ((Get-CheckStatus $interruptedRun.checks 'clone/no-interrupted-op') -ceq 'FAIL') `
        'An interrupted merge stops the submission.'
    Assert-True ($null -eq (Get-CheckStatus $interruptedRun.checks 'sync/fetch-upstream')) `
        'Nothing is fetched while an interrupted operation is active.'
    Write-Host 'PASS: an interrupted Git operation stops the run before any fetch or write'

    # --- No destructive or PR-creating operation exists in the source ------

    # A test can only prove that the paths it exercises are safe. These assertions
    # cover the ones it cannot reach: the operations that must not exist at all.
    $mutationSource = Get-Content -LiteralPath (Join-Path $wingetRoot 'WinGetPkgsSubmission.ps1') -Raw
    $commandSource = Get-Content -LiteralPath (Join-Path $wingetRoot 'Prepare-TigerMarkViewWinGetSubmission.ps1') -Raw
    foreach ($source in @($mutationSource, $commandSource)) {
        foreach ($forbidden in @("'--force'", "'-f'", "'reset'", "'--hard'", "'-D'", "'clean'")) {
            Assert-True (-not $source.Contains("GitArgs @($forbidden")) `
                "No git argument list may begin with $forbidden."
            Assert-True (-not $source.Contains(", $forbidden")) `
                "No git argument list may contain $forbidden."
        }
        Assert-True ($source -notmatch "@\('pr',\s*'create'") `
            'Nothing here may open the pull request; that decision stays with the human.'
        Assert-True ($source -notmatch 'GH_TOKEN|GITHUB_TOKEN|auth token|-GitHubToken') `
            'The submission path must not read, forward, or log a token.'
    }
    Assert-True ($mutationSource.Contains('gh pr create')) `
        'The handoff must give the maintainer the exact pull-request command.'
    foreach ($source in @($mutationSource, $commandSource)) {
        Assert-True ($source -notmatch '(?m)^\s*&?\s*gh\s+pr\s+create') `
            'That command must be printed, never executed.'
    }
    Write-Host 'PASS: no force, reset, delete, or pull-request-creating operation exists in the source'

    Write-Host
    Write-Host 'PASS: winget-pkgs submission mutation' -ForegroundColor Green
}
catch {
    Write-Host
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
finally {
    if ($null -eq $originalGlobalConfig) { Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue }
    else { $env:GIT_CONFIG_GLOBAL = $originalGlobalConfig }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
