#Requires -Version 7.0
<#
    .SYNOPSIS
    Proves a directory holds exactly the recorded TigerMarkView release bytes.

    .DESCRIPTION
    The set is the installer, TigerMarkView-<version>-WinGet.zip, SHA256SUMS.txt,
    and release-artifacts.json. Both recorded artifacts must match their recorded
    length and SHA-256, SHA256SUMS.txt must say exactly the same, and the archive
    must hold exactly the three submission manifests whose submission digest the
    record names.

    .PARAMETER ArtifactDirectory
    The release directory to check.

    .PARAMETER ExpectedVersion
    The version the manifest must describe.

    .PARAMETER ExpectedCommit
    The commit the manifest must name.

    .PARAMETER ExpectedManifestSha256
    When supplied, the SHA-256 release-artifacts.json itself must have. This is
    the transfer check: the validation job records the hash and the publication
    job repeats it over the downloaded artifact, so an upload that changed the
    manifest cannot survive both.

    .PARAMETER ExpectedSubmissionDigest
    When supplied, the submission digest the sealing step recorded: the archive
    the release publishes must hold exactly that sealed set.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ArtifactDirectory,

    [Parameter(Mandatory)]
    [string] $ExpectedVersion,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $ExpectedCommit,

    [string] $ExpectedManifestSha256,

    [string] $ExpectedSubmissionDigest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'winget' 'TigerMarkViewWinGet.ps1')

$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
$manifestPath = Join-Path $ArtifactDirectory 'release-artifacts.json'
$checksumPath = Join-Path $ArtifactDirectory 'SHA256SUMS.txt'
if (-not [string]::IsNullOrWhiteSpace($ExpectedManifestSha256)) {
    $manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($manifestSha256 -cne $ExpectedManifestSha256.ToLowerInvariant()) {
        throw ("release-artifacts.json hashes to '$manifestSha256'; the validated manifest hashed to " +
            "'$($ExpectedManifestSha256.ToLowerInvariant())'. The artifact changed in transit.")
    }
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or
    $manifest.releaseVersion -cne $ExpectedVersion -or
    $manifest.sourceCommit -cne $ExpectedCommit.ToLowerInvariant()) {
    throw 'Release manifest identity does not match the requested release.'
}

$release = Get-TigerMarkViewWinGetRelease -Version $ExpectedVersion
$expected = [ordered]@{
    $release.installerFileName = 'WindowsInstaller'
    $release.wingetArchiveFileName = 'WinGetManifests'
}
$entries = @($manifest.artifacts)
$recorded = @($entries | ForEach-Object { "$($_.name)=$($_.kind)" })
$wanted = @($expected.Keys | ForEach-Object { "$_=$($expected[$_])" })
if (($recorded -join ',') -cne ($wanted -join ',')) {
    throw "Release manifest records '$($recorded -join ', ')', not the installer and its WinGet archive."
}

$allowedNames = @(@($expected.Keys) + @('release-artifacts.json', 'SHA256SUMS.txt'))
$actualNames = @(Get-ChildItem -LiteralPath $ArtifactDirectory -File | ForEach-Object Name)
$missing = @($allowedNames | Where-Object { $_ -cnotin $actualNames })
$unexpected = @($actualNames | Where-Object { $_ -cnotin $allowedNames })
if ($missing.Count -ne 0 -or $unexpected.Count -ne 0) {
    throw "Release directory mismatch. Missing: $($missing -join ', '); unexpected: $($unexpected -join ', ')."
}

foreach ($entry in $entries) {
    $path = Join-Path $ArtifactDirectory $entry.name
    $file = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne [long] $entry.length -or $hash -cne [string] $entry.sha256) {
        throw "Release artifact '$($entry.name)' does not match its recorded bytes."
    }
}

$archiveEntry = $entries[1]
$archive = Read-TigerMarkViewWinGetArchive -Path (Join-Path $ArtifactDirectory $archiveEntry.name) -Version $ExpectedVersion
if ($null -eq $archiveEntry.PSObject.Properties['submissionSha256'] -or
    $archive.digest -cne [string] $archiveEntry.submissionSha256) {
    throw "$($archiveEntry.name) does not hold the WinGet submission set release-artifacts.json records."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedSubmissionDigest) -and
    $archive.digest -cne $ExpectedSubmissionDigest.ToLowerInvariant()) {
    throw ("$($archiveEntry.name) holds the set '$($archive.digest)'; the sealed set is " +
        "'$($ExpectedSubmissionDigest.ToLowerInvariant())'.")
}

$expectedChecksums = @($entries | ForEach-Object { "$($_.sha256)  $($_.name)" }) -join [Environment]::NewLine
$actualChecksums = (Get-Content -LiteralPath $checksumPath -Raw).TrimEnd("`r", "`n") -replace "`r`n", "`n"
if ($actualChecksums -cne ($expectedChecksums -replace "`r`n", "`n")) {
    throw 'SHA256SUMS.txt does not exactly match release-artifacts.json.'
}

Write-Host "Verified exact TigerMarkView $ExpectedVersion release bytes at $ExpectedCommit."
Write-Host "$($archiveEntry.name) holds the sealed WinGet submission set $($archive.digest)."
