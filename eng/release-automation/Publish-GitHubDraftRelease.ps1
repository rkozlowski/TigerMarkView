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

    [switch] $PlanOnly,

    [switch] $AllowDifferentHeadForRecovery
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
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
        git -C $repoRoot tag -a $tag $CommitSha -m "TigerMarkView $Version"
        if ($LASTEXITCODE -ne 0) { throw "Could not create annotated tag '$tag'." }
    }
    git -C $repoRoot push origin "refs/tags/$tag"
    if ($LASTEXITCODE -ne 0) { throw "Could not push annotated tag '$tag'." }
}

if ($null -eq $release) {
    $arguments = @(
        'release', 'create', $tag,
        '--repo', $Repository,
        '--draft',
        '--verify-tag',
        '--generate-notes',
        '--title', $title
    ) + @($assets | ForEach-Object FullName)
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

Write-Host "Draft GitHub Release '$title' is ready for maintainer review."
