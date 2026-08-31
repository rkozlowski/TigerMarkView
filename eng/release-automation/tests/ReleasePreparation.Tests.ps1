#Requires -Version 7.0
<#
    .SYNOPSIS
    Covers the deterministic release-preparation helpers in
    eng/release-automation/ReleasePreparation.ps1.

    .DESCRIPTION
    Builds a throwaway git repository shaped like TigerMarkView's version-bearing
    files and proves the version bump touches only the two approved locations, is
    idempotent, refuses when a code file hardcodes the version, and honours a
    plan-only run.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$automationRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $automationRoot 'ReleasePreparation.ps1')

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
        $out = (& git -C $Root @GitArgs 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
        $out
    }
    finally { $PSNativeCommandUseErrorActionPreference = $previous; $global:LASTEXITCODE = 0 }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('TigerReleasePrep-' + [Guid]::NewGuid().ToString('N'))

function New-Fixture {
    param([string] $Version = '0.8.1')

    $root = Join-Path $testRoot ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root '.github/workflows') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root '.github/release-notes') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $root 'Version.props') -Encoding utf8NoBOM -Value @"
<Project>
  <PropertyGroup>
    <Version>$Version</Version>
    <AssemblyVersion>`$(Version).0</AssemblyVersion>
  </PropertyGroup>
</Project>
"@
    Set-Content -LiteralPath (Join-Path $root '.github/workflows/release.yml') -Encoding utf8NoBOM -Value @"
name: Release TigerMarkView
on:
  workflow_dispatch:
    inputs:
      version:
        description: Exact release version already recorded in Version.props
        required: true
        default: '$Version'
        type: string
jobs:
  validate:
    runs-on: windows-latest
    steps:
      - run: echo build
"@
    Set-Content -LiteralPath (Join-Path $root '.github/release-notes/TEMPLATE.md') -Encoding utf8NoBOM -Value "## Highlights`n`nx`n`n## Fixed`n`nx"
    Set-Content -LiteralPath (Join-Path $root "docs/history.md") -Encoding utf8NoBOM `
        -Value "TigerMarkView $Version shipped the installer."
    Set-Content -LiteralPath (Join-Path $root 'src/Program.cs') -Encoding utf8NoBOM `
        -Value "// derives version from Version.props`nclass Program { }"

    Invoke-Git -Root $root -GitArgs @('init', '--quiet', '-b', 'main') | Out-Null
    Invoke-Git -Root $root -GitArgs @('config', 'user.email', 'test@example.com') | Out-Null
    Invoke-Git -Root $root -GitArgs @('config', 'user.name', 'Test') | Out-Null
    Invoke-Git -Root $root -GitArgs @('add', '-A') | Out-Null
    Invoke-Git -Root $root -GitArgs @('commit', '--quiet', '-m', 'fixture') | Out-Null
    $root
}

