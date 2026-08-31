#Requires -Version 7.0
<#
    .SYNOPSIS
    Downloads the sealed WinGet submission set a published release was built from.

    .DESCRIPTION
    After a release is published there is exactly one authoritative WinGet
    submission set: the three manifests the release workflow generated from that
    release's installer, validated, sealed, and uploaded as
    TigerMarkView-WinGet-<version>-<commit>. This retrieves that artifact and
    nothing else.

    The chain it follows is the whole point:

      version -> the published release tagged v<version>
              -> the commit that tag names
              -> the one workflow artifact whose run built that commit
              -> the archive whose SHA-256 is the digest GitHub recorded
              -> exactly three manifests, UTF-8 without a byte-order mark.

    Every link is checked and a broken link throws. There is deliberately no
    fallback to artifacts\winget\, where Prepare-TigerMarkViewWinGet.ps1 writes: a
    locally generated set describes a locally built installer, whose hash is not the
    published one, and submitting it is the failure this script exists to prevent.

    GitHub is reached only through the authenticated `gh` session that
    `gh auth login` established. No token is accepted, read from the environment,
    or logged. On a machine that cannot reach the artifact endpoint at all, pass an
    already-downloaded artifact archive with -ArchivePath; it is verified against
    the same recorded digest, so it is a different route to the same bytes rather
    than a weaker check.

    .PARAMETER Version
    The published release version whose sealed set to fetch. Defaults to Version.props.

    .PARAMETER ArchivePath
    An already-downloaded TigerMarkView-WinGet-<version>-<commit>.zip to use instead
    of downloading. It must still match the digest GitHub recorded for the artifact.

    .PARAMETER ExpectedSubmissionDigest
    When supplied, the submission digest the sealed set must reproduce - the value
    the release workflow's sealing step recorded.

    .PARAMETER Force
    Re-downloads even when a retained, provenance-bound copy already matches
    everything GitHub records for the artifact.

    .EXAMPLE
    .\eng\winget\Get-TigerMarkViewWinGetReleaseSubmission.ps1 -Version 0.8.1
#>
[CmdletBinding()]
param(
    [string] $Version,
    [string] $ArchivePath,
    [string] $ExpectedSubmissionDigest,
    [switch] $Force,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'TigerMarkViewWinGet.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string] (Get-TigerMarkViewWinGetVersionProperty -RepositoryRoot $repoRoot).Version
}

$client = New-TigerMarkViewGitHubClient
$acquired = Get-TigerMarkViewWinGetSealedSubmission `
    -RepositoryRoot $repoRoot `
    -Version $Version `
    -Client $client `
    -ArchivePath $ArchivePath `
    -ExpectedSubmissionDigest $ExpectedSubmissionDigest `
    -Force:$Force

$provenance = $acquired.provenance
Write-Host "PASS: '$($provenance.submissionDirectory)' is the sealed $Version submission set." -ForegroundColor Green
Write-Host "  Artifact:          $($provenance.artifactName) (id $($provenance.artifactId))"
Write-Host "  Workflow run:      $($provenance.workflowRunId)"
Write-Host "  Release commit:    $($provenance.commit)"
Write-Host "  Archive source:    $($provenance.archiveSource)"
Write-Host "  Archive SHA-256:   $($provenance.archiveSha256)"
Write-Host "  Submission digest: $($provenance.submissionDigest)"
foreach ($document in $acquired.submission.documents) {
    Write-Host ('  {0}  {1} ({2} bytes)' -f $document.sha256, $document.name, $document.length)
}

if ($Json) {
    $provenance | ConvertTo-Json -Depth 8
}
else {
    Write-Output $provenance.submissionDirectory
}
