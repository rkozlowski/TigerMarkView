#Requires -Version 7.0
<#
    .SYNOPSIS
    Creates (or safely reuses) the annotated tag and the draft GitHub Release for a
    validated artifact set, then hands publication to a human.

    .DESCRIPTION
    Nothing here publishes: the release is created as a draft, and the run ends
    with the `READY FOR HUMAN ACTION` handoff describing exactly what the
    maintainer must review and do next. The same handoff is written to the
    workflow step summary, so the release workflow needs no summary logic of its
    own.

    .PARAMETER ArtifactDirectory
    The validated release directory: installer, SHA256SUMS.txt, release-artifacts.json.

    .PARAMETER Version
    The release version.

    .PARAMETER CommitSha
    The validated commit the tag must name.

    .PARAMETER Repository
    owner/name.

    .PARAMETER NotesFile
    The checked-in version-specific release notes. Strongly preferred: without it
    GitHub's generic generated notes are used.

    .PARAMETER WinGetArtifactName
    The sealed WinGet submission artifact for this release, quoted in the handoff.

    .PARAMETER WinGetSubmissionDigest
    That set's submission digest, quoted in the handoff.

    .PARAMETER RunUrl
    The workflow run to link from the handoff.

    .PARAMETER StepSummaryPath
    A file to append the Markdown handoff to. Defaults to $env:GITHUB_STEP_SUMMARY.

    .PARAMETER PlanOnly
    Reports what would be created and changes nothing.

    .PARAMETER AllowDifferentHeadForRecovery
    Permits running from a later checkout during recovery; the retained manifest
    and the tag must still identify the original validated commit.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ArtifactDirectory,

    [Parameter(Mandatory)]
    [string] $Version,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $CommitSha,

    [string] $Repository = 'rkozlowski/TigerMarkView',

    [string] $NotesFile,

    [string] $WinGetArtifactName,

    [string] $WinGetSubmissionDigest,

    [string] $RunUrl,

    [string] $StepSummaryPath,

    [switch] $PlanOnly,

    [switch] $AllowDifferentHeadForRecovery
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ReleaseAutomation.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$constant = Get-TigerMarkViewReleaseConstant
if ([string]::IsNullOrWhiteSpace($StepSummaryPath)) { $StepSummaryPath = $env:GITHUB_STEP_SUMMARY }

