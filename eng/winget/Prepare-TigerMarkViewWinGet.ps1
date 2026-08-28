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
Write-Output $manifestDirectory
