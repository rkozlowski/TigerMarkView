#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$wingetDirectory = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $wingetDirectory)
$prepareScript = Join-Path $wingetDirectory 'Prepare-TigerMarkViewWinGet.ps1'
[xml] $versionXml = Get-Content -LiteralPath (Join-Path $repositoryRoot 'Version.props') -Raw
$version = [string] $versionXml.Project.PropertyGroup.Version
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("TigerMarkViewWinGet-tests-" + [Guid]::NewGuid().ToString('N'))
$installerDirectory = Join-Path $testRoot 'installer'
$installerPath = Join-Path $installerDirectory "TigerMarkView-$version-win-x64-setup.exe"
$installerUrl = "https://github.com/rkozlowski/TigerMarkView/releases/download/v$version/TigerMarkView-$version-win-x64-setup.exe"
$productCode = [regex]::Escape("'{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}_is1'")

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-InstallerManifest {
    param(
        [Parameter(Mandatory)]
        [string] $OutputRoot
    )

    Get-Content -LiteralPath (
        Join-Path $OutputRoot "manifests\i\ItTiger\TigerMarkView\$version\ItTiger.TigerMarkView.installer.yaml") -Raw
}

function Assert-AppsAndFeaturesBlocks {
    param(
        [Parameter(Mandatory)]
        [string] $Manifest,

        [string] $ExpectedDisplayVersion
    )

    $displayVersionLine = if ([string]::IsNullOrEmpty($ExpectedDisplayVersion)) {
        ''
    }
    else {
        "    DisplayVersion: $([regex]::Escape($ExpectedDisplayVersion))\r?\n"
    }
    $pattern = "(?m)^  AppsAndFeaturesEntries:\r?\n" +
        "  - DisplayName: TigerMarkView\r?\n" +
        "    Publisher: IT Tiger\r?\n" +
        $displayVersionLine +
        "    ProductCode: $productCode\r?\n" +
        '    InstallerType: inno\r?$'
    $matches = [regex]::Matches($Manifest, $pattern)
    Assert-True ($matches.Count -eq 2) `
        "Expected two correctly indented AppsAndFeaturesEntries blocks; found $($matches.Count)."
}

try {
    New-Item -ItemType Directory -Path $installerDirectory -Force | Out-Null
    [IO.File]::WriteAllBytes($installerPath, [byte[]] (0..31))

    $defaultOutput = Join-Path $testRoot 'default'
    & $prepareScript `
        -InstallerPath $installerPath `
        -OutputRoot $defaultOutput `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl
    $defaultManifest = Get-InstallerManifest -OutputRoot $defaultOutput
    Assert-True ($defaultManifest -cnotmatch '(?m)^\s+DisplayVersion:') `
        'DisplayVersion must be omitted when no installed display version is supplied.'
    Assert-AppsAndFeaturesBlocks -Manifest $defaultManifest
    Write-Host 'PASS: default DisplayVersion is omitted'

    $sameOutput = Join-Path $testRoot 'same'
    & $prepareScript `
        -InstallerPath $installerPath `
        -OutputRoot $sameOutput `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -InstalledDisplayVersion $version
    $sameManifest = Get-InstallerManifest -OutputRoot $sameOutput
    Assert-True ($sameManifest -cnotmatch '(?m)^\s+DisplayVersion:') `
        'DisplayVersion must be omitted when the installed version equals PackageVersion.'
    Assert-AppsAndFeaturesBlocks -Manifest $sameManifest
    Write-Host 'PASS: equal DisplayVersion is omitted'

    $differentOutput = Join-Path $testRoot 'different'
    $differentVersion = "$version.0"
    & $prepareScript `
        -InstallerPath $installerPath `
        -OutputRoot $differentOutput `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -InstalledDisplayVersion $differentVersion
    $differentManifest = Get-InstallerManifest -OutputRoot $differentOutput
    $displayVersionMatches = [regex]::Matches(
        $differentManifest,
        "(?m)^    DisplayVersion: $([regex]::Escape($differentVersion))\r?$")
    Assert-True ($displayVersionMatches.Count -eq 2) `
        'A differing DisplayVersion must be emitted for both installer scopes.'
    Assert-AppsAndFeaturesBlocks -Manifest $differentManifest -ExpectedDisplayVersion $differentVersion
    Write-Host 'PASS: differing DisplayVersion is preserved with valid indentation'
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
