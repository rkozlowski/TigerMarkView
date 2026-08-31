#Requires -Version 7.0
<#
    .SYNOPSIS
    Validates a published TigerMarkView release against the WinGet submission set
    its release workflow sealed, and reports whether that set is ready to copy into
    microsoft/winget-pkgs.

    .DESCRIPTION
    The gate itself lives in eng\winget\WinGetReleaseValidation.ps1 as
    Invoke-TigerMarkViewWinGetReleaseValidation, so the post-release submission
    orchestrator can require the identical result without a child process and
    without this command's exit code deciding anything for it. This script is the
    maintainer-facing command around that one function: it resolves the version,
    runs the gate, renders the summary, and maps the report status to an exit code.

    A PASS here says the sealed manifests, the published asset, and a clean-guest
    WinGet install all agree. It does not touch the winget-pkgs clone; that is
    eng\winget\Prepare-TigerMarkViewWinGetSubmission.ps1, which runs this gate
    first and requires its full result.

    GitHub is reached only through the authenticated `gh` session established by
    `gh auth login`. No token is accepted, read from the environment, or logged.

    .PARAMETER Version
    The published release version to validate. Defaults to Version.props.

    .PARAMETER ArchivePath
    An already-downloaded TigerMarkView-WinGet-<version>-<commit>.zip, for a machine
    that cannot reach the artifact endpoint. It is verified against the same
    recorded digest as a download, so it is a different route to the sealed bytes,
    not a weaker check.

    .PARAMETER ExpectedSubmissionDigest
    When supplied, the submission digest the sealed set must reproduce - the value
    the release workflow's sealing step recorded.

    .PARAMETER Refresh
    Re-downloads the sealed artifact even when a retained, provenance-bound copy
    already matches everything GitHub records for it.

    .PARAMETER TigerWinLabRoot
    An explicit TigerWinLab working copy. Omit it and the lab is discovered from
    the TigerAiCore configuration named by TigerAiCoreConfig. There is no sibling
    checkout or environment-variable fallback: an unregistered lab fails the lab
    check rather than being guessed at, because validating a release against a
    lab nobody chose is worse than not validating it here.

    .PARAMETER SkipLab
    Runs the manifest and published-asset checks only. Useful for re-checking a
    published release quickly; it can never produce a submission-ready PASS.

    .EXAMPLE
    .\eng\winget\Test-TigerMarkViewWinGet.ps1 -Version 0.8.1
#>
[CmdletBinding()]
param(
    [string] $Version,
    [string] $ArchivePath,
    [string] $ExpectedSubmissionDigest,
    [string] $TigerWinLabRoot,
    [string] $WinGetPath,
    [ValidateRange(1, 240)]
    [int] $TimeoutMinutes = 45,
    [switch] $Refresh,
    [switch] $SkipLab,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'WinGetReleaseValidation.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string] (Get-TigerMarkViewWinGetVersionProperty -RepositoryRoot $repoRoot).Version
}

$validation = Invoke-TigerMarkViewWinGetReleaseValidation `
    -RepositoryRoot $repoRoot `
    -Version $Version `
    -ArchivePath $ArchivePath `
    -ExpectedSubmissionDigest $ExpectedSubmissionDigest `
    -TigerWinLabRoot $TigerWinLabRoot `
    -WinGetPath $WinGetPath `
    -TimeoutMinutes $TimeoutMinutes `
    -Refresh:$Refresh `
    -SkipLab:$SkipLab

if ($null -eq $validation.submission) {
    # The sealed set was never obtained, so there is no WinGet-specific evidence to
    # render; the shared report says everything that is known.
    if ($Json) { $validation.report | ConvertTo-Json -Depth 12 }
    else { foreach ($line in (Format-TigerMarkViewReleaseSummary -Report $validation.report)) { Write-Host $line } }
    exit $validation.report.exitCode
}

if ($Json) {
    $validation.result | ConvertTo-Json -Depth 12
}
else {
    foreach ($line in (Format-TigerMarkViewWinGetSummary -Result $validation.result)) {
        Write-Host $line.text -ForegroundColor $line.colour
    }
}

exit $validation.report.exitCode
