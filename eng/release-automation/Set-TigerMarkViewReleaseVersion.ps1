#Requires -Version 7.0
<#
    .SYNOPSIS
    Updates the two deterministic version locations for a TigerMarkView release.

    .DESCRIPTION
    Writes the given version into `<Version>` in Version.props and into the
    `workflow_dispatch` default in .github/workflows/release.yml, and nothing
    else. Every other version-bearing surface - assemblies, About, CLI output,
    installer identity, artifact names - derives from Version.props at build time.

    Before writing it refuses if a tracked code file outside those two locations
    hardcodes the current version, because that file would drift.

    This script never commits, pushes, tags, or dispatches. Use -WhatIf to see the
    planned edits without touching the tree.

    .PARAMETER Version
    The release version to set (for example 0.9.0).

    .EXAMPLE
    pwsh eng/release-automation/Set-TigerMarkViewReleaseVersion.ps1 -Version 0.9.0 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [string] $Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ReleasePreparation.ps1')

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$planOnly = -not $PSCmdlet.ShouldProcess('Version.props and .github/workflows/release.yml', "set version to $Version")

$changes = Set-TigerMarkViewVersionInFiles -RepositoryRoot $repositoryRoot -Version $Version -PlanOnly:$planOnly

foreach ($change in $changes) {
    $verb = if ($planOnly) { 'would set' } else { if ($change.changed) { 'set' } else { 'already' } }
    Write-Host ("  {0,-32} {1} {2} -> {3}" -f $change.file, $verb, $change.from, $change.to)
}

if ($planOnly) {
    Write-Host 'PLAN ONLY: no file was modified.'
    return
}

Write-Host
Write-Host "Version set to $Version in the two deterministic locations." -ForegroundColor Green
Write-Host 'Next: update .github/release-notes/{0}.md and any changed public docs, then run' -f $Version
Write-Host '      eng/release-automation/Test-TigerMarkViewReleaseReadiness.ps1 -Version {0}' -f $Version