function New-GoodNotes {
    param([string] $Root, [string] $Version)
    Set-Content -LiteralPath (Join-Path $Root ".github/release-notes/$Version.md") -Encoding utf8NoBOM -Value @"
## Highlights

TigerMarkView $Version improves how the viewer renders wide tables and adds a
running-head option to the tiger-mark command line for exported PDFs.

## Fixed

- The reload indicator no longer sticks after a file is deleted and recreated.

## Prerequisites and known limitations

- Windows 10 or later, x64, with the .NET Desktop Runtime 10 and WebView2.
- This build is unsigned.
"@
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    # 1. Invalid versions are rejected before anything is written.
    $root = New-Fixture
    Assert-Throws -MessagePattern 'Invalid release version' -Action {
        Set-TigerMarkViewVersionInFiles -RepositoryRoot $root -Version 'v0.9' -PlanOnly
    }
    Write-Host 'PASS: an invalid version is rejected'

    # 2. A plan-only run reports the edits and changes nothing.
    $root = New-Fixture
    $plan = Set-TigerMarkViewVersionInFiles -RepositoryRoot $root -Version '0.9.0' -PlanOnly
    Assert-True ($plan.Count -eq 2) 'The plan covers exactly two files.'
    Assert-True (@($plan | Where-Object { $_.changed }).Count -eq 2) 'Both files would change.'
    Assert-True ((Read-TigerMarkViewConfiguredVersion -RepositoryRoot $root) -ceq '0.8.1') `
        'A plan-only run must not modify Version.props.'
    Assert-True ((Invoke-Git -Root $root -GitArgs @('status', '--porcelain')).Trim() -eq '') `
        'A plan-only run must leave the tree clean.'
    Write-Host 'PASS: -PlanOnly writes nothing'

    # 3. A real run touches only the two approved files, and sets both.
    $root = New-Fixture
    $changes = Set-TigerMarkViewVersionInFiles -RepositoryRoot $root -Version '0.9.0'
    Assert-True ((Read-TigerMarkViewConfiguredVersion -RepositoryRoot $root) -ceq '0.9.0') `
        'Version.props must record the new version.'
    Assert-True ((Get-TigerMarkViewReleaseWorkflowDefault -RepositoryRoot $root) -ceq '0.9.0') `
        'The workflow dispatch default must record the new version.'
    $touched = @((Invoke-Git -Root $root -GitArgs @('status', '--porcelain')) -split "\r?\n" |
        Where-Object { $_ } | ForEach-Object { ($_ -replace '^.{3}', '').Trim() })
    Assert-True (($touched | Sort-Object) -join ',' -ceq '.github/workflows/release.yml,Version.props') `
        "Only the two approved files may change; changed: $($touched -join ', ')."
    Write-Host 'PASS: a version bump touches only Version.props and the workflow default'

    # 4. Rerunning is idempotent: no further change.
    $again = Set-TigerMarkViewVersionInFiles -RepositoryRoot $root -Version '0.9.0'
    Assert-True (@($again | Where-Object { $_.changed }).Count -eq 0) 'A second run makes no change.'
    Write-Host 'PASS: the version bump is idempotent'

    # 5. A code file that hardcodes the current version blocks the bump and is
    #    surfaced by the readiness check.
    $root = New-Fixture
    Set-Content -LiteralPath (Join-Path $root 'src/Program.cs') -Encoding utf8NoBOM `
        -Value "class Program { const string V = ""0.8.1""; }"
    Invoke-Git -Root $root -GitArgs @('commit', '--quiet', '-am', 'hardcode') | Out-Null
    Assert-Throws -MessagePattern 'hardcode the current version' -Action {
        Set-TigerMarkViewVersionInFiles -RepositoryRoot $root -Version '0.9.0'
    }
    New-GoodNotes -Root $root -Version '0.8.1'
    $prepChecks = Test-TigerMarkViewReleasePreparation -RepositoryRoot $root -Version '0.8.1'
    $hardcoded = @($prepChecks | Where-Object { $_.id -ceq 'prep/no-hardcoded-version' })[0]
    Assert-True ($hardcoded.status -ceq 'FAIL') 'The readiness check flags a hardcoded version.'
    Assert-True ($hardcoded.observed -match 'src/Program\.cs:1') 'The finding names the file and line.'
    Write-Host 'PASS: a hardcoded version is detected and blocks the bump'

    # 6. A version in docs or release-notes is allowed and does not trip the check.
    $root = New-Fixture
    Set-TigerMarkViewVersionInFiles -RepositoryRoot $root -Version '0.9.0' | Out-Null
    New-GoodNotes -Root $root -Version '0.9.0'
    Set-Content -LiteralPath (Join-Path $root 'docs/history.md') -Encoding utf8NoBOM `
        -Value "TigerMarkView 0.9.0 followed 0.8.1."
    $prepChecks = Test-TigerMarkViewReleasePreparation -RepositoryRoot $root -Version '0.9.0'
    Assert-True (@($prepChecks | Where-Object { $_.status -cne 'PASS' }).Count -eq 0) `
        ("A fully prepared fixture should pass every deterministic check; failing: " +
        (@($prepChecks | Where-Object { $_.status -cne 'PASS' } | ForEach-Object { "$($_.id)=$($_.status)" }) -join ', '))
    Write-Host 'PASS: versions in docs and release notes are allowed'

    Write-Host
    Write-Host 'PASS: release preparation helpers' -ForegroundColor Green
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
