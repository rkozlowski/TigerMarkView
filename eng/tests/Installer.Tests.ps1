#Requires -Version 7.0
<#
    .SYNOPSIS
    Keeps the installer's declarations aligned with their single sources.

    .DESCRIPTION
    installer\TigerSetup.toml repeats a few values TigerSetup cannot read from the build - the
    product links and the WinGet descriptions - and names the extensions the Markdown handler is
    registered for. Version.props owns the first, Core's MarkdownLinkResolver the second; this suite
    fails when either drifts. It also checks the builder pin and that the release workflow provisions
    exactly that builder. It needs no TigerSetup, so it runs in normal CI.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repositoryRoot 'installer' 'TigerSetupBuilder.ps1')

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Get-TomlSection {
    <# The simple `key = "value"` lines of one [section] of TigerSetup.toml. #>
    param([string[]] $Lines, [string] $Section)

    $values = @{}
    $inside = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*\[+(?<name>[^\]]+)\]+\s*(#.*)?$') { $inside = $Matches.name -ceq $Section; continue }
        if ($inside -and $line -match '^\s*(?<key>[A-Za-z_]+)\s*=\s*"(?<value>[^"]*)"') { $values[$Matches.key] = $Matches.value }
    }
    $values
}

[xml] $versionProps = Get-Content -LiteralPath (Join-Path $repositoryRoot 'Version.props') -Raw
$properties = $versionProps.Project.PropertyGroup
$repositoryUrl = [string] $properties.RepositoryUrl
$expand = { param([string] $value) $value.Replace('$(RepositoryUrl)', $repositoryUrl) }

$manifestLines = Get-Content -LiteralPath (Join-Path $repositoryRoot 'installer\TigerSetup.toml')
$package = Get-TomlSection -Lines $manifestLines -Section 'package'
$winget = Get-TomlSection -Lines $manifestLines -Section 'winget'

Assert-True ($package.name -ceq [string] $properties.Product) "TigerSetup.toml name '$($package.name)' is not Version.props Product."
Assert-True ($package.publisher -ceq [string] $properties.Company) "TigerSetup.toml publisher '$($package.publisher)' is not Version.props Company."
Assert-True ($package.license -ceq [string] $properties.LicenseIdentity) "TigerSetup.toml license '$($package.license)' is not Version.props LicenseIdentity."
Assert-True ($package.website -ceq [string] $properties.WebsiteUrl) 'TigerSetup.toml website is not Version.props WebsiteUrl.'
Assert-True ($package.support -ceq (& $expand ([string] $properties.IssueTrackerUrl))) 'TigerSetup.toml support is not Version.props IssueTrackerUrl.'
Assert-True ($package.help -ceq (& $expand ([string] $properties.DocumentationUrl))) 'TigerSetup.toml help is not Version.props DocumentationUrl.'
Assert-True ($winget.package_url -ceq $repositoryUrl) 'TigerSetup.toml [winget] package_url is not Version.props RepositoryUrl.'
Assert-True ($winget.publisher_url -ceq [string] $properties.WebsiteUrl) 'TigerSetup.toml [winget] publisher_url is not Version.props WebsiteUrl.'
Assert-True ($winget.publisher_support_url -ceq (& $expand ([string] $properties.IssueTrackerUrl))) 'TigerSetup.toml [winget] publisher_support_url is not Version.props IssueTrackerUrl.'
Assert-True ($winget.short_description -ceq [string] $properties.Description) 'TigerSetup.toml [winget] short_description is not Version.props Description.'
Assert-True (@($manifestLines | Where-Object { $_ -match '^\s*version\s*=' }).Count -eq 0) 'TigerSetup.toml must not state a version; [metadata] reads it from Version.props.'
Write-Host 'PASS: TigerSetup.toml repeats Version.props exactly and states no version'

$resolverSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'src\TigerMarkView.Core\Navigation\MarkdownLinkResolver.cs') -Raw
Assert-True ($resolverSource -match 'MarkdownExtensions\s*=\s*\[(?<list>[^\]]*)\]') 'MarkdownLinkResolver.MarkdownExtensions was not found.'
$viewerExtensions = @([regex]::Matches($Matches.list, '"(?<extension>[^"]+)"') | ForEach-Object { $_.Groups['extension'].Value })
$associationLine = @($manifestLines | Where-Object { $_ -match '^\s*extensions\s*=' })
Assert-True ($associationLine.Count -eq 1) 'TigerSetup.toml must declare exactly one extensions list.'
$registeredExtensions = @([regex]::Matches($associationLine[0], '"(?<extension>[^"]+)"') | ForEach-Object { $_.Groups['extension'].Value })
Assert-True (($registeredExtensions -join ',') -ceq ($viewerExtensions -join ',')) `
    "The Markdown handler is registered for '$($registeredExtensions -join ',')'; the viewer opens '$($viewerExtensions -join ',')'."
Write-Host 'PASS: the Markdown handler is registered for exactly the extensions the viewer opens'

$pin = Get-TigerMarkViewTigerSetupPin -RepositoryRoot $repositoryRoot
Write-Host "PASS: installer\tigersetup.json pins TigerSetup $($pin.version) by URL and SHA-256"

$workflow = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github\workflows\release.yml') -Raw
Assert-True ($workflow -notmatch '(?i)inno|ISCC|Install-WinGet') 'The release workflow must not provision Inno Setup or WinGet.'
Assert-True ($workflow.Contains('./eng/release-automation/Install-TigerSetup.ps1')) 'The release workflow must provision the pinned TigerSetup builder.'
foreach ($script in 'Build-Installer.ps1', 'Assert-Installer.ps1', 'Prepare-TigerMarkViewWinGet.ps1') {
    Assert-True ($workflow -match "(?s)$([regex]::Escape($script)).{0,400}?-TigerSetupPath \`$env:TIGER_SETUP") `
        "The release workflow must hand $script the provisioned builder."
}
Assert-True ($workflow -match '(?m)^\s+TIGER_SETUP: \$\{\{ steps\.tigersetup\.outputs\.path \}\}\r?$') `
    'The builder path must reach the scripts through an environment variable.'
Write-Host 'PASS: the release workflow builds with exactly the pinned TigerSetup builder'
