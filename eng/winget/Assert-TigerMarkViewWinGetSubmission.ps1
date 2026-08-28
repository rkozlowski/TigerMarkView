#Requires -Version 7.0
<#
    .SYNOPSIS
    Proves a directory is the TigerMarkView WinGet submission set and reports its digest.

    .DESCRIPTION
    The release workflow validates one manifest set and then uploads it. This is
    what makes "the same set" checkable on both sides of that upload: it asserts
    the directory holds exactly the three submission manifests, UTF-8 without a
    byte-order mark, that all three agree on identity and version, and that the
    installer manifest names the immutable v<version> release asset URL. It then
    prints a digest over the three files.

    The validation job records that digest; the publication job downloads the
    uploaded artifact and recomputes it. A submission set that changed in transit
    cannot survive both.

    Nothing is written into the manifest directory, so the directory this passes
    on remains exactly what is copied into a winget-pkgs fork.

    .PARAMETER ManifestDirectory
    The submission directory to check.

    .PARAMETER Version
    The release version the set must describe.

    .PARAMETER ExpectedInstallerSha256
    When supplied, the digest the installer manifest must declare.

    .PARAMETER ExpectedDigest
    When supplied, the submission digest the set must reproduce. This is the
    transfer check.

    .PARAMETER GitHubOutput
    When supplied, a GITHUB_OUTPUT file to append 'submission_sha256' to.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ManifestDirectory,

    [Parameter(Mandatory)]
    [string] $Version,

    [string] $ExpectedInstallerSha256,

    [string] $ExpectedDigest,

    [string] $GitHubOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'TigerMarkViewWinGet.ps1')

$submission = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $ManifestDirectory -Version $Version
$release = $submission.release

foreach ($document in @('installer', 'locale', 'version')) {
    $facts = $submission.$document
    if ($facts.packageIdentifier -cne $release.packageIdentifier) {
        throw ("The $document manifest declares PackageIdentifier " +
            "'$($facts.packageIdentifier)'; expected '$($release.packageIdentifier)'.")
    }
    if ($facts.packageVersion -cne $Version) {
        throw "The $document manifest declares PackageVersion '$($facts.packageVersion)'; expected '$Version'."
    }
}

if ($submission.installer.installerUrl -cne $release.installerUrl) {
    throw ("The installer manifest declares InstallerUrl '$($submission.installer.installerUrl)'; " +
        "the immutable release asset URL is '$($release.installerUrl)'.")
}
if ([string] $submission.installer.installerSha256 -cnotmatch '^[0-9A-F]{64}$') {
    throw "The installer manifest declares a malformed InstallerSha256 '$($submission.installer.installerSha256)'."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedInstallerSha256) -and
    $submission.installer.installerSha256 -cne $ExpectedInstallerSha256.ToUpperInvariant()) {
    throw ("The installer manifest declares InstallerSha256 '$($submission.installer.installerSha256)'; " +
        "the installer hashes to '$($ExpectedInstallerSha256.ToUpperInvariant())'.")
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedDigest) -and $submission.digest -cne $ExpectedDigest.ToLowerInvariant()) {
    throw ("The submission set hashes to '$($submission.digest)'; the validated set hashed to " +
        "'$($ExpectedDigest.ToLowerInvariant())'. These are not the same manifests.")
}

Write-Host "PASS: '$($submission.directory)' is the $($release.packageIdentifier) $Version submission set." -ForegroundColor Green
foreach ($document in $submission.documents) {
    Write-Host ('  {0}  {1} ({2} bytes)' -f $document.sha256, $document.name, $document.length)
}
Write-Host "Submission digest: $($submission.digest)"
Write-Host "winget-pkgs path: $($release.submissionPath)"

if (-not [string]::IsNullOrWhiteSpace($GitHubOutput)) {
    "submission_sha256=$($submission.digest)" | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
}

Write-Output $submission.digest