# Prefer a deliberate, checked-in notes file over GitHub's generic generated
# notes. When one is given it must pass the same readiness check the workflow
# gate runs, so a draft is never created from placeholder or leaky notes.
$resolvedNotesFile = $null
if (-not [string]::IsNullOrWhiteSpace($NotesFile)) {
    $resolvedNotesFile = [IO.Path]::GetFullPath($NotesFile)
    if (-not (Test-Path -LiteralPath $resolvedNotesFile -PathType Leaf)) {
        throw "Release notes file not found: $resolvedNotesFile"
    }
    & (Join-Path $PSScriptRoot 'Assert-ReleaseNotes.ps1') -Version $Version -NotesRoot (Split-Path -Parent $resolvedNotesFile)
}
$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
& (Join-Path $PSScriptRoot 'Assert-ReleaseArtifactManifest.ps1') `
    -ArtifactDirectory $ArtifactDirectory `
    -ExpectedVersion $Version `
    -ExpectedCommit $CommitSha

foreach ($commandName in @('git.exe', 'gh.exe')) {
    if ($null -eq (Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "Required command '$commandName' is unavailable."
    }
}

$head = (git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the current Git commit.' }
if (-not $AllowDifferentHeadForRecovery -and $head -cne $CommitSha) {
    throw "Current HEAD '$head' is not the validated release commit '$CommitSha'."
}

$tag = "v$Version"
$title = "TigerMarkView $Version"
$assetNames = @(
    "TigerMarkView-$Version-win-x64-setup.exe"
    'SHA256SUMS.txt'
    'release-artifacts.json'
)
$assets = @($assetNames | ForEach-Object { Get-Item -LiteralPath (Join-Path $ArtifactDirectory $_) })

$remoteTag = (git -C $repoRoot ls-remote --tags origin "refs/tags/$tag" | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not inspect remote tag '$tag'." }
$tagExists = -not [string]::IsNullOrWhiteSpace($remoteTag)
if ($tagExists) {
    git -C $repoRoot fetch --force origin "refs/tags/${tag}:refs/tags/${tag}" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Could not fetch existing tag '$tag'." }
    $tagCommit = (git -C $repoRoot rev-list -n 1 $tag).Trim()
    if ($tagCommit -cne $CommitSha) {
        throw "Tag '$tag' points to '$tagCommit', not '$CommitSha'; it will never be moved."
    }
}

$releaseJson = gh release view $tag --repo $Repository --json isDraft,name,tagName,assets 2>$null
$releaseExit = $LASTEXITCODE
$release = if ($releaseExit -eq 0) { $releaseJson | ConvertFrom-Json } else { $null }
if ($null -ne $release) {
    if (-not $release.isDraft -or $release.tagName -cne $tag -or $release.name -cne $title) {
        throw "Existing release '$tag' is not the compatible draft '$title'."
    }

    $remoteAssets = @($release.assets)
    $unexpected = @($remoteAssets | Where-Object { $_.name -cnotin $assetNames })
    if ($unexpected.Count -ne 0) {
        throw "Draft '$tag' contains unexpected assets: $($unexpected.name -join ', ')."
    }
    foreach ($asset in $assets) {
        $remote = @($remoteAssets | Where-Object name -CEQ $asset.Name)
        if ($remote.Count -gt 1) { throw "Draft '$tag' contains duplicate asset '$($asset.Name)'." }
        if ($remote.Count -eq 1) {
            $hash = (Get-FileHash -LiteralPath $asset.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            if ([long] $remote[0].size -ne $asset.Length -or [string] $remote[0].digest -cne "sha256:$hash") {
                throw "Draft asset '$($asset.Name)' is not byte-identical to the validated artifact."
            }
        }
    }
}

Write-Host "Release plan for $tag at $CommitSha"
Write-Host "  annotated tag: $(if ($tagExists) { 'already compatible' } else { 'create and push' })"
Write-Host "  draft release: $(if ($null -eq $release) { 'create' } else { 'reuse compatible draft' })"
Write-Host "  release notes: $(if ($resolvedNotesFile) { "from $resolvedNotesFile" } else { 'GitHub --generate-notes (generic)' })"
foreach ($asset in $assets) {
    $present = $null -ne $release -and @($release.assets | Where-Object name -CEQ $asset.Name).Count -eq 1
    Write-Host "  asset: $($asset.Name) ($(if ($present) { 'already identical' } else { 'upload' }))"
}
if ($PlanOnly) {
    Write-Host 'PLAN ONLY: no tag, release, or asset was changed.'
    return
}

if (-not $tagExists) {
    $localTagCommit = git -C $repoRoot rev-list -n 1 $tag 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($localTagCommit)) {
        if ($localTagCommit.Trim() -cne $CommitSha) {
            throw "Local tag '$tag' points somewhere else and will not be changed."
        }
    }
    else {
        git -C $repoRoot config user.name 'github-actions[bot]'
        git -C $repoRoot config user.email '41898282+github-actions[bot]@users.noreply.github.com'
        git -C $repoRoot tag -a $tag $CommitSha -m "TigerMarkView $Version"
        if ($LASTEXITCODE -ne 0) { throw "Could not create annotated tag '$tag'." }
    }
    git -C $repoRoot push origin "refs/tags/$tag"
    if ($LASTEXITCODE -ne 0) { throw "Could not push annotated tag '$tag'." }
}

if ($null -eq $release) {
    $notesArguments = if ($resolvedNotesFile) {
        @('--notes-file', $resolvedNotesFile)
    }
    else {
        # Generic generated notes are a last resort, not the finished design: the
        # workflow gate requires a checked-in notes file before it reaches here.
        @('--generate-notes')
    }
    $arguments = @(
        'release', 'create', $tag,
        '--repo', $Repository,
        '--draft',
        '--verify-tag',
        '--title', $title
    ) + $notesArguments + @($assets | ForEach-Object FullName)
    & gh @arguments
    if ($LASTEXITCODE -ne 0) { throw "Could not create draft release '$tag'." }
}
else {
    foreach ($asset in $assets) {
        if (@($release.assets | Where-Object name -CEQ $asset.Name).Count -eq 0) {
            gh release upload $tag $asset.FullName --repo $Repository
            if ($LASTEXITCODE -ne 0) { throw "Could not upload '$($asset.Name)'." }
        }
    }
}

# The draft exists. Everything from here is the handoff: one report, rendered for
# the terminal and for the workflow summary, in the shared release vocabulary.
$draftUrl = "$($constant.repositoryUrl)/releases/tag/$tag"
$checks = @(
    New-TigerMarkViewReleaseCheck -Id 'release/tag' -Status 'PASS' `
        -Observed "Annotated tag '$tag' names $CommitSha." -Evidence $CommitSha
    New-TigerMarkViewReleaseCheck -Id 'release/draft' -Status 'PASS' `
        -Observed "Draft release '$title' is at $draftUrl." -Evidence $draftUrl
    New-TigerMarkViewReleaseCheck -Id 'release/notes' -Status $(if ($resolvedNotesFile) { 'PASS' } else { 'WARN' }) `
        -Observed $(if ($resolvedNotesFile) {
            "Notes came from $([IO.Path]::GetFileName($resolvedNotesFile))."
        }
        else {
            'Notes were generated by GitHub and are generic.'
        }) `
        -Remediation $(if ($resolvedNotesFile) { '' } else { 'Replace the notes before publishing.' })
) + @($assets | ForEach-Object {
    New-TigerMarkViewReleaseCheck -Id "release/asset/$($_.Name)" -Status 'PASS' `
        -Observed "$($_.Name) ($($_.Length) bytes) is attached to the draft."
})
if (-not [string]::IsNullOrWhiteSpace($WinGetArtifactName)) {
    $checks += New-TigerMarkViewReleaseCheck -Id 'winget/sealed-set' -Status 'PASS' `
        -Observed "Sealed submission artifact '$WinGetArtifactName' digest $WinGetSubmissionDigest." `
        -Evidence $WinGetSubmissionDigest
}
if (-not [string]::IsNullOrWhiteSpace($RunUrl)) {
    $checks += New-TigerMarkViewReleaseCheck -Id 'release/run' -Status 'PASS' -Observed $RunUrl -Evidence $RunUrl
}

$report = New-TigerMarkViewReleaseReport -Title "Draft GitHub Release for TigerMarkView $Version" `
    -Checks $checks `
    -Handoff @(
        "Review the draft at $draftUrl - tag, commit, the three assets, the recorded hashes, and the notes."
        'Confirm the notes state the runtime prerequisites and the current unsigned status.'
        'Publish the draft explicitly. Automation never publishes it.'
    ) `
    -NextCommand ("After publication, run: pwsh eng/winget/Prepare-TigerMarkViewWinGetSubmission.ps1 " +
        "-Version $Version") `
    -Context @{ version = $Version; commit = $CommitSha; tag = $tag; draftUrl = $draftUrl }

if (-not [string]::IsNullOrWhiteSpace($StepSummaryPath)) {
    (Format-TigerMarkViewReleaseSummary -Report $report -Markdown) |
        Out-File -FilePath $StepSummaryPath -Encoding utf8 -Append
}
foreach ($line in (Format-TigerMarkViewReleaseSummary -Report $report)) { Write-Host $line }
