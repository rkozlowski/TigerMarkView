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

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Action,

        [Parameter(Mandatory)]
        [string] $MessagePattern
    )

    try {
        try {
            & $Action
        }
        finally {
            # The action is expected to fail, frequently by way of a non-zero native exit code.
            # Clear $LASTEXITCODE so a handled failure cannot become the script's exit status.
            $global:LASTEXITCODE = 0
        }
    }
    catch {
        Assert-True ($_.Exception.Message -match $MessagePattern) `
            "Expected failure matching '$MessagePattern'; received '$($_.Exception.Message)'."
        return
    }

    throw "Expected an exception matching '$MessagePattern'."
}

function Set-FakeWinGetResult {
    param(
        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [int] $ValidateExitCode,

        [Parameter(Mandatory)]
        [string] $LogPath
    )

    $env:TIGERMARKVIEW_TEST_WINGET_VERSION = $Version
    $env:TIGERMARKVIEW_TEST_WINGET_EXIT = [string] $ValidateExitCode
    $env:TIGERMARKVIEW_TEST_WINGET_LOG = $LogPath
    Set-Content -LiteralPath $LogPath -Value '' -Encoding ascii
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

    $manifestDirectory = Join-Path $defaultOutput "manifests\i\ItTiger\TigerMarkView\$version"
    $manifestFiles = @(Get-ChildItem -LiteralPath $manifestDirectory -File -Filter '*.yaml')
    Assert-True ($manifestFiles.Count -eq 3) 'Expected exactly three generated WinGet manifests.'
    foreach ($manifestFile in $manifestFiles) {
        $manifestText = Get-Content -LiteralPath $manifestFile.FullName -Raw
        Assert-True ($manifestText -match '(?m)^# yaml-language-server: \$schema=https://aka\.ms/winget-manifest\..*\.1\.12\.0\.schema\.json\r?$') `
            "$($manifestFile.Name) does not target a schema 1.12.0 header URL."
        Assert-True ($manifestText -match '(?m)^ManifestVersion: 1\.12\.0\r?$') `
            "$($manifestFile.Name) does not declare ManifestVersion 1.12.0."
    }
    Write-Host 'PASS: all generated manifests consistently target schema 1.12.0'

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

    $fakeWinGet = Join-Path $testRoot 'winget-test.cmd'
    $fakeWinGetContent = @'
@echo off
echo %*>>"%TIGERMARKVIEW_TEST_WINGET_LOG%"
if "%~1"=="--version" (
  echo v%TIGERMARKVIEW_TEST_WINGET_VERSION%
  exit /b 0
)
if "%~1"=="validate" (
  echo Fake WinGet validation result %TIGERMARKVIEW_TEST_WINGET_EXIT%
  exit /b %TIGERMARKVIEW_TEST_WINGET_EXIT%
)
exit /b 2
'@
    Set-Content -LiteralPath $fakeWinGet -Value $fakeWinGetContent -Encoding ascii

    $unsupportedLog = Join-Path $testRoot 'unsupported-winget.log'
    Set-FakeWinGetResult -Version '1.11.510' -ValidateExitCode -1978335192 -LogPath $unsupportedLog
    Assert-Throws -MessagePattern 'cannot validate manifest schema 1\.12\.0' -Action {
        & $prepareScript `
            -InstallerPath $installerPath `
            -OutputRoot (Join-Path $testRoot 'unsupported-client') `
            -ExpectedVersion $version `
            -InstallerUrl $installerUrl `
            -WinGetPath $fakeWinGet `
            -Validate | Out-Host
    }
    $unsupportedInvocations = @(Get-Content -LiteralPath $unsupportedLog | Where-Object { $_ })
    Assert-True ($unsupportedInvocations.Count -eq 1 -and $unsupportedInvocations[0] -eq '--version') `
        'A schema-incompatible WinGet client must be rejected before manifest validation.'
    Write-Host 'PASS: WinGet 1.11 is rejected before validating schema 1.12.0 manifests'

    $successLog = Join-Path $testRoot 'success-winget.log'
    Set-FakeWinGetResult -Version '1.29.290' -ValidateExitCode 0 -LogPath $successLog
    & $prepareScript `
        -InstallerPath $installerPath `
        -OutputRoot (Join-Path $testRoot 'validation-success') `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -WinGetPath $fakeWinGet `
        -Validate | Out-Host
    $successInvocation = @(Get-Content -LiteralPath $successLog | Where-Object { $_ -like 'validate *' })
    Assert-True ($successInvocation.Count -eq 1 -and
        $successInvocation[0] -match '--disable-interactivity') `
        'Manifest validation must invoke WinGet exactly once with --disable-interactivity.'
    Write-Host 'PASS: supported WinGet validation is non-interactive'

    $warningLog = Join-Path $testRoot 'warning-winget.log'
    Set-FakeWinGetResult -Version '1.29.290' -ValidateExitCode -1978335192 -LogPath $warningLog
    & $prepareScript `
        -InstallerPath $installerPath `
        -OutputRoot (Join-Path $testRoot 'validation-warning') `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -WinGetPath $fakeWinGet `
        -Validate | Out-Host
    Write-Host 'PASS: only WinGet warning-success HRESULT 0x8A150028 is accepted'

    $failureLog = Join-Path $testRoot 'failure-winget.log'
    Set-FakeWinGetResult -Version '1.29.290' -ValidateExitCode -1978335191 -LogPath $failureLog
    Assert-Throws -MessagePattern '0x8A150029' -Action {
        & $prepareScript `
            -InstallerPath $installerPath `
            -OutputRoot (Join-Path $testRoot 'validation-failure') `
            -ExpectedVersion $version `
            -InstallerUrl $installerUrl `
            -WinGetPath $fakeWinGet `
            -Validate | Out-Host
    }
    Write-Host 'PASS: genuine WinGet manifest-validation failure HRESULT remains fatal'
}
finally {
    Remove-Item Env:TIGERMARKVIEW_TEST_WINGET_VERSION -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_WINGET_EXIT -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_WINGET_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
