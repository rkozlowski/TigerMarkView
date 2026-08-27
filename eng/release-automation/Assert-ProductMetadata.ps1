[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PublishDirectory,

    [string] $ExpectedVersion
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$versionPropsPath = Join-Path $repoRoot 'Version.props'
[xml] $versionProps = Get-Content -LiteralPath $versionPropsPath -Raw
$properties = $versionProps.Project.PropertyGroup
if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) {
    $ExpectedVersion = [string] $properties.Version
}
if ($ExpectedVersion -cne [string] $properties.Version) {
    throw "Expected version '$ExpectedVersion' does not match Version.props '$($properties.Version)'."
}

$productionProjects = @(
    'src\TigerMarkView\TigerMarkView.csproj'
    'src\TigerMarkView.Core\TigerMarkView.Core.csproj'
    'src\TigerMarkView.Pdf\TigerMarkView.Pdf.csproj'
    'src\TigerMarkView.Cli\TigerMarkView.Cli.csproj'
)
foreach ($relativePath in $productionProjects) {
    [xml] $project = Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) -Raw
    $imports = @($project.Project.Import | Where-Object { $_.Project -ceq '..\..\Version.props' })
    if ($imports.Count -ne 1) {
        throw "'$relativePath' must import the root Version.props exactly once."
    }
}

[xml] $directoryProps = Get-Content -LiteralPath (Join-Path $repoRoot 'Directory.Build.props') -Raw
foreach ($propertyName in @('Version', 'AssemblyVersion', 'FileVersion', 'InformationalVersion', 'Company', 'Product')) {
    if ($null -ne $directoryProps.SelectSingleNode("/Project/PropertyGroup/$propertyName")) {
        throw "Directory.Build.props must not define product metadata '$propertyName'."
    }
}

$expectedFileVersion = ([string] $properties.FileVersion).Replace('$(Version)', $ExpectedVersion)

$PublishDirectory = [IO.Path]::GetFullPath($PublishDirectory)
$expectedFiles = @(
    'TigerMarkView.exe'
    'tiger-mark.exe'
    'TigerMarkView.Core.dll'
    'TigerMarkView.Pdf.dll'
)
foreach ($name in $expectedFiles) {
    $path = Join-Path $PublishDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Shipped binary is missing: $path"
    }

    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($path)
    $shortProductVersion = ([string] $info.ProductVersion).Split('+')[0]
    if ($shortProductVersion -cne $ExpectedVersion) {
        throw "'$name' ProductVersion '$($info.ProductVersion)' does not match '$ExpectedVersion'."
    }
    if ([string] $info.FileVersion -cne $expectedFileVersion) {
        throw "'$name' FileVersion '$($info.FileVersion)' does not match '$expectedFileVersion'."
    }
    if ([string] $info.CompanyName -cne [string] $properties.Company -or
        [string] $info.ProductName -cne [string] $properties.Product -or
        [string] $info.LegalCopyright -cne [string] $properties.Copyright) {
        throw "'$name' does not carry the canonical product/company/copyright metadata."
    }
}

$cli = Join-Path $PublishDirectory 'tiger-mark.exe'
$versionOutput = & $cli --version | Out-String
if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch [regex]::Escape($ExpectedVersion)) {
    throw 'tiger-mark --version did not report the canonical version.'
}
$helpOutput = & $cli --help | Out-String
$repositoryUrl = [string] $properties.RepositoryUrl
$documentationUrl = ([string] $properties.DocumentationUrl).Replace('$(RepositoryUrl)', $repositoryUrl)
foreach ($link in @($repositoryUrl, $documentationUrl)) {
    if (-not $helpOutput.Contains($link, [StringComparison]::Ordinal)) {
        throw "TigerCli-generated help does not surface canonical link '$link'."
    }
}

Write-Host "Validated canonical metadata and TigerCli output for TigerMarkView $ExpectedVersion."
