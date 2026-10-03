#Requires -Version 7.0
<#
    .SYNOPSIS
    Keeps the installer's declarations aligned with their single sources.

    .DESCRIPTION
    installer\TigerSetup.toml repeats a few values TigerSetup cannot read from the build - the
    product links, the privacy statement's URL template and the WinGet descriptions - and names the extensions the Markdown handler is
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
# WinGet repository policy expects a product privacy statement; TigerSetup writes PrivacyUrl only when
# declared, and verbatim. The statement of a version is its own release's PRIVACY.md asset, so both
# declarations are version templates - $(Version) in Version.props, {version} in TigerSetup.toml, which
# states no version - and must agree for any version.
$privacyTemplate = & $expand ([string] $properties.PrivacyUrl)
Assert-True ($privacyTemplate -ceq "$repositoryUrl/releases/download/v`$(Version)/PRIVACY.md" -and
    (Test-Path -LiteralPath (Join-Path $repositoryRoot 'docs\PRIVACY.md') -PathType Leaf)) `
    "Version.props PrivacyUrl '$privacyTemplate' must be the version's own PRIVACY.md release asset, and docs\PRIVACY.md must exist."
Assert-True ($winget.ContainsKey('privacy_url')) 'TigerSetup.toml [winget] must declare privacy_url.'
foreach ($sampleVersion in [string] $properties.Version, '0.11.1', '1.0.0-rc.1') {
    Assert-True ($winget.privacy_url.Replace('{version}', $sampleVersion) -ceq $privacyTemplate.Replace('$(Version)', $sampleVersion)) `
        "TigerSetup.toml [winget] privacy_url '$($winget.privacy_url)' does not resolve to Version.props PrivacyUrl for $sampleVersion."
}
# The licence and the release notes of a version are first-party pages too, pinned to its tag.
Assert-True ($winget.license_url -ceq "$repositoryUrl/blob/v{version}/LICENSE" -and
    (Test-Path -LiteralPath (Join-Path $repositoryRoot 'LICENSE') -PathType Leaf)) `
    "TigerSetup.toml [winget] license_url '$($winget.license_url)' must be the LICENSE at the version's own tag."
Assert-True ($winget.release_notes_url -ceq "$repositoryUrl/releases/tag/v{version}") `
    "TigerSetup.toml [winget] release_notes_url '$($winget.release_notes_url)' must be the version's own release."
Assert-True (@($manifestLines | Where-Object { $_ -match '^\s*version\s*=' }).Count -eq 0) 'TigerSetup.toml must not state a version; [metadata] reads it from Version.props.'
# The statement ships twice from one checkout - installed as Docs\PRIVACY.md and published as the
# release's PRIVACY.md - so a checkout must reproduce the committed bytes exactly on every machine.
$privacyAttributes = (& git -C $repositoryRoot check-attr text eol -- docs/PRIVACY.md | Out-String)
Assert-True ($privacyAttributes -match 'text: set' -and $privacyAttributes -match 'eol: lf') `
    '.gitattributes must pin docs/PRIVACY.md to LF so every checkout produces the committed bytes.'
$privacyBytes = [IO.File]::ReadAllBytes((Join-Path $repositoryRoot 'docs\PRIVACY.md'))
Assert-True ($privacyBytes -notcontains [byte] 13 -and -not ($privacyBytes.Length -ge 3 -and $privacyBytes[0] -eq 0xEF)) `
    'docs\PRIVACY.md must be UTF-8 without a byte-order mark and with LF line endings only.'
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

# --- local data: removed by an explicit uninstall, kept by an upgrade ----------------------------

