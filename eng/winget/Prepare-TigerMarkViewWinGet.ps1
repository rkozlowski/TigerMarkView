#Requires -Version 7.0
<#
    .SYNOPSIS
    Generates a TigerMarkView WinGet submission set from a local installer.

    .DESCRIPTION
    This is the only thing in the repository that writes a manifest, and it serves
    two roles that must not be confused:

      - locally, before a release exists, to see and review what the manifests will
        say; and
      - inside the release workflow, over the installer that workflow just built,
        producing the set the workflow then validates, seals, and uploads as
        TigerMarkView-WinGet-<version>-<commit>.

    Only the second produces the authoritative post-release submission. A set
    generated locally hashes a locally built installer, and an Inno rebuild is never
    byte-identical to the one CI compiled, so its InstallerSha256 will not be the
    published one. Copying a local set into winget-pkgs, or validating one as though
    it were the release's, is precisely the mistake the post-release gate refuses to
    make: Test-TigerMarkViewWinGet.ps1 reads the sealed workflow artifact and never
    the output of this script.

    Output goes to artifacts\winget\manifests\i\ItTiger\TigerMarkView\<version>\ by
    default; the post-release submission lives elsewhere, under
    artifacts\winget-release\<version>\submission\.

    .PARAMETER InstallerPath
    The installer to hash. Defaults to artifacts\installer\<installer file name>.

    .PARAMETER OutputRoot
    The root the manifests\... path is created under. Defaults to artifacts\winget.

    .PARAMETER ExpectedVersion
    When supplied, the version Version.props must already be at.

    .PARAMETER InstallerUrl
    The immutable release asset URL. Defaults to, and must equal, the v<version> URL.

    .PARAMETER ExpectedInstallerSha256
    When supplied, the digest the installer must hash to.

    .PARAMETER InstalledDisplayVersion
    An ARP display version that genuinely differs from PackageVersion. Omitted otherwise.

    .PARAMETER Validate
    Runs winget validate over the generated set.

    .EXAMPLE
    .\eng\winget\Prepare-TigerMarkViewWinGet.ps1
#>
[CmdletBinding()]
param(
    [string] $InstallerPath,
    [string] $OutputRoot,
    [string] $ExpectedVersion,
    [string] $InstallerUrl,
    [string] $ExpectedInstallerSha256,
    [string] $InstalledDisplayVersion,
    [string] $WinGetPath,
    [switch] $Validate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'TigerMarkViewWinGet.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$properties = Get-TigerMarkViewWinGetVersionProperty -RepositoryRoot $repoRoot
$version = [string] $properties.Version
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and $version -cne $ExpectedVersion) {
    throw "Version.props '$version' does not match expected version '$ExpectedVersion'."
}

$repositoryUrl = ([string] $properties.RepositoryUrl).TrimEnd('/')
$release = Get-TigerMarkViewWinGetRelease -Version $version -RepositoryUrl $repositoryUrl
$packageIdentifier = $release.packageIdentifier
$issueTrackerUrl = ([string] $properties.IssueTrackerUrl).Replace('$(RepositoryUrl)', $repositoryUrl)
$websiteUrl = [string] $properties.WebsiteUrl
$installerFileName = $release.installerFileName
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = Join-Path $repoRoot "artifacts\installer\$installerFileName"
}
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw "Installer not found: $InstallerPath"
}
if ([IO.Path]::GetFileName($InstallerPath) -cne $installerFileName) {
    throw "Installer filename must be '$installerFileName'."
}

$expectedUrl = $release.installerUrl
if ([string]::IsNullOrWhiteSpace($InstallerUrl)) { $InstallerUrl = $expectedUrl }
if ($InstallerUrl -cne $expectedUrl) { throw "Installer URL must be '$expectedUrl'." }

$installerHash = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToUpperInvariant()
if (-not [string]::IsNullOrWhiteSpace($ExpectedInstallerSha256) -and
    $installerHash -cne $ExpectedInstallerSha256.ToUpperInvariant()) {
    throw "Installer SHA-256 '$installerHash' does not match '$ExpectedInstallerSha256'."
}

