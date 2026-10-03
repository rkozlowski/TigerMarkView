#Requires -Version 7.0
<#
    .SYNOPSIS
    Closes the release artifact set: the installer, the sealed WinGet manifests that
    describe it, the version's privacy statement, their recorded hashes, and the
    record that names the commit they were built from.

    .DESCRIPTION
    With -InstallerPath the artifact directory is created and populated here, so
    the release workflow needs no staging or copying step of its own: the
    directory this writes holds the installer, TigerMarkView-<version>-WinGet.zip,
    PRIVACY.md, SHA256SUMS.txt, and release-artifacts.json and nothing else.

    The archive is packed from the sealed submission directory, never regenerated,
    and release-artifacts.json records the submission digest of what it holds, so
    the published archive can be proven to carry the exact manifest bytes the
    workflow sealed.

    PRIVACY.md is the privacy statement frozen for this version: a byte-for-byte copy
    of -PrivacyStatementPath, the docs\PRIVACY.md the installer was built with. It is
    what the version's WinGet PrivacyUrl names, so once published it can never come
    to describe another version.

    .PARAMETER ArtifactDirectory
    The closed release directory to write.

    .PARAMETER Version
    The release version.

    .PARAMETER CommitSha
    The commit the artifacts were built from.

    .PARAMETER InstallerPath
    The installer to place in the artifact directory. When omitted, the installer
    is expected to be there already.

    .PARAMETER WinGetManifestDirectory
    The sealed submission directory: exactly the three manifests.

    .PARAMETER PrivacyStatementPath
    The privacy statement to freeze as PRIVACY.md: the repository's docs\PRIVACY.md,
    the same file the installer carries as Docs\PRIVACY.md.

    .PARAMETER ExpectedSubmissionDigest
    When supplied, the submission digest the sealing step recorded. The archive
    must hold exactly that set.

    .PARAMETER GitHubOutput
    When supplied, a GITHUB_OUTPUT file to append 'manifest_sha256' to - the
    transfer check the publication job repeats after downloading the artifact.
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

    [string] $InstallerPath,

    [Parameter(Mandatory)]
    [string] $WinGetManifestDirectory,

    [Parameter(Mandatory)]
    [string] $PrivacyStatementPath,

    [string] $ExpectedSubmissionDigest,

    [string] $GitHubOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'winget' 'TigerMarkViewWinGet.ps1')

if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Invalid release version '$Version'."
}

$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
$release = Get-TigerMarkViewWinGetRelease -Version $Version
$installerName = $release.installerFileName
$archiveName = $release.wingetArchiveFileName
if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
    if ([IO.Path]::GetFileName($InstallerPath) -cne $installerName) {
        throw "The release installer must be named '$installerName'."
    }
    if (Test-Path -LiteralPath $ArtifactDirectory) {
        Remove-Item -LiteralPath $ArtifactDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $ArtifactDirectory -Force | Out-Null
    Copy-Item -LiteralPath $InstallerPath -Destination (Join-Path $ArtifactDirectory $installerName)
}

$archivePath = Join-Path $ArtifactDirectory $archiveName
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
$archive = New-TigerMarkViewWinGetArchive -ManifestDirectory $WinGetManifestDirectory -Version $Version -Path $archivePath
if (-not [string]::IsNullOrWhiteSpace($ExpectedSubmissionDigest) -and
    $archive.digest -cne $ExpectedSubmissionDigest.ToLowerInvariant()) {
    throw ("The WinGet archive holds the set '$($archive.digest)'; the sealed set is " +
        "'$($ExpectedSubmissionDigest.ToLowerInvariant())'.")
}

$privacyName = $release.privacyStatementFileName
$PrivacyStatementPath = [IO.Path]::GetFullPath($PrivacyStatementPath)
if (-not (Test-Path -LiteralPath $PrivacyStatementPath -PathType Leaf)) {
    throw "Privacy statement not found: $PrivacyStatementPath"
}
$privacyPath = Join-Path $ArtifactDirectory $privacyName
if ($PrivacyStatementPath -cne [IO.Path]::GetFullPath($privacyPath)) {
    Copy-Item -LiteralPath $PrivacyStatementPath -Destination $privacyPath -Force
}
$privacySha256 = (Get-FileHash -LiteralPath $privacyPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($privacySha256 -cne (Get-FileHash -LiteralPath $PrivacyStatementPath -Algorithm SHA256).Hash.ToLowerInvariant()) {
    throw "$privacyName is not a byte-for-byte copy of '$PrivacyStatementPath'."
}

$expectedNames = @($installerName, $archiveName, $privacyName)
$actualNames = @(Get-ChildItem -LiteralPath $ArtifactDirectory -File | ForEach-Object Name)
$missing = @($expectedNames | Where-Object { $_ -cnotin $actualNames })
$unexpected = @($actualNames | Where-Object { $_ -cnotin $expectedNames })
if ($missing.Count -ne 0 -or $unexpected.Count -ne 0) {
    throw "Release payload mismatch. Missing: $($missing -join ', '); unexpected: $($unexpected -join ', ')."
}

$installerFile = Get-Item -LiteralPath (Join-Path $ArtifactDirectory $installerName)
$artifacts = @(
    [ordered]@{
        name = $installerName
        kind = 'WindowsInstaller'
        length = $installerFile.Length
        sha256 = (Get-FileHash -LiteralPath $installerFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    [ordered]@{
        name = $archiveName
        kind = 'WinGetManifests'
        length = $archive.length
        sha256 = $archive.sha256
        submissionSha256 = $archive.digest
    }
    [ordered]@{
        name = $privacyName
        kind = 'PrivacyStatement'
        length = (Get-Item -LiteralPath $privacyPath).Length
        sha256 = $privacySha256
    }
)

$manifestPath = Join-Path $ArtifactDirectory 'release-artifacts.json'
$checksumPath = Join-Path $ArtifactDirectory 'SHA256SUMS.txt'
[ordered]@{
    schemaVersion = 1
    releaseVersion = $Version
    sourceCommit = $CommitSha.ToLowerInvariant()
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    artifacts = $artifacts
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

@($artifacts | ForEach-Object { "$($_.sha256)  $($_.name)" }) |
    Set-Content -LiteralPath $checksumPath -Encoding utf8NoBOM
Write-Host "Recorded the closed TigerMarkView $Version release artifact set."
Write-Host "$archiveName holds the sealed WinGet submission set $($archive.digest)."
Write-Host "$privacyName is the privacy statement of $Version, SHA-256 $privacySha256."

$manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "release-artifacts.json SHA-256: $manifestSha256"
if (-not [string]::IsNullOrWhiteSpace($GitHubOutput)) {
    "manifest_sha256=$manifestSha256" | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
}