$action = Get-TomlSection -Lines $manifestLines -Section 'actions'
Assert-True (@($manifestLines | Where-Object { $_ -match '^\s*\[\[actions\]\]' }).Count -eq 1) 'TigerSetup.toml must declare exactly one custom action.'
Assert-True ($action.name -ceq 'remove-local-data' -and $action.phase -ceq 'post-uninstall' -and $action.kind -ceq 'cmd' -and
    $action.source -ceq 'actions/remove-local-data.cmd' -and $action.on_failure -ceq 'continue') `
    'The local-data removal must be the packaged cmd action remove-local-data, after an uninstall, reporting rather than rolling back a failure.'
Assert-True (@($manifestLines | Where-Object { $_ -match '^\s*run_on\s*=\s*\["uninstall"\]\s*(#.*)?$' }).Count -eq 1) `
    'The local-data removal must run on an uninstall only, never on an install, upgrade or repair.'

# The folders the action removes are the ones the application writes: settings and WebView2 profiles
# under the user's Local AppData, generated pages under the user's temporary folder.
$actionScript = Join-Path $repositoryRoot 'installer\actions\remove-local-data.cmd'
$actionText = Get-Content -LiteralPath $actionScript -Raw
$appSources = @(
    'src\TigerMarkView\Settings\SettingsStore.cs'
    'src\TigerMarkView\Hosting\WebViewProfile.cs'
    'src\TigerMarkView.Pdf\OffScreenWebViewHost.cs'
) | ForEach-Object { Get-Content -LiteralPath (Join-Path $repositoryRoot $_) -Raw }
foreach ($source in $appSources) {
    Assert-True ($source -match 'SpecialFolder\.LocalApplicationData\),\s*"TigerMarkView"') `
        'Every per-user data folder the application writes must be %LOCALAPPDATA%\TigerMarkView, the folder the uninstall removes.'
}
$tempSources = @(
    'src\TigerMarkView\Hosting\GeneratedPages.cs'
    'src\TigerMarkView.Pdf\OffScreenPdfHost.cs'
) | ForEach-Object { Get-Content -LiteralPath (Join-Path $repositoryRoot $_) -Raw }
foreach ($source in $tempSources) {
    Assert-True ($source -match 'Path\.GetTempPath\(\),\s*"TigerMarkView"') `
        'Every generated page must live under %TEMP%\TigerMarkView, the folder the uninstall removes.'
}
foreach ($window in 'MainWindow', 'HelpWindow') {
    $source = Get-Content -LiteralPath (Join-Path $repositoryRoot "src\TigerMarkView\$window.axaml.cs") -Raw
    Assert-True ($source -match 'GeneratedPages\.ForThisProcess\(' -and $source -notmatch 'GetTempPath') `
        "$window must name its page through GeneratedPages, under %TEMP%\TigerMarkView."
}
Assert-True ($actionText.Contains('set "data=%LOCALAPPDATA%\TigerMarkView"') -and $actionText.Contains('set "pages=%TEMP%\TigerMarkView"')) `
    'remove-local-data.cmd must remove exactly %LOCALAPPDATA%\TigerMarkView and %TEMP%\TigerMarkView.'
Assert-True ([IO.File]::ReadAllText($actionScript) -notmatch "(?<!`r)`n") 'remove-local-data.cmd must have CRLF line endings, which cmd.exe needs for its labels.'
Write-Host 'PASS: an uninstall-only action removes exactly the folders the application writes'

# The script itself, against redirected profile folders: what it removes, what it leaves alone, and
# that a link inside the data is removed without being followed.
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('TigerMarkView-remove-local-data-' + [Guid]::NewGuid().ToString('N'))
try {
    $localAppData = Join-Path $sandbox 'Local'
    $temp = Join-Path $sandbox 'Temp'
    $outside = Join-Path $sandbox 'Outside'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $localAppData 'TigerMarkView\WebView2\Viewer'),
        (Join-Path $temp 'TigerMarkView\pdf'), (Join-Path $localAppData 'Other'), $outside
    Set-Content -LiteralPath (Join-Path $localAppData 'TigerMarkView\settings.json') -Value '{ "recentFiles": [ "C:\\docs\\a.md" ] }'
    Set-Content -LiteralPath (Join-Path $temp 'TigerMarkView\preview.html') -Value '<p>a document</p>'
    Set-Content -LiteralPath (Join-Path $localAppData 'Other\keep.txt') -Value 'another application'
    Set-Content -LiteralPath (Join-Path $outside 'keep.txt') -Value 'reached only through a link'
    $null = New-Item -ItemType Junction -Path (Join-Path $localAppData 'TigerMarkView\link') -Target $outside

    function Invoke-RemoveLocalData([string] $LocalAppDataValue) {
        $start = [Diagnostics.ProcessStartInfo]::new('cmd.exe')
        foreach ($argument in '/d', '/s', '/c', $actionScript) { $start.ArgumentList.Add($argument) }
        $start.UseShellExecute = $false
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        if ($LocalAppDataValue) { $start.Environment['LOCALAPPDATA'] = $LocalAppDataValue } else { $null = $start.Environment.Remove('LOCALAPPDATA') }
        $start.Environment['TEMP'] = $temp
        $process = [Diagnostics.Process]::Start($start)
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        [pscustomobject]@{ exitCode = $process.ExitCode; output = $output.Trim() }
    }

    $removed = Invoke-RemoveLocalData $localAppData
    Assert-True ($removed.exitCode -eq 0) "remove-local-data.cmd exited $($removed.exitCode): $($removed.output)"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $localAppData 'TigerMarkView')) -and
        -not (Test-Path -LiteralPath (Join-Path $temp 'TigerMarkView'))) 'The settings, profiles and generated pages are removed.'
    Assert-True ((Test-Path -LiteralPath (Join-Path $localAppData 'Other\keep.txt')) -and (Test-Path -LiteralPath (Join-Path $outside 'keep.txt'))) `
        'Nothing outside the two folders is touched, including what a link inside them points to.'
    Assert-True ((Invoke-RemoveLocalData $localAppData).exitCode -eq 0) 'Removing data that is already gone succeeds: the action is safe to run again.'
    Assert-True ((Invoke-RemoveLocalData '').exitCode -eq 2) 'Without a profile folder to name, the action removes nothing and says so.'

    $null = New-Item -ItemType Directory -Force -Path (Join-Path $localAppData 'TigerMarkView')
    $held = [IO.File]::Open((Join-Path $localAppData 'TigerMarkView\held.txt'), 'Create', 'ReadWrite', 'None')
    try { $blocked = Invoke-RemoveLocalData $localAppData }
    finally { $held.Dispose() }
    Assert-True ($blocked.exitCode -eq 1 -and $blocked.output -match 'Could not remove') `
        'A file something still holds is reported as a failure, never as removed.'
    Write-Host 'PASS: remove-local-data.cmd removes the application''s data and nothing else'
}
finally {
    [IO.Directory]::Delete($sandbox, $true)
}

# --- the Inno Setup migration row's source -------------------------------------------------------
# The v0.8.x release assets were withdrawn on purpose. The lab's migration row must never fetch one:
# it uses a retained copy of the published bytes, refused unless it hashes to the recorded digest.
$releaseLab = Get-Content -LiteralPath (Join-Path $repositoryRoot 'eng\lab\Test-TigerMarkViewRelease.ps1') -Raw
Assert-True ($releaseLab -notmatch '(?i)Invoke-RestMethod|Invoke-WebRequest\s+-Uri\s+\$asset|browser_download_url|api\.github\.com') `
    'The migration row must not download a published installer from GitHub.'
Assert-True ($releaseLab -match "'0\.8\.1'\s*=\s*'B81118C96655A7E6E28642A22AE5FC14CBD4EF47F2FA5928A35408833EE4BE9F'") `
    'The migration row must pin the SHA-256 the published 0.8.1 installer had.'
Assert-True ($releaseLab -match '(?s)\$legacyHash -cne \$publishedInnoInstallers\[\$UpgradeFromVersion\].{0,80}throw') `
    'The migration row must refuse a copy that is not the published bytes.'
Write-Host 'PASS: the migration row uses the retained published 0.8.1 installer, verified by its recorded SHA-256'
