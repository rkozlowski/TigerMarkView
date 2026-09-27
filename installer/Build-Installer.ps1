<#
.SYNOPSIS
    Publishes TigerMarkView for Release win-x64 and builds its TigerSetup installer.

.DESCRIPTION
    One repeatable command, no IDE steps:

        pwsh installer\Build-Installer.ps1

    Produces artifacts\installer\TigerMarkView-<version>-win-x64-setup.exe, where <version> comes
    from Version.props by way of the published executable's version resource. The staging directory
    contains both the GUI and tiger-mark; the installer is built only after their metadata agrees,
    and tiger-setup's own [metadata] check then refuses a TigerMarkView.exe that disagrees with the
    project. installer\TigerSetup.toml is the package; installer\tigersetup.json pins the builder.

.PARAMETER SkipPublish
    Build the installer from the existing artifacts\publish\win-x64 folder without republishing.

.PARAMETER NoBuild
    Publish already-built Release win-x64 outputs without compiling or restoring. Release automation
    uses this after its single solution build so the exact built binaries are packaged.

.PARAMETER Version
    A local candidate's version, overriding Version.props as an MSBuild global property for both the
    publish and the installer build; how an upgrade candidate is produced without editing the
    repository. Release automation never passes it.

.PARAMETER TigerSetupPath
    Full path to tiger-setup.exe. Defaults to tiger-setup.exe on PATH. Its version must be the one
    installer\tigersetup.json pins, so a local build and the release build use the same builder.

.PARAMETER Fast
    tiger-setup build --fast: functionally identical, larger, much quicker. For iteration only.
#>
[CmdletBinding()]
param(
    [string] $Configuration = 'Release',
    [switch] $SkipPublish,
    [switch] $NoBuild,
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,
    [string] $TigerSetupPath,
    [switch] $Fast
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'TigerSetupBuilder.ps1')

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$AppProject = Join-Path $RepoRoot 'src\TigerMarkView\TigerMarkView.csproj'
$CliProject = Join-Path $RepoRoot 'src\TigerMarkView.Cli\TigerMarkView.Cli.csproj'
$VersionProps = Join-Path $RepoRoot 'Version.props'
$Manifest   = Join-Path $PSScriptRoot 'TigerSetup.toml'
$PublishDir = Join-Path $RepoRoot 'artifacts\publish\win-x64'
$OutputDir  = Join-Path $RepoRoot 'artifacts\installer'
$AppExe     = Join-Path $PublishDir 'TigerMarkView.exe'
$CliExe     = Join-Path $PublishDir 'tiger-mark.exe'

Write-Host '== TigerSetup builder ==' -ForegroundColor Cyan
$tigerSetup = Resolve-TigerMarkViewTigerSetup -RepositoryRoot $RepoRoot -Path $TigerSetupPath
Write-Host "  $tigerSetup ($((Get-TigerMarkViewTigerSetupPin -RepositoryRoot $RepoRoot).version))"

[xml] $versionDocument = Get-Content -LiteralPath $VersionProps -Raw
$company = [string] $versionDocument.Project.PropertyGroup.Company
$candidateVersion = if ($Version) { $Version } else { [string] $versionDocument.Project.PropertyGroup.Version }
if ([string]::IsNullOrWhiteSpace($candidateVersion)) { throw 'Version.props does not define Version.' }
if ([string]::IsNullOrWhiteSpace($company)) { throw 'Version.props does not define Company.' }
$versionProperty = if ($Version) { @("-p:Version=$Version") } else { @() }

if ($SkipPublish) {
    Write-Host "== Skipping publish, using $PublishDir ==" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $AppExe)) {
        throw "No publish output at '$PublishDir'. Run without -SkipPublish first."
    }
} else {
    Write-Host "== Staging GUI and CLI ($Configuration win-x64) ==" -ForegroundColor Cyan
    # A stale file left in the publish folder would be packaged as though it belonged there.
    if (Test-Path -LiteralPath $PublishDir) {
        Remove-Item -LiteralPath $PublishDir -Recurse -Force
    }

    # Framework-dependent on purpose: neither the .NET runtime nor WebView2 is bundled; the installer
    # declares both as dependencies instead.
    $publishArguments = @(
        '--configuration', $Configuration,
        '--runtime', 'win-x64',
        '--self-contained', 'false',
        '--output', $PublishDir,
        '-m:1'
    ) + $versionProperty
    if ($NoBuild) {
        $publishArguments += @('--no-build', '--no-restore')
    }

    foreach ($project in @($AppProject, $CliProject)) {
        dotnet publish $project @publishArguments
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet publish failed for '$project' with exit code $LASTEXITCODE."
        }
    }
}

Write-Host '== Version ==' -ForegroundColor Cyan
# Version.props -> AssemblyInformationalVersion -> ProductVersion. Build metadata is stripped here
# exactly as Core.About.ApplicationVersion.Format strips it for the About dialog.
foreach ($executable in @($AppExe, $CliExe)) {
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Required product executable is missing from installer staging: '$executable'."
    }

    $versionInfo = (Get-Item -LiteralPath $executable).VersionInfo
    $productVersion = $versionInfo.ProductVersion
    if ([string]::IsNullOrWhiteSpace($productVersion) -or $productVersion.Split('+')[0] -cne $candidateVersion) {
        throw "'$executable' ProductVersion '$productVersion' does not match '$candidateVersion'."
    }
    if ($versionInfo.CompanyName -cne $company) {
        throw "'$executable' CompanyName '$($versionInfo.CompanyName)' is not the canonical publisher."
    }
    Write-Host "  $([IO.Path]::GetFileName($executable)): $productVersion"
}

Write-Host '== Building installer ==' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$expected = Join-Path $OutputDir "TigerMarkView-$candidateVersion-win-x64-setup.exe"
# Removed first, so a failed build can never leave an earlier installer looking like this one.
Remove-Item -LiteralPath $expected -Force -ErrorAction SilentlyContinue

$buildArguments = @('build', $Manifest, '--output', $expected)
if ($Version) { $buildArguments += @('--property', "Version=$Version") }
if ($Fast) { $buildArguments += '--fast' }
& $tigerSetup @buildArguments
if ($LASTEXITCODE -ne 0) { throw "tiger-setup build failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath $expected -PathType Leaf)) {
    throw "Expected installer '$expected' was not produced."
}

& $tigerSetup verify $expected
if ($LASTEXITCODE -ne 0) { throw "tiger-setup verify rejected '$expected' (exit code $LASTEXITCODE)." }

$installer = Get-Item -LiteralPath $expected
Write-Host ''
Write-Host '== Done ==' -ForegroundColor Green
Write-Host ("  {0}  ({1:N1} MB)" -f $installer.FullName, ($installer.Length / 1MB))