if ([string]::IsNullOrWhiteSpace($InstalledDisplayVersion)) {
    $InstalledDisplayVersion = $version
}
if ($InstalledDisplayVersion -match '[\r\n]') {
    throw 'InstalledDisplayVersion must be a single-line value.'
}
$displayVersionEntry = if ($InstalledDisplayVersion -cne $version) {
    "    DisplayVersion: $InstalledDisplayVersion`r`n"
}
else {
    ''
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'artifacts\winget' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$manifestDirectory = Get-TigerMarkViewWinGetManifestDirectory -OutputRoot $OutputRoot -Version $version
if (Test-Path -LiteralPath $manifestDirectory) {
    $safeRoot = $OutputRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath($manifestDirectory)
    if (-not $resolved.StartsWith($safeRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace manifests outside '$OutputRoot'."
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null

$productCode = '{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}_is1'
$installerManifest = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.1.12.0.schema.json
PackageIdentifier: $packageIdentifier
PackageVersion: $version
InstallerLocale: en-US
Platform:
- Windows.Desktop
MinimumOSVersion: 10.0.14393.0
InstallerType: inno
InstallModes:
- interactive
- silent
- silentWithProgress
UpgradeBehavior: install
Commands:
- tiger-mark
Dependencies:
  PackageDependencies:
  - PackageIdentifier: Microsoft.DotNet.DesktopRuntime.10
  - PackageIdentifier: Microsoft.EdgeWebView2Runtime
Installers:
- Architecture: x64
  Scope: machine
  InstallerUrl: $InstallerUrl
  InstallerSha256: $installerHash
  InstallerSwitches:
    Silent: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS /TASKS="addtopath"
    SilentWithProgress: /SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS /TASKS="addtopath"
  ProductCode: '$productCode'
  AppsAndFeaturesEntries:
  - DisplayName: $($properties.Product)
    Publisher: $($properties.Company)
$displayVersionEntry    ProductCode: '$productCode'
    InstallerType: inno
- Architecture: x64
  Scope: user
  InstallerUrl: $InstallerUrl
  InstallerSha256: $installerHash
  InstallerSwitches:
    Silent: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER /TASKS="addtopath"
    SilentWithProgress: /SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER /TASKS="addtopath"
  ProductCode: '$productCode'
  AppsAndFeaturesEntries:
  - DisplayName: $($properties.Product)
    Publisher: $($properties.Company)
$displayVersionEntry    ProductCode: '$productCode'
    InstallerType: inno
ManifestType: installer
ManifestVersion: 1.12.0
"@

$localeManifest = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.1.12.0.schema.json
PackageIdentifier: $packageIdentifier
PackageVersion: $version
PackageLocale: en-US
Publisher: $($properties.Company)
PublisherUrl: $websiteUrl
PublisherSupportUrl: $issueTrackerUrl
Author: $($properties.Authors)
PackageName: $($properties.Product)
PackageUrl: $repositoryUrl
License: $($properties.LicenseIdentity)
LicenseUrl: $repositoryUrl/blob/v$version/LICENSE
Copyright: $($properties.Copyright)
ShortDescription: $($properties.Description)
Description: |-
  TigerMarkView is a Windows desktop application for reading and reviewing local Markdown files.
  The installer includes the graphical viewer and the tiger-mark Markdown-to-PDF command.
Moniker: tiger-markview
Tags:
- markdown
- pdf
- viewer
Documentations:
- DocumentLabel: Help
  DocumentUrl: $repositoryUrl/blob/v$version/docs/HELP.md
ReleaseNotesUrl: $repositoryUrl/releases/tag/v$version
ManifestType: defaultLocale
ManifestVersion: 1.12.0
"@

$versionManifest = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.1.12.0.schema.json
PackageIdentifier: $packageIdentifier
PackageVersion: $version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.12.0
"@

Set-Content -LiteralPath (Join-Path $manifestDirectory "$packageIdentifier.installer.yaml") -Value $installerManifest -Encoding utf8NoBOM
Set-Content -LiteralPath (Join-Path $manifestDirectory "$packageIdentifier.locale.en-US.yaml") -Value $localeManifest -Encoding utf8NoBOM
Set-Content -LiteralPath (Join-Path $manifestDirectory "$packageIdentifier.yaml") -Value $versionManifest -Encoding utf8NoBOM

# Reading the set back is the shape gate: exactly the three submission manifests, no
# extra file, and no byte-order mark. What is on disk from here on is the submission.
$submission = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $manifestDirectory -Version $version
if ($installerManifest -notmatch '(?ms)Scope: machine.*?/ALLUSERS.*?Scope: user.*?/CURRENTUSER' -or
    $installerManifest -notmatch [regex]::Escape($installerHash) -or
    $installerManifest -notmatch [regex]::Escape($productCode)) {
    throw 'Generated installer scope, switch, hash, or product-code semantics are incomplete.'
}

if ($Validate) {
    $null = Invoke-TigerMarkViewWinGetValidation -ManifestDirectory $manifestDirectory -WinGetPath $WinGetPath
}

Write-Host "PASS: prepared $packageIdentifier $version manifests at '$manifestDirectory'." -ForegroundColor Green
Write-Host "Submission digest: $($submission.digest)"
Write-Host ('This is a locally generated set. The authoritative post-release submission is the ' +
    "release workflow's TigerMarkView-WinGet-$version-<commit> artifact.") -ForegroundColor DarkGray
Write-Output $manifestDirectory
