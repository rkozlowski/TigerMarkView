<#
.SYNOPSIS
    Publishes TigerMarkView for Release win-x64 and compiles the Inno Setup installer.

.DESCRIPTION
    One repeatable command, no IDE steps:

        pwsh installer\Build-Installer.ps1

    Produces artifacts\installer\TigerMarkView-<version>-win-x64-setup.exe, where <version> comes
    from Directory.Build.props by way of the published executable's version resource. This script
    never states a version of its own; it reads the one the SDK stamped and then checks that the
    installer Inno Setup produced carries the same one.

.PARAMETER SkipPublish
    Compile the installer from the existing artifacts\publish\win-x64 folder without republishing.

.PARAMETER InnoSetupPath
    Full path to ISCC.exe, when it is somewhere this script would not look.
#>
[CmdletBinding()]
param(
    [string] $Configuration = 'Release',
    [switch] $SkipPublish,
    [string] $InnoSetupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$AppProject = Join-Path $RepoRoot 'src\TigerMarkView\TigerMarkView.csproj'
$IssScript  = Join-Path $PSScriptRoot 'TigerMarkView.iss'
$PublishDir = Join-Path $RepoRoot 'artifacts\publish\win-x64'
$OutputDir  = Join-Path $RepoRoot 'artifacts\installer'
$AppExe     = Join-Path $PublishDir 'TigerMarkView.exe'

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
    Write-Host "== Publishing $Configuration win-x64 ==" -ForegroundColor Cyan
    # A stale file left in the publish folder would be packaged as though it belonged there.
    if (Test-Path -LiteralPath $PublishDir) {
        Remove-Item -LiteralPath $PublishDir -Recurse -Force
    }

    # Framework-dependent on purpose: neither the .NET runtime nor WebView2 is bundled.
    dotnet publish $AppProject `
        --configuration $Configuration `
        --runtime win-x64 `
        --self-contained false `
        --output $PublishDir
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE." }
}

Write-Host '== Version ==' -ForegroundColor Cyan
# Directory.Build.props -> AssemblyInformationalVersion -> ProductVersion. The '+<sha>' build
# metadata the SDK appends is stripped here exactly as Core.About.ApplicationVersion.Format
# strips it for the About dialog, so this is the version the running application reports.
$productVersion = (Get-Item -LiteralPath $AppExe).VersionInfo.ProductVersion
if (-not $productVersion) { throw "Could not read ProductVersion from '$AppExe'." }
$version = $productVersion.Split('+')[0]
Write-Host "  $version  (from $productVersion)"

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
