#Requires -Version 7.0
<#
    .SYNOPSIS
    Closes the release artifact set: exactly one installer, its recorded hashes,
    and the manifest that names the commit they were built from.

    .DESCRIPTION
    With -InstallerPath the artifact directory is created and populated here, so
    the release workflow needs no staging or copying step of its own: the
    directory this writes holds the installer, SHA256SUMS.txt, and
    release-artifacts.json and nothing else.

    .PARAMETER ArtifactDirectory
    The closed release directory to write.

    .PARAMETER Version
    The release version.

    .PARAMETER CommitSha
    The commit the artifacts were built from.

    .PARAMETER InstallerPath
    The installer to place in the artifact directory. When omitted, the installer
    is expected to be there already.

    .PARAMETER GitHubOutput
    When supplied, a GITHUB_OUTPUT file to append 'manifest_sha256' to - the
    transfer check the publication job repeats after downloading the artifact.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ArtifactDirectory,

    [Parameter(Mandatory)]
    [string] $Version,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $CommitSha,

    [string] $InstallerPath,

    [string] $GitHubOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Invalid release version '$Version'."
}

$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
$installerName = "TigerMarkView-$Version-win-x64-setup.exe"
if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
    if ([IO.Path]::GetFileName($InstallerPath) -cne $installerName) {
        throw "The release installer must be named '$installerName'."
    }
    if (Test-Path -LiteralPath $ArtifactDirectory) {
        Remove-Item -LiteralPath $ArtifactDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $ArtifactDirectory -Force | Out-Null
    Copy-Item -LiteralPath $InstallerPath -Destination (Join-Path $ArtifactDirectory $installerName)
}
$expectedNames = @($installerName)
$actualNames = @(Get-ChildItem -LiteralPath $ArtifactDirectory -File | ForEach-Object Name)
$missing = @($expectedNames | Where-Object { $_ -cnotin $actualNames })
$unexpected = @($actualNames | Where-Object { $_ -cnotin $expectedNames })
if ($missing.Count -ne 0 -or $unexpected.Count -ne 0) {
    throw "Release payload mismatch. Missing: $($missing -join ', '); unexpected: $($unexpected -join ', ')."
}

$artifacts = @(
    foreach ($name in $expectedNames) {
        $path = Join-Path $ArtifactDirectory $name
        $file = Get-Item -LiteralPath $path
        [ordered]@{
            name = $name
            kind = 'WindowsInstaller'
            length = $file.Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
)

$manifestPath = Join-Path $ArtifactDirectory 'release-artifacts.json'
$checksumPath = Join-Path $ArtifactDirectory 'SHA256SUMS.txt'
[ordered]@{
    schemaVersion = 1
    releaseVersion = $Version
    sourceCommit = $CommitSha.ToLowerInvariant()
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    artifacts = $artifacts
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

@($artifacts | ForEach-Object { "$($_.sha256)  $($_.name)" }) |
    Set-Content -LiteralPath $checksumPath -Encoding utf8NoBOM
Write-Host "Recorded the closed TigerMarkView $Version release artifact set."

$manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "release-artifacts.json SHA-256: $manifestSha256"
if (-not [string]::IsNullOrWhiteSpace($GitHubOutput)) {
    "manifest_sha256=$manifestSha256" | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
}
