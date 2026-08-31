#Requires -Version 7.0
<#
    .SYNOPSIS
    Deterministic pieces of TigerMarkView release preparation.

    .DESCRIPTION
    Dot-source this file. It owns the narrow, mechanical parts of preparing a
    release so the maintainer-facing scripts and their tests share one
    implementation:

      - which files may carry a literal product version (Version.props and the
        release workflow's dispatch default), and detection of any other tracked
        code file that hardcodes one;
      - the version-string update itself, with a plan/-WhatIf form; and
      - the checks that the workflow default and Version.props agree.

    Judgment-based work - release notes, changed public documentation - is not
    here. That belongs to the maintainer following docs/maintainers.
#>

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ReleaseAutomation.ps1')

# Shipped product and installer sources must never hardcode the version:
# assemblies, About, CLI output, and installer identity all derive it from
# Version.props at build time. The scan is deliberately scoped to those trees
# (plus the repository-wide build files) - engineering scripts, tests, workflows,
# release notes, and documentation legitimately name a version in examples and
# history, so they are not scanned.
$script:TigerMarkViewVersionScanPrefixes = @(
    'src/'
    'installer/'
)

$script:TigerMarkViewVersionScanRootFiles = @(
    'Directory.Build.props'
    'Directory.Build.targets'
    'TigerMarkView.slnx'
)

# Version.props is the single source, so it is never a "hardcoded" hit.
$script:TigerMarkViewVersionScanExcludedFiles = @(
    'Version.props'
)

# Only these tracked file kinds are scanned for a hardcoded version.
$script:TigerMarkViewVersionScanExtensions = @(
    '.cs', '.csproj', '.props', '.targets', '.axaml', '.xaml', '.iss',
    '.ps1', '.psm1', '.psd1', '.slnx'
)

function Get-TigerMarkViewVersionPropsPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepositoryRoot)
    Join-Path $RepositoryRoot 'Version.props'
}

function Get-TigerMarkViewReleaseWorkflowPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepositoryRoot)
    Join-Path $RepositoryRoot '.github/workflows/release.yml'
}

function Read-TigerMarkViewConfiguredVersion {
    <#
        .SYNOPSIS
        The version currently recorded in Version.props.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepositoryRoot)

    [xml] $props = Get-Content -LiteralPath (Get-TigerMarkViewVersionPropsPath -RepositoryRoot $RepositoryRoot) -Raw
    [string] $props.Project.PropertyGroup.Version
}

function Get-TigerMarkViewReleaseWorkflowDefault {
    <#
        .SYNOPSIS
        The workflow_dispatch version default in release.yml, or $null.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepositoryRoot)

    $text = Get-Content -LiteralPath (Get-TigerMarkViewReleaseWorkflowPath -RepositoryRoot $RepositoryRoot) -Raw
    $match = [regex]::Match($text, "(?ms)inputs:\s*\r?\n\s*version:.*?\bdefault:\s*'(?<value>[^']*)'")
    if ($match.Success) { return $match.Groups['value'].Value }
    $null
}

function Find-TigerMarkViewUnexpectedVersionLiteral {
    <#
        .SYNOPSIS
        Tracked code files, outside the allow list, that hardcode the given
        version string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $Version
    )

    $previousNative = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $tracked = @(& git -C $RepositoryRoot ls-files)
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $previousNative
        $global:LASTEXITCODE = 0
    }

    $needle = [regex]::Escape($Version)
    # A version boundary: not preceded/followed by a digit or dot, so 0.8.1 does
    # not match inside 10.8.11.
    $pattern = "(?<![\d.])$needle(?![\d.])"

    $findings = [Collections.Generic.List[object]]::new()
    foreach ($relative in $tracked) {
        $normalized = $relative -replace '\\', '/'
        if ($normalized -cin $script:TigerMarkViewVersionScanExcludedFiles) { continue }
        if ($normalized -match '(^|/)(tests?|bin|obj)/') { continue }
        $inScope = ($normalized -cin $script:TigerMarkViewVersionScanRootFiles) -or
            ($script:TigerMarkViewVersionScanPrefixes | Where-Object { $normalized.StartsWith($_) })
        if (-not $inScope) { continue }
        $extension = [IO.Path]::GetExtension($normalized).ToLowerInvariant()
        if ($extension -cnotin $script:TigerMarkViewVersionScanExtensions) { continue }

        $full = Join-Path $RepositoryRoot $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $lineNumber = 0
        foreach ($line in [IO.File]::ReadAllLines($full)) {
            $lineNumber++
            if ([regex]::IsMatch($line, $pattern)) {
                $findings.Add([pscustomobject][ordered]@{
                    file = $normalized
                    line = $lineNumber
                    text = $line.Trim()
                })
            }
        }
    }
    $findings.ToArray()
}

