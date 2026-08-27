[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ArtifactDirectory,

    [Parameter(Mandatory)]
    [string] $ExpectedVersion,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $ExpectedCommit
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
$manifestPath = Join-Path $ArtifactDirectory 'release-artifacts.json'
$checksumPath = Join-Path $ArtifactDirectory 'SHA256SUMS.txt'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or
    $manifest.releaseVersion -cne $ExpectedVersion -or
    $manifest.sourceCommit -cne $ExpectedCommit.ToLowerInvariant()) {
    throw 'Release manifest identity does not match the requested release.'
}

$expectedNames = @("TigerMarkView-$ExpectedVersion-win-x64-setup.exe")
$entries = @($manifest.artifacts)
if ($entries.Count -ne 1 -or [string] $entries[0].name -cne $expectedNames[0]) {
    throw 'Release manifest does not contain the one expected installer.'
}

$allowedNames = @($expectedNames + @('release-artifacts.json', 'SHA256SUMS.txt'))
$actualNames = @(Get-ChildItem -LiteralPath $ArtifactDirectory -File | ForEach-Object Name)
$missing = @($allowedNames | Where-Object { $_ -cnotin $actualNames })
$unexpected = @($actualNames | Where-Object { $_ -cnotin $allowedNames })
if ($missing.Count -ne 0 -or $unexpected.Count -ne 0) {
    throw "Release directory mismatch. Missing: $($missing -join ', '); unexpected: $($unexpected -join ', ')."
}

foreach ($entry in $entries) {
    $path = Join-Path $ArtifactDirectory $entry.name
    $file = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne [long] $entry.length -or $hash -cne [string] $entry.sha256) {
        throw "Release artifact '$($entry.name)' does not match its recorded bytes."
    }
}

$expectedChecksums = @($entries | ForEach-Object { "$($_.sha256)  $($_.name)" }) -join [Environment]::NewLine
$actualChecksums = (Get-Content -LiteralPath $checksumPath -Raw).TrimEnd("`r", "`n")
if ($actualChecksums -cne $expectedChecksums) {
    throw 'SHA256SUMS.txt does not exactly match release-artifacts.json.'
}

Write-Host "Verified exact TigerMarkView $ExpectedVersion release bytes at $ExpectedCommit."
