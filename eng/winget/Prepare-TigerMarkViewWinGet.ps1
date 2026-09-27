#Requires -Version 7.0
<#
    .SYNOPSIS
    Generates a TigerMarkView WinGet submission set from a local installer.

    .DESCRIPTION
    This is the only thing in the repository that produces a manifest, and it serves
    two roles that must not be confused:

      - locally, before a release exists, to see and review what the manifests will
        say; and
      - inside the release workflow, over the installer that workflow just built,
        producing the set the workflow then seals and uploads as
        TigerMarkView-WinGet-<version>-<commit>.

    Only the second produces the authoritative post-release submission. A set
    generated locally hashes a locally built installer, and a rebuild is never
    byte-identical to the one CI built (the installer embeds build times and the
    dependency hints current when it was built), so its InstallerSha256 will not be
    the published one. Test-TigerMarkViewWinGet.ps1 reads the sealed workflow
    artifact and never the output of this script.

    The manifests themselves are TigerSetup's: `tiger-setup winget prepare` writes
    them from installer\TigerSetup.toml and the installer's bytes, and
    `tiger-setup winget finalize` fills in the immutable release URL and the hash.
    This script pins the inputs - the builder installer\tigersetup.json names, the
    version, the file name, the URL - and proves the result is exactly the three
    submission manifests.

    Output goes to artifacts\winget\manifests\i\ItTiger\TigerMarkView\<version>\ by
    default; the post-release submission lives elsewhere, under
    artifacts\winget-release\<version>\submission\.

    .PARAMETER InstallerPath
    The installer to hash. Defaults to artifacts\installer\<installer file name>.

    .PARAMETER OutputRoot
    The root the manifests\... path is created under. Defaults to artifacts\winget.

    .PARAMETER ExpectedVersion
    When supplied, the version Version.props must already be at.

    .PARAMETER Version
    A local candidate's version, when the installer was built with
    Build-Installer.ps1 -Version. Defaults to Version.props.

    .PARAMETER InstallerUrl
    The immutable release asset URL. Defaults to, and must equal, the v<version> URL.

    .PARAMETER ExpectedInstallerSha256
    When supplied, the digest the installer must hash to.

    .PARAMETER TigerSetupPath
    tiger-setup.exe; defaults to the one on PATH. Must be the pinned version.

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
    [string] $Version,
    [string] $InstallerUrl,
    [string] $ExpectedInstallerSha256,
    [string] $TigerSetupPath,
    [string] $WinGetPath,
    [switch] $Validate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'TigerMarkViewWinGet.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'installer' 'TigerSetupBuilder.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$properties = Get-TigerMarkViewWinGetVersionProperty -RepositoryRoot $repoRoot
$configuredVersion = [string] $properties.Version
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and $configuredVersion -cne $ExpectedVersion) {
    throw "Version.props '$configuredVersion' does not match expected version '$ExpectedVersion'."
}
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $configuredVersion }

$release = Get-TigerMarkViewWinGetRelease -Version $Version -RepositoryUrl ([string] $properties.RepositoryUrl)
$packageIdentifier = $release.packageIdentifier
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

$tigerSetup = Resolve-TigerMarkViewTigerSetup -RepositoryRoot $repoRoot -Path $TigerSetupPath

if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'artifacts\winget' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$manifestDirectory = Get-TigerMarkViewWinGetManifestDirectory -OutputRoot $OutputRoot -Version $Version
if (Test-Path -LiteralPath $manifestDirectory) {
    $safeRoot = $OutputRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath($manifestDirectory)
    if (-not $resolved.StartsWith($safeRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace manifests outside '$OutputRoot'."
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null

$manifest = Join-Path $repoRoot 'installer\TigerSetup.toml'
& $tigerSetup winget prepare $manifest --installer $InstallerPath --output $manifestDirectory | Out-Host
if ($LASTEXITCODE -ne 0) { throw "tiger-setup winget prepare failed with exit code $LASTEXITCODE." }
& $tigerSetup winget finalize $manifestDirectory --url $InstallerUrl --installer $InstallerPath | Out-Host
if ($LASTEXITCODE -ne 0) { throw "tiger-setup winget finalize failed with exit code $LASTEXITCODE." }

# Reading the set back is the shape gate: exactly the three submission manifests, no
# extra file, and no byte-order mark. What is on disk from here on is the submission.
$submission = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $manifestDirectory -Version $Version
foreach ($part in @($submission.installer, $submission.locale, $submission.version)) {
    if ($part.packageIdentifier -cne $packageIdentifier -or $part.packageVersion -cne $Version) {
        throw "The generated manifests do not all declare $packageIdentifier $Version."
    }
}
if ($submission.installer.installerUrl -cne $InstallerUrl -or
    $submission.installer.installerSha256 -cne $installerHash) {
    throw 'The generated installer manifest does not declare the release URL and this installer''s hash.'
}

if ($Validate) {
    $null = Invoke-TigerMarkViewWinGetValidation -ManifestDirectory $manifestDirectory -WinGetPath $WinGetPath
}

Write-Host "PASS: prepared $packageIdentifier $Version manifests at '$manifestDirectory'." -ForegroundColor Green
Write-Host "Submission digest: $($submission.digest)"
Write-Host ('This is a locally generated set. The authoritative post-release submission is the ' +
    "release workflow's TigerMarkView-WinGet-$Version-<commit> artifact.") -ForegroundColor DarkGray
Write-Output $manifestDirectory
