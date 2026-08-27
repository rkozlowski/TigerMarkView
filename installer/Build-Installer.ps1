<#
.SYNOPSIS
    Publishes TigerMarkView for Release win-x64 and compiles the Inno Setup installer.

.DESCRIPTION
    One repeatable command, no IDE steps:

        pwsh installer\Build-Installer.ps1

    Produces artifacts\installer\TigerMarkView-<version>-win-x64-setup.exe, where <version> comes
    from Version.props by way of the published executable's version resource. The staging directory
    contains both the GUI and tiger-mark; the installer is compiled only after their metadata agrees.

.PARAMETER SkipPublish
    Compile the installer from the existing artifacts\publish\win-x64 folder without republishing.

.PARAMETER NoBuild
    Publish already-built Release win-x64 outputs without compiling or restoring. Release automation
    uses this after its single solution build so the exact validated binaries are packaged.

.PARAMETER InnoSetupPath
    Full path to ISCC.exe, when it is somewhere this script would not look.
#>
[CmdletBinding()]
param(
    [string] $Configuration = 'Release',
    [switch] $SkipPublish,
    [switch] $NoBuild,
    [string] $InnoSetupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$AppProject = Join-Path $RepoRoot 'src\TigerMarkView\TigerMarkView.csproj'
$CliProject = Join-Path $RepoRoot 'src\TigerMarkView.Cli\TigerMarkView.Cli.csproj'
$VersionProps = Join-Path $RepoRoot 'Version.props'
$IssScript  = Join-Path $PSScriptRoot 'TigerMarkView.iss'
$PublishDir = Join-Path $RepoRoot 'artifacts\publish\win-x64'
$OutputDir  = Join-Path $RepoRoot 'artifacts\installer'
$AppExe     = Join-Path $PublishDir 'TigerMarkView.exe'
$CliExe     = Join-Path $PublishDir 'tiger-mark.exe'

function Resolve-InnoSetupCompiler {
    param([string] $Explicit)

    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) {
            throw "ISCC.exe not found at '$Explicit'."
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }

    if ($env:INNOSETUP_PATH -and (Test-Path -LiteralPath $env:INNOSETUP_PATH)) {
        return (Resolve-Path -LiteralPath $env:INNOSETUP_PATH).Path
    }

    $onPath = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    # winget installs Inno Setup per-user when it cannot elevate, so LocalAppData is a real location
    # and not just a fallback.
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Programs'),
        ${env:ProgramFiles(x86)},
        $env:ProgramFiles
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($root in $roots) {
        foreach ($version in @('7', '6')) {
            $candidate = Join-Path $root "Inno Setup $version\ISCC.exe"
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }

    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $uninstallKeys) {
        $entries = Get-ItemProperty $key -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties.Name -contains 'DisplayName' -and $_.DisplayName -like 'Inno Setup*' }
        foreach ($entry in $entries) {
            if ($entry.PSObject.Properties.Name -contains 'InstallLocation' -and $entry.InstallLocation) {
                $candidate = Join-Path $entry.InstallLocation 'ISCC.exe'
                if (Test-Path -LiteralPath $candidate) { return $candidate }
            }
        }
    }

    throw @'
Inno Setup's command-line compiler (ISCC.exe) was not found.

Install it with:  winget install JRSoftware.InnoSetup.7
Then re-run this script, or pass -InnoSetupPath <path to ISCC.exe>.
'@
}

Write-Host '== Inno Setup compiler ==' -ForegroundColor Cyan
$iscc = Resolve-InnoSetupCompiler -Explicit $InnoSetupPath
Write-Host "  $iscc"

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

    # Framework-dependent on purpose: neither the .NET runtime nor WebView2 is bundled.
    $publishArguments = @(
        '--configuration', $Configuration,
        '--runtime', 'win-x64',
        '--self-contained', 'false',
        '--output', $PublishDir,
        '-m:1'
    )
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
[xml] $versionDocument = Get-Content -LiteralPath $VersionProps -Raw
$version = [string] $versionDocument.Project.PropertyGroup.Version
$company = [string] $versionDocument.Project.PropertyGroup.Company
if ([string]::IsNullOrWhiteSpace($version)) { throw "Version.props does not define Version." }
if ([string]::IsNullOrWhiteSpace($company)) { throw "Version.props does not define Company." }

foreach ($executable in @($AppExe, $CliExe)) {
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Required product executable is missing from installer staging: '$executable'."
    }

    $versionInfo = (Get-Item -LiteralPath $executable).VersionInfo
    $productVersion = $versionInfo.ProductVersion
    if ([string]::IsNullOrWhiteSpace($productVersion) -or $productVersion.Split('+')[0] -cne $version) {
        throw "'$executable' ProductVersion '$productVersion' does not match Version.props '$version'."
    }
    if ($versionInfo.CompanyName -cne $company) {
        throw "'$executable' CompanyName '$($versionInfo.CompanyName)' is not the canonical publisher."
    }
    Write-Host "  $([IO.Path]::GetFileName($executable)): $productVersion"
}

Write-Host '== Compiling installer ==' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

& $iscc "/DSourceDir=$PublishDir" "/DOutputDir=$OutputDir" $IssScript
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE." }

$expected = Join-Path $OutputDir "TigerMarkView-$version-win-x64-setup.exe"
if (-not (Test-Path -LiteralPath $expected)) {
    throw "Expected installer '$expected' was not produced."
}

$installer = Get-Item -LiteralPath $expected
Write-Host ''
Write-Host '== Done ==' -ForegroundColor Green
Write-Host ("  {0}  ({1:N1} MB)" -f $installer.FullName, ($installer.Length / 1MB))
