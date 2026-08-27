[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ArtifactDirectory,

    [Parameter(Mandatory)]
    [string] $Version,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $CommitSha
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Invalid release version '$Version'."
}

$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
$installerName = "TigerMarkView-$Version-win-x64-setup.exe"
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