function Set-TigerMarkViewVersionInFiles {
    <#
        .SYNOPSIS
        Rewrites the version in Version.props and the release-workflow default.

        .DESCRIPTION
        Returns one record per file describing the change (or that no change was
        needed). With -PlanOnly nothing is written. Refuses to run when a tracked
        code file outside the allow list hardcodes the current version: that file
        must be dealt with first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $Version,
        [switch] $PlanOnly
    )

    if (-not (Test-TigerMarkViewReleaseVersion -Version $Version)) {
        throw "Invalid release version '$Version'."
    }

    $current = Read-TigerMarkViewConfiguredVersion -RepositoryRoot $RepositoryRoot
    $unexpected = @()
    if ($current -cne $Version) {
        $unexpected = @(Find-TigerMarkViewUnexpectedVersionLiteral -RepositoryRoot $RepositoryRoot -Version $current)
    }
    if ($unexpected.Count -gt 0) {
        $list = ($unexpected | ForEach-Object { "$($_.file):$($_.line)" }) -join ', '
        throw ("Refusing to bump the version: these tracked files hardcode the current version " +
            "$current and must derive it from Version.props instead: $list.")
    }

    $changes = [Collections.Generic.List[object]]::new()

    $propsPath = Get-TigerMarkViewVersionPropsPath -RepositoryRoot $RepositoryRoot
    $propsText = Get-Content -LiteralPath $propsPath -Raw
    $newPropsText = [regex]::Replace($propsText, '(<Version>)[^<]*(</Version>)', "`${1}$Version`${2}", 1)
    $changes.Add([pscustomobject][ordered]@{
        file = 'Version.props'
        changed = $newPropsText -cne $propsText
        from = $current
        to = $Version
    })
    if (-not $PlanOnly -and $newPropsText -cne $propsText) {
        [IO.File]::WriteAllText($propsPath, $newPropsText, [Text.UTF8Encoding]::new($false))
    }

    $workflowPath = Get-TigerMarkViewReleaseWorkflowPath -RepositoryRoot $RepositoryRoot
    $workflowText = Get-Content -LiteralPath $workflowPath -Raw
    $currentDefault = Get-TigerMarkViewReleaseWorkflowDefault -RepositoryRoot $RepositoryRoot
    $newWorkflowText = [regex]::Replace(
        $workflowText,
        "(?ms)(inputs:\s*\r?\n\s*version:.*?\bdefault:\s*')[^']*(')",
        "`${1}$Version`${2}",
        1)
    $changes.Add([pscustomobject][ordered]@{
        file = '.github/workflows/release.yml'
        changed = $newWorkflowText -cne $workflowText
        from = $currentDefault
        to = $Version
    })
    if (-not $PlanOnly -and $newWorkflowText -cne $workflowText) {
        [IO.File]::WriteAllText($workflowPath, $newWorkflowText, [Text.UTF8Encoding]::new($false))
    }

    $changes.ToArray()
}

function Test-TigerMarkViewReleasePreparation {
    <#
        .SYNOPSIS
        Read-only checks that the deterministic parts of preparation are done.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $Version
    )

    $checks = [Collections.Generic.List[object]]::new()

    $configured = Read-TigerMarkViewConfiguredVersion -RepositoryRoot $RepositoryRoot
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'prep/version-props' `
        -Condition ((Test-TigerMarkViewReleaseVersion -Version $Version) -and ($configured -ceq $Version)) `
        -PassObserved "Version.props records $Version." `
        -FailObserved "Version.props records '$configured', not '$Version'." `
        -Expected $Version -Evidence $configured `
        -Remediation "Run Set-TigerMarkViewReleaseVersion.ps1 -Version $Version."))

    $default = Get-TigerMarkViewReleaseWorkflowDefault -RepositoryRoot $RepositoryRoot
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'prep/workflow-default' `
        -Condition ($default -ceq $Version) `
        -PassObserved "The release workflow dispatch default is $Version." `
        -FailObserved "The release workflow dispatch default is '$default', not '$Version'." `
        -Expected $Version -Evidence $default `
        -Remediation "Run Set-TigerMarkViewReleaseVersion.ps1 -Version $Version."))

    $unexpected = @(Find-TigerMarkViewUnexpectedVersionLiteral -RepositoryRoot $RepositoryRoot -Version $Version)
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'prep/no-hardcoded-version' `
        -Condition ($unexpected.Count -eq 0) `
        -PassObserved 'No tracked code file outside Version.props hardcodes the release version.' `
        -FailObserved ("These tracked files hardcode $Version and should derive it from Version.props: " +
            (($unexpected | ForEach-Object { "$($_.file):$($_.line)" }) -join ', ') + '.') `
        -Remediation 'Replace each literal with the shared Version.props value.'))

    $checks.Add((Test-TigerMarkViewReleaseNotes -Version $Version -RepositoryRoot $RepositoryRoot))

    $checks.ToArray()
}
