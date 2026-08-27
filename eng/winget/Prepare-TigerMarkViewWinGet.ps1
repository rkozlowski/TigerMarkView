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

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
[xml] $versionProps = Get-Content -LiteralPath (Join-Path $repoRoot 'Version.props') -Raw
$properties = $versionProps.Project.PropertyGroup
$version = [string] $properties.Version
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and $version -cne $ExpectedVersion) {
    throw "Version.props '$version' does not match expected version '$ExpectedVersion'."
}

$packageIdentifier = 'ItTiger.TigerMarkView'
$manifestVersion = [version] '1.12.0'
$repositoryUrl = [string] $properties.RepositoryUrl
$issueTrackerUrl = ([string] $properties.IssueTrackerUrl).Replace('$(RepositoryUrl)', $repositoryUrl)
$websiteUrl = [string] $properties.WebsiteUrl
$installerFileName = "TigerMarkView-$version-win-x64-setup.exe"
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

$expectedUrl = "https://github.com/rkozlowski/TigerMarkView/releases/download/v$version/$installerFileName"
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
$manifestDirectory = Join-Path $OutputRoot "manifests\i\ItTiger\TigerMarkView\$version"
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

foreach ($path in Get-ChildItem -LiteralPath $manifestDirectory -File -Filter '*.yaml') {
    $bytes = [IO.File]::ReadAllBytes($path.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "'$($path.Name)' must be UTF-8 without a byte-order mark."
    }
}
if ($installerManifest -notmatch '(?ms)Scope: machine.*?/ALLUSERS.*?Scope: user.*?/CURRENTUSER' -or
    $installerManifest -notmatch [regex]::Escape($installerHash) -or
    $installerManifest -notmatch [regex]::Escape($productCode)) {
    throw 'Generated installer scope, switch, hash, or product-code semantics are incomplete.'
}

if ($Validate) {
    if ([string]::IsNullOrWhiteSpace($WinGetPath)) {
        $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
        if ($null -eq $winget) { throw 'winget.exe is required for -Validate.' }
        $WinGetPath = $winget.Source
    }
    $WinGetPath = [IO.Path]::GetFullPath($WinGetPath)
    if (-not (Test-Path -LiteralPath $WinGetPath -PathType Leaf)) {
        throw "WinGet executable not found: $WinGetPath"
    }

    Write-Host "Validating manifest schema $manifestVersion with WinGet at '$WinGetPath'."
    $validationOutput = @(
        & $WinGetPath validate --manifest $manifestDirectory --disable-interactivity 2>&1
    )
    $validationExitCode = $LASTEXITCODE
    $validationOutput | ForEach-Object { Write-Host $_ }

    # WinGet documents 0x8A150028 as MANIFEST_VALIDATION_WARNING: validation succeeded
    # with warnings. Accept only that HRESULT; the client itself decides whether it
    # understands the manifest schema.
    $validationWarningExitCode = -1978335192
    if ($validationExitCode -eq $validationWarningExitCode) {
        Write-Warning 'WinGet manifest validation succeeded with warnings.'

        # The accepted warning HRESULT still lives in the caller's $LASTEXITCODE. Clear the
        # global copy so a hosting shell -- notably the GitHub Actions pwsh step, which ends
        # with 'exit $LASTEXITCODE' -- does not fail on a result this script treats as success.
        $global:LASTEXITCODE = 0
    }
    elseif ($validationExitCode -ne 0) {
        $unsignedExitCode = [uint32] ([int64] $validationExitCode -band 0xffffffffL)
        throw ('winget validate failed with exit code {0} (0x{1:X8}).' -f `
            $validationExitCode, $unsignedExitCode)
    }
}

Write-Host "PASS: prepared $packageIdentifier $version manifests at '$manifestDirectory'." -ForegroundColor Green
Write-Output $manifestDirectory
