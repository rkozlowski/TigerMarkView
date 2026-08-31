#Requires -Version 7.0
<#
    .SYNOPSIS
    Covers the read-only winget-pkgs clone safety checks in
    eng/winget/WinGetPkgsClone.ps1.

    .DESCRIPTION
    Uses local bare Git repositories and a fake `gh` invoker. No test touches the
    real fork, upstream, or GitHub.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$wingetRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $wingetRoot 'WinGetPkgsClone.ps1')

function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([Parameter(Mandatory)] [scriptblock] $Action, [Parameter(Mandatory)] [string] $MessagePattern)
    try { & $Action }
    catch {
        Assert-True ($_.Exception.Message -match $MessagePattern) `
            "Expected failure matching '$MessagePattern'; received '$($_.Exception.Message)'."
        return
    }
    throw "Expected an exception matching '$MessagePattern'."
}

function Invoke-Git {
    param([string] $Root, [string[]] $GitArgs)
    $previous = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $out = (& git @($(if ($Root) { @('-C', $Root) } else { @() }) + $GitArgs) 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
        $out
    }
    finally { $PSNativeCommandUseErrorActionPreference = $previous; $global:LASTEXITCODE = 0 }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('TigerWinGetPkgsClone-' + [Guid]::NewGuid().ToString('N'))

function New-CloneFixture {
    <#
        Creates upstream.git + fork.git bare repos and a working clone whose
        remotes are set to the canonical github.com URLs (read-only tests never
        contact them). Returns a config object bound to that clone.
    #>
    $dir = Join-Path $testRoot ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $upstream = Join-Path $dir 'upstream.git'
    $fork = Join-Path $dir 'fork.git'
    $clone = Join-Path $dir 'clone'
    Invoke-Git -Root '' -GitArgs @('init', '--quiet', '--bare', '-b', 'master', $upstream) | Out-Null
    Invoke-Git -Root '' -GitArgs @('init', '--quiet', '--bare', '-b', 'master', $fork) | Out-Null

    $seed = Join-Path $dir 'seed'
    Invoke-Git -Root '' -GitArgs @('clone', '--quiet', $fork, $seed) | Out-Null
    Invoke-Git -Root $seed -GitArgs @('config', 'user.email', 'test@example.com') | Out-Null
    Invoke-Git -Root $seed -GitArgs @('config', 'user.name', 'Test') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $seed 'doc') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $seed 'doc/README.md') -Value 'winget-pkgs' -Encoding utf8NoBOM
    Invoke-Git -Root $seed -GitArgs @('add', '-A') | Out-Null
    Invoke-Git -Root $seed -GitArgs @('commit', '--quiet', '-m', 'seed') | Out-Null
    Invoke-Git -Root $seed -GitArgs @('push', '--quiet', 'origin', 'master') | Out-Null
    Invoke-Git -Root $seed -GitArgs @('push', '--quiet', $upstream, 'master') | Out-Null

    Invoke-Git -Root '' -GitArgs @('clone', '--quiet', $fork, $clone) | Out-Null
    Invoke-Git -Root $clone -GitArgs @('config', 'user.email', 'test@example.com') | Out-Null
    Invoke-Git -Root $clone -GitArgs @('config', 'user.name', 'Test') | Out-Null
    Invoke-Git -Root $clone -GitArgs @('remote', 'add', 'upstream', $upstream) | Out-Null
    Invoke-Git -Root $clone -GitArgs @('remote', 'set-url', 'origin', 'https://github.com/rkozlowski/winget-pkgs.git') | Out-Null
    Invoke-Git -Root $clone -GitArgs @('remote', 'set-url', 'upstream', 'https://github.com/microsoft/winget-pkgs') | Out-Null

    $configFile = Join-Path $dir 'winget-pkgs.clone.json'
    Set-Content -LiteralPath $configFile -Encoding utf8NoBOM -Value (@{
        clonePath = $clone
        forkSlug = 'rkozlowski/winget-pkgs'
        upstreamSlug = 'microsoft/winget-pkgs'
        defaultBranch = 'master'
        branchPrefix = 'ItTiger-TigerMarkView-'
        packageIdentifier = 'ItTiger.TigerMarkView'
        manifestPath = 'manifests/i/ItTiger/TigerMarkView'
    } | ConvertTo-Json)

    Get-TigerWinGetPkgsCloneConfig -ConfigPath $configFile -ClonePath $clone
}

function Get-CheckStatus {
    param([object[]] $Checks, [string] $Id)
    $match = @($Checks | Where-Object { $_.id -ceq $Id })
    if ($match.Count -eq 0) { return $null }
    $match[0].status
}

function New-PrCli {
    param([hashtable] $Routes)
    New-TigerMarkViewGitHubCli -Invoker {
        param([string[]] $GhArgs)
        $key = if ($GhArgs.Count -ge 4 -and $GhArgs[0] -ceq 'api') { "api $($GhArgs[3])" } else { ($GhArgs -join ' ') }
        foreach ($route in $Routes.Keys) {
            if ($key -like $route) {
                $value = $Routes[$route]
                return [pscustomobject]@{ ExitCode = 0; StdOut = ($value | ConvertTo-Json -Depth 12); StdErr = '' }
            }
        }
        [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = "no route for $key" }
    }.GetNewClosure()
}

function New-Pr {
    param(
        [int] $Number,
        [string] $State = 'closed',
        [bool] $Draft = $false,
        [string] $MergedAt = '2026-08-01T00:00:00Z',
        [string] $HeadRef = 'ItTiger-TigerMarkView-1.0.0',
        [string] $HeadOwner = 'rkozlowski'
    )
    [pscustomobject]@{
        number = $Number
        html_url = "https://github.com/microsoft/winget-pkgs/pull/$Number"
        state = $State
        draft = $Draft
        merged_at = $MergedAt
        head = [pscustomobject]@{ ref = $HeadRef; repo = [pscustomobject]@{ owner = [pscustomobject]@{ login = $HeadOwner } } }
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    # --- Config loading and validation ----------------------------------

    $config = New-CloneFixture
    Assert-True ($config.forkOwner -ceq 'rkozlowski') 'The fork owner is derived from the slug.'
    Assert-True ([IO.Path]::IsPathRooted($config.clonePath)) 'The clone path is absolute.'

    $badDir = Join-Path $testRoot 'bad-config'
    New-Item -ItemType Directory -Path $badDir -Force | Out-Null
    $badFile = Join-Path $badDir 'c.json'
    Set-Content -LiteralPath $badFile -Value (@{ forkSlug = 'rkozlowski/winget-pkgs' } | ConvertTo-Json) -Encoding utf8NoBOM
    Assert-Throws -MessagePattern "is missing 'upstreamSlug'" -Action {
        Get-TigerWinGetPkgsCloneConfig -ConfigPath $badFile -ClonePath 'C:\x'
    }
    Set-Content -LiteralPath $badFile -Encoding utf8NoBOM -Value (@{
        forkSlug = 'not-a-slug'; upstreamSlug = 'microsoft/winget-pkgs'; defaultBranch = 'master'
        branchPrefix = 'x-'; packageIdentifier = 'ItTiger.TigerMarkView'; manifestPath = 'm'
    } | ConvertTo-Json)
    Assert-Throws -MessagePattern "forkSlug' must be 'owner/name'" -Action {
        Get-TigerWinGetPkgsCloneConfig -ConfigPath $badFile -ClonePath 'C:\x'
    }
    Set-Content -LiteralPath $badFile -Encoding utf8NoBOM -Value (@{
        forkSlug = 'a/b'; upstreamSlug = 'c/d'; defaultBranch = 'master'
        branchPrefix = 'x-'; packageIdentifier = 'p'; manifestPath = 'm'
    } | ConvertTo-Json)
    Assert-Throws -MessagePattern 'must be absolute' -Action {
        Get-TigerWinGetPkgsCloneConfig -ConfigPath $badFile -ClonePath 'relative\path'
    }
    Write-Host 'PASS: clone configuration is loaded and validated'

    # --- GitHub slug normalization ------------------------------------

    Assert-True (Test-TigerGitHubSlugMatch -Url 'https://github.com/microsoft/winget-pkgs' -ExpectedSlug 'microsoft/winget-pkgs') 'https form matches.'
    Assert-True (Test-TigerGitHubSlugMatch -Url 'https://github.com/Microsoft/winget-pkgs.git' -ExpectedSlug 'microsoft/winget-pkgs') 'case and .git are ignored.'
    Assert-True (Test-TigerGitHubSlugMatch -Url 'git@github.com:microsoft/winget-pkgs.git' -ExpectedSlug 'microsoft/winget-pkgs') 'scp-style ssh matches.'
    Assert-True (Test-TigerGitHubSlugMatch -Url 'ssh://git@github.com/microsoft/winget-pkgs' -ExpectedSlug 'microsoft/winget-pkgs') 'ssh:// URL matches.'
    Assert-True (-not (Test-TigerGitHubSlugMatch -Url 'https://gitlab.com/microsoft/winget-pkgs' -ExpectedSlug 'microsoft/winget-pkgs')) 'a non-github host does not match.'
    Assert-True ($null -eq (Get-TigerGitHubSlug -Url 'file:///tmp/fork.git')) 'an unrecognized URL yields no slug.'
    Write-Host 'PASS: only canonical github.com URL forms are accepted'

    # --- Interrupted operations -------------------------------------

    $config = New-CloneFixture
    Assert-True (@(Get-TigerWinGetPkgsInterruptedOperation -ClonePath $config.clonePath).Count -eq 0) `
        'A fresh clone has no interrupted operation.'
    New-Item -ItemType File -Path (Join-Path $config.clonePath '.git/MERGE_HEAD') -Force | Out-Null
    Assert-True (@(Get-TigerWinGetPkgsInterruptedOperation -ClonePath $config.clonePath) -contains 'merge') `
        'MERGE_HEAD is detected as an interrupted merge.'
    New-Item -ItemType Directory -Path (Join-Path $config.clonePath '.git/rebase-merge') -Force | Out-Null
    Assert-True (@(Get-TigerWinGetPkgsInterruptedOperation -ClonePath $config.clonePath) -contains 'rebase') `
        'rebase-merge/ is detected as an interrupted rebase.'
    Write-Host 'PASS: interrupted Git operations are detected'

    # --- Clone identity matrix ------------------------------------

    $absent = Get-TigerWinGetPkgsCloneConfig -ConfigPath $config.configPath -ClonePath (Join-Path $testRoot 'no-such-clone')
    $absentChecks = Test-TigerWinGetPkgsCloneIdentity -Config $absent
    Assert-True ((Get-CheckStatus $absentChecks 'clone/exists') -ceq 'BLOCKED') 'An absent clone is BLOCKED, not FAIL.'
    Assert-True (@($absentChecks | Where-Object { $_.id -ceq 'clone/exists' })[0].evidence -match 'git clone') `
        'The absent-clone check carries the creation plan.'

    $notRepo = Join-Path $testRoot 'plain-dir'
    New-Item -ItemType Directory -Path $notRepo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $notRepo 'file.txt') -Value 'x' -Encoding utf8NoBOM
    $notRepoConfig = Get-TigerWinGetPkgsCloneConfig -ConfigPath $config.configPath -ClonePath $notRepo
    Assert-True ((Get-CheckStatus (Test-TigerWinGetPkgsCloneIdentity -Config $notRepoConfig) 'clone/worktree') -ceq 'FAIL') `
        'A non-repository directory is FAIL.'

    $good = New-CloneFixture
    $goodChecks = Test-TigerWinGetPkgsCloneIdentity -Config $good
    Assert-True (@($goodChecks | Where-Object { $_.status -cne 'PASS' }).Count -eq 0) `
        ("A clean, correctly-remoted clone passes every identity check; failing: " +
        (@($goodChecks | Where-Object { $_.status -cne 'PASS' } | ForEach-Object { "$($_.id)=$($_.status)" }) -join ', '))

    $wrongOrigin = New-CloneFixture
    Invoke-Git -Root $wrongOrigin.clonePath -GitArgs @('remote', 'set-url', 'origin', 'https://github.com/someoneelse/winget-pkgs.git') | Out-Null
    Assert-True ((Get-CheckStatus (Test-TigerWinGetPkgsCloneIdentity -Config $wrongOrigin) 'clone/origin') -ceq 'FAIL') `
        'A fork remote pointing elsewhere is FAIL.'

    $noUpstream = New-CloneFixture
    Invoke-Git -Root $noUpstream.clonePath -GitArgs @('remote', 'remove', 'upstream') | Out-Null
    Assert-True ((Get-CheckStatus (Test-TigerWinGetPkgsCloneIdentity -Config $noUpstream) 'clone/upstream') -ceq 'FAIL') `
        'A missing upstream remote is FAIL.'

    $dirty = New-CloneFixture
    Set-Content -LiteralPath (Join-Path $dirty.clonePath 'doc/README.md') -Value 'tampered' -Encoding utf8NoBOM
    Assert-True ((Get-CheckStatus (Test-TigerWinGetPkgsCloneIdentity -Config $dirty) 'clone/clean') -ceq 'FAIL') `
        'A dirty worktree is FAIL.'

    $untracked = New-CloneFixture
    $manifestDir = Join-Path $untracked.clonePath 'manifests/i/ItTiger/TigerMarkView/9.9.9'
    New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $manifestDir 'ItTiger.TigerMarkView.yaml') -Value 'stray' -Encoding utf8NoBOM
    Assert-True ((Get-CheckStatus (Test-TigerWinGetPkgsCloneIdentity -Config $untracked) 'clone/no-untracked-manifests') -ceq 'FAIL') `
        'A stray untracked manifest that would be overwritten is FAIL.'

    $interrupted = New-CloneFixture
    New-Item -ItemType File -Path (Join-Path $interrupted.clonePath '.git/CHERRY_PICK_HEAD') -Force | Out-Null
    Assert-True ((Get-CheckStatus (Test-TigerWinGetPkgsCloneIdentity -Config $interrupted) 'clone/no-interrupted-op') -ceq 'FAIL') `
        'An interrupted cherry-pick is FAIL.'
    Write-Host 'PASS: clone identity separates absent, wrong, dirty, and interrupted clones'

    # --- Previous-PR gate -------------------------------------

    $cfg = $good

    $none = Get-TigerWinGetPkgsPreviousPr -Cli (New-PrCli @{ 'api search/issues*' = [pscustomobject]@{ items = @() } }) -Config $cfg
    Assert-True ($none.check.status -ceq 'PASS' -and $null -eq $none.pullRequest) 'No prior PR passes.'

    $mergedRoutes = @{
        'api search/issues*' = [pscustomobject]@{ items = @([pscustomobject]@{ number = 100; pull_request = [pscustomobject]@{} }) }
        'api repos/microsoft/winget-pkgs/pulls/100' = (New-Pr -Number 100 -State 'closed' -MergedAt '2026-08-01T00:00:00Z')
    }
    $merged = Get-TigerWinGetPkgsPreviousPr -Cli (New-PrCli $mergedRoutes) -Config $cfg
    Assert-True ($merged.check.status -ceq 'PASS' -and $merged.pullRequest.number -eq 100) 'A merged latest PR passes.'

    $closedRoutes = @{
        'api search/issues*' = [pscustomobject]@{ items = @([pscustomobject]@{ number = 101; pull_request = [pscustomobject]@{} }) }
        'api repos/microsoft/winget-pkgs/pulls/101' = (New-Pr -Number 101 -State 'closed' -MergedAt '')
    }
    Assert-True ((Get-TigerWinGetPkgsPreviousPr -Cli (New-PrCli $closedRoutes) -Config $cfg).check.status -ceq 'PASS') `
        'A manually closed latest PR passes.'

    $openRoutes = @{
        'api search/issues*' = [pscustomobject]@{ items = @([pscustomobject]@{ number = 102; pull_request = [pscustomobject]@{} }) }
        'api repos/microsoft/winget-pkgs/pulls/102' = (New-Pr -Number 102 -State 'open' -MergedAt '')
    }
    $open = Get-TigerWinGetPkgsPreviousPr -Cli (New-PrCli $openRoutes) -Config $cfg
    Assert-True ($open.check.status -ceq 'BLOCKED' -and $open.check.evidence -match 'PR #102') 'An open latest PR blocks with evidence.'

    $draftRoutes = @{
        'api search/issues*' = [pscustomobject]@{ items = @([pscustomobject]@{ number = 103; pull_request = [pscustomobject]@{} }) }
        'api repos/microsoft/winget-pkgs/pulls/103' = (New-Pr -Number 103 -State 'open' -Draft $true -MergedAt '')
    }
    Assert-True ((Get-TigerWinGetPkgsPreviousPr -Cli (New-PrCli $draftRoutes) -Config $cfg).check.status -ceq 'BLOCKED') `
        'An open draft latest PR blocks.'

    # A newer PR from a different fork owner, and a newer one for another Tiger
    # project, are both ignored; our merged PR is the match.
    $filteredRoutes = @{
        'api search/issues*' = [pscustomobject]@{ items = @(
            [pscustomobject]@{ number = 300; pull_request = [pscustomobject]@{} }
            [pscustomobject]@{ number = 200; pull_request = [pscustomobject]@{} }
            [pscustomobject]@{ number = 100; pull_request = [pscustomobject]@{} }
        ) }
        'api repos/microsoft/winget-pkgs/pulls/300' = (New-Pr -Number 300 -State 'open' -MergedAt '' -HeadOwner 'someone-else')
        'api repos/microsoft/winget-pkgs/pulls/200' = (New-Pr -Number 200 -State 'open' -MergedAt '' -HeadRef 'ItTiger-TigerOther-2.0.0')
        'api repos/microsoft/winget-pkgs/pulls/100' = (New-Pr -Number 100 -State 'closed' -MergedAt '2026-07-01T00:00:00Z')
    }
    $filtered = Get-TigerWinGetPkgsPreviousPr -Cli (New-PrCli $filteredRoutes) -Config $cfg
    Assert-True ($filtered.check.status -ceq 'PASS' -and $filtered.pullRequest.number -eq 100) `
        'PRs from another fork owner or another Tiger project are not the previous PR.'
    Write-Host 'PASS: the previous-PR gate is project-specific and blocks only open or draft PRs'

    Write-Host
    Write-Host 'PASS: winget-pkgs clone safety checks' -ForegroundColor Green
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
