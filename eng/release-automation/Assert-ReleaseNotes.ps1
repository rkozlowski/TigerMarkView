#Requires -Version 7.0
<#
    .SYNOPSIS
    Proves the checked-in release-notes source for a version is useful and clean.

    .DESCRIPTION
    Wraps Test-TigerMarkViewReleaseNotes so the release workflow and a maintainer
    can gate on .github/release-notes/<version>.md directly. Throws on anything but
    PASS; the readiness command folds the same check into its report instead.

    .PARAMETER Version
    The release version whose notes file to check.

    .PARAMETER NotesRoot
    The directory holding <version>.md. Defaults to .github/release-notes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Version,

    [string] $NotesRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ReleaseAutomation.ps1')

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$check = Test-TigerMarkViewReleaseNotes -Version $Version -RepositoryRoot $repositoryRoot -NotesRoot $NotesRoot

if ($check.status -cne 'PASS') {
    throw ("Release notes for $Version are not ready: $($check.observed) " +
        "$(if ($check.remediation) { $check.remediation })")
}

Write-Host "PASS: $($check.observed)" -ForegroundColor Green
