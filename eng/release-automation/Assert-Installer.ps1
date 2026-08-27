[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $InstallerPath,

    [Parameter(Mandatory)]
    [string] $ExpectedVersion,

    [switch] $ValidateBehavior
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-PathEntrySnapshot {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ($null -eq $Value) { return }

    $segments = $Value.Split([char[]] @(';'), [StringSplitOptions]::None)
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $normalized = $segments[$index].Trim()
        while ($normalized.Length -gt 3 -and
            ($normalized.EndsWith('\', [StringComparison]::Ordinal) -or
             $normalized.EndsWith('/', [StringComparison]::Ordinal))) {
            $normalized = $normalized.Substring(0, $normalized.Length - 1)
        }

        [pscustomobject] @{
            Index      = $index
            Raw        = $segments[$index]
            Normalized = $normalized
        }
    }
}

function Get-EquivalentPathEntries {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Entries,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Expected
    )

    $expectedEntry = @(Get-PathEntrySnapshot -Value $Expected)[0]
    @($Entries | Where-Object {
        [StringComparer]::OrdinalIgnoreCase.Equals($_.Normalized, $expectedEntry.Normalized)
    })
}

function Get-NormalizedPathDifferences {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Before,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $After
    )

    # Match entries one by one so duplicate and empty segments keep their multiplicity. The
    # original arrays are never reordered or deduplicated.
    $unmatchedAfter = [Collections.Generic.List[object]]::new()
    foreach ($entry in $After) { $unmatchedAfter.Add($entry) }

    $missing = [Collections.Generic.List[object]]::new()
    foreach ($expected in $Before) {
        $matchIndex = -1
        for ($index = 0; $index -lt $unmatchedAfter.Count; $index++) {
            if ([StringComparer]::OrdinalIgnoreCase.Equals(
                    $expected.Normalized, $unmatchedAfter[$index].Normalized)) {
                $matchIndex = $index
                break
            }
        }

        if ($matchIndex -ge 0) {
            $unmatchedAfter.RemoveAt($matchIndex)
        }
        else {
            $missing.Add($expected)
        }
    }

    [pscustomobject] @{
        Missing = [object[]] $missing.ToArray()
        Added   = [object[]] $unmatchedAfter.ToArray()
    }
}

function Format-NormalizedPathDifferences {
    param(
        [Parameter(Mandatory)]
        [object] $Differences
    )

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('Normalized PATH entry differences:')
    foreach ($entry in $Differences.Missing) {
        $value = if ($entry.Normalized.Length -eq 0) { '<empty>' } else { $entry.Normalized }
        $lines.Add("  removed at original index $($entry.Index): '$value'")
    }
    foreach ($entry in $Differences.Added) {
        $value = if ($entry.Normalized.Length -eq 0) { '<empty>' } else { $entry.Normalized }
        $lines.Add("  added at resulting index $($entry.Index): '$value'")
    }
    $lines -join [Environment]::NewLine
}

function Assert-PathEntriesPreserved {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Before,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $After,

        [Parameter(Mandatory)]
        [string] $Context
    )

    $differences = Get-NormalizedPathDifferences -Before $Before -After $After
    if ($differences.Missing.Count -gt 0) {
        $details = Format-NormalizedPathDifferences -Differences $differences
        throw "$Context removed or meaningfully changed pre-existing PATH entries.$([Environment]::NewLine)$details"
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
[xml] $versionProps = Get-Content -LiteralPath (Join-Path $repoRoot 'Version.props') -Raw
$properties = $versionProps.Project.PropertyGroup
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
$expectedName = "TigerMarkView-$ExpectedVersion-win-x64-setup.exe"
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw "Installer not found: $InstallerPath"
}
if ([IO.Path]::GetFileName($InstallerPath) -cne $expectedName) {
    throw "Expected installer '$expectedName'; found '$([IO.Path]::GetFileName($InstallerPath))'."
}

$info = [Diagnostics.FileVersionInfo]::GetVersionInfo($InstallerPath)
if (([string] $info.FileVersion).Trim() -cne $ExpectedVersion -or
    ([string] $info.CompanyName).Trim() -cne ([string] $properties.Company).Trim() -or
    ([string] $info.LegalCopyright).Trim() -cne ([string] $properties.Copyright).Trim()) {
    throw 'Installer version/company/copyright metadata does not match Version.props.'
}

$source = Get-Content -LiteralPath (Join-Path $repoRoot 'installer\TigerMarkView.iss') -Raw
foreach ($contract in @(
    '(?m)^AppVersion=\{#AppVersion\}\r?$'
    '(?m)^PrivilegesRequired=lowest\r?$'
    '(?m)^PrivilegesRequiredOverridesAllowed=commandline dialog\r?$'
    '(?m)^OutputBaseFilename=\{#AppName\}-\{#AppVersion\}-win-x64-setup\r?$'
    '(?ms)^Name: "addtopath";.*?Flags: checkedonce\r?$'
    '(?m)^ChangesEnvironment=yes\r?$'
)) {
    if ($source -notmatch $contract) {
        throw "TigerMarkView.iss does not satisfy release contract '$contract'."
    }
}

Write-Host "Validated installer identity and source contract for $expectedName."
if (-not $ValidateBehavior) { return }
if (-not $IsWindows) { throw 'Installer behavior validation requires Windows.' }

$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}_is1'
if (Test-Path -LiteralPath $uninstallKey) {
    throw "Refusing to disturb a pre-existing TigerMarkView installation at '$uninstallKey'."
}

$temporaryRoot = if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    [IO.Path]::GetTempPath()
}
else {
    $env:RUNNER_TEMP
}
$validationRoot = Join-Path $temporaryRoot ('TigerMarkView-installer-' + [Guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $validationRoot 'app'
$pathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathBeforeEntries = @(Get-PathEntrySnapshot -Value $pathBefore)
$normalizedInstallRoot = $installRoot.TrimEnd('\', '/')
$preExistingMatches = @(Get-EquivalentPathEntries -Entries $pathBeforeEntries -Expected $normalizedInstallRoot)
if ($preExistingMatches.Count -ne 0) {
    throw "The unique validation install root unexpectedly already exists in the per-user PATH."
}
$ownershipKey = "HKCU:\Software\$($properties.Company)\$($properties.Product)\Installer"
$ownedPathEntry = $null
$installed = $false
try {
    $arguments = @(
        '/VERYSILENT'
        '/SUPPRESSMSGBOXES'
        '/NORESTART'
        '/SP-'
        '/CURRENTUSER'
        "/DIR=$installRoot"
        '/TASKS="addtopath"'
    )
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Silent per-user install failed with $($process.ExitCode)." }
    $installed = $true

    foreach ($relativePath in @(
        'TigerMarkView.exe'
        'tiger-mark.exe'
        'Docs\HELP.md'
        'Docs\LICENSE.txt'
        'Docs\THIRD-PARTY-NOTICES.md'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot $relativePath) -PathType Leaf)) {
            throw "Installed product is missing '$relativePath'."
        }
    }

    $appInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $installRoot 'TigerMarkView.exe'))
    $cliInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $installRoot 'tiger-mark.exe'))
    foreach ($binaryInfo in @($appInfo, $cliInfo)) {
        if (([string] $binaryInfo.ProductVersion).Split('+')[0] -cne $ExpectedVersion) {
            throw 'An installed executable reports the wrong product version.'
        }
    }

    $versionOutput = & (Join-Path $installRoot 'tiger-mark.exe') --version | Out-String
    if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch [regex]::Escape($ExpectedVersion)) {
        throw 'The installed tiger-mark command reports the wrong version.'
    }

    $pathAfterInstallEntries = @(Get-PathEntrySnapshot -Value (
        [Environment]::GetEnvironmentVariable('Path', 'User')))
    $pathMatches = @(Get-EquivalentPathEntries `
        -Entries $pathAfterInstallEntries `
        -Expected $normalizedInstallRoot)
    if ($pathMatches.Count -ne 1) {
        $differences = Get-NormalizedPathDifferences -Before $pathBeforeEntries -After $pathAfterInstallEntries
        $details = Format-NormalizedPathDifferences -Differences $differences
        throw "Expected one owned per-user PATH entry for '$installRoot'; found $($pathMatches.Count).$([Environment]::NewLine)$details"
    }
    Assert-PathEntriesPreserved `
        -Before $pathBeforeEntries `
        -After $pathAfterInstallEntries `
        -Context 'Install'

    $ownership = Get-ItemProperty -LiteralPath $ownershipKey -ErrorAction SilentlyContinue
    $ownedProperty = if ($null -eq $ownership) { $null } else { $ownership.PSObject.Properties['OwnedPathEntry'] }
    if ($null -eq $ownedProperty) { throw 'Installer did not record ownership of its PATH entry.' }
    $ownedPathEntry = [string] $ownedProperty.Value
    $ownedMarkerMatches = @(Get-EquivalentPathEntries -Entries $pathMatches -Expected $ownedPathEntry)
    if ($ownedMarkerMatches.Count -ne 1) {
        throw 'Installer ownership marker does not identify its PATH entry.'
    }

    $reinstall = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
    if ($reinstall.ExitCode -ne 0) { throw "Silent per-user reinstall failed with $($reinstall.ExitCode)." }
    $pathAfterReinstallEntries = @(Get-PathEntrySnapshot -Value (
        [Environment]::GetEnvironmentVariable('Path', 'User')))
    $pathMatches = @(Get-EquivalentPathEntries `
        -Entries $pathAfterReinstallEntries `
        -Expected $ownedPathEntry)
    if ($pathMatches.Count -ne 1) {
        $differences = Get-NormalizedPathDifferences -Before $pathBeforeEntries -After $pathAfterReinstallEntries
        $details = Format-NormalizedPathDifferences -Differences $differences
        throw "Per-user reinstall created $($pathMatches.Count) equivalent PATH entries.$([Environment]::NewLine)$details"
    }
    Assert-PathEntriesPreserved `
        -Before $pathBeforeEntries `
        -After $pathAfterReinstallEntries `
        -Context 'Reinstall'

    $arp = Get-ItemProperty -LiteralPath $uninstallKey
    if ($arp.DisplayVersion -cne $ExpectedVersion -or $arp.Publisher -cne [string] $properties.Company) {
        throw 'The per-user Add/Remove Programs entry has incorrect version or publisher metadata.'
    }
}
finally {
    if ($installed -and (Test-Path -LiteralPath $uninstallKey)) {
        $uninstaller = Join-Path $installRoot 'unins000.exe'
        if (Test-Path -LiteralPath $uninstaller -PathType Leaf) {
            $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @(
                '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
            ) -Wait -PassThru
            if ($uninstall.ExitCode -ne 0) {
                throw "Silent uninstall failed with $($uninstall.ExitCode)."
            }
        }
    }
}

if (Test-Path -LiteralPath $installRoot) { throw "Installation directory remains: $installRoot" }
if (Test-Path -LiteralPath $uninstallKey) { throw 'Per-user uninstall registration remains.' }
$pathAfter = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathAfterEntries = @(Get-PathEntrySnapshot -Value $pathAfter)
$ownedMatchesAfter = @(Get-EquivalentPathEntries -Entries $pathAfterEntries -Expected $ownedPathEntry)
if ($ownedMatchesAfter.Count -ne $preExistingMatches.Count) {
    $differences = Get-NormalizedPathDifferences -Before $pathBeforeEntries -After $pathAfterEntries
    $details = Format-NormalizedPathDifferences -Differences $differences
    throw "Uninstall left $($ownedMatchesAfter.Count) equivalent owned PATH entries; expected $($preExistingMatches.Count).$([Environment]::NewLine)$details"
}
$ownership = Get-ItemProperty -LiteralPath $ownershipKey -ErrorAction SilentlyContinue
$ownedProperty = if ($null -eq $ownership) { $null } else { $ownership.PSObject.Properties['OwnedPathEntry'] }
if ($null -ne $ownedProperty) { throw 'Uninstall left the PATH ownership marker behind.' }
Assert-PathEntriesPreserved `
    -Before $pathBeforeEntries `
    -After $pathAfterEntries `
    -Context 'Uninstall'

# Exercise preservation of duplicate unrelated entries and trailing empty segments explicitly. A
# PATH ending in ';' previously lost that final empty segment when the installer appended its entry.
$pathBeforeEdgeCase = [Environment]::GetEnvironmentVariable('Path', 'User')
$edgeCaseEntry = Join-Path $validationRoot 'unrelated-entry'
$edgeCaseTail = $edgeCaseEntry + '\;' + $edgeCaseEntry.ToUpperInvariant() + ';;'
$pathWithEdgeCases = if ($null -eq $pathBeforeEdgeCase) {
    $edgeCaseTail
}
else {
    $pathBeforeEdgeCase + ';' + $edgeCaseTail
}
$edgeCaseEntriesBefore = @(Get-PathEntrySnapshot -Value $pathWithEdgeCases)
$edgeCaseInstalled = $false
try {
    [Environment]::SetEnvironmentVariable('Path', $pathWithEdgeCases, 'User')
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Edge-case PATH install failed with $($process.ExitCode)." }
    $edgeCaseInstalled = $true

    $edgeCaseEntriesAfterInstall = @(Get-PathEntrySnapshot -Value (
        [Environment]::GetEnvironmentVariable('Path', 'User')))
    $ownership = Get-ItemProperty -LiteralPath $ownershipKey -ErrorAction SilentlyContinue
    $ownedProperty = if ($null -eq $ownership) { $null } else { $ownership.PSObject.Properties['OwnedPathEntry'] }
    if ($null -eq $ownedProperty) { throw 'Edge-case install did not record PATH ownership.' }
    $edgeCaseOwnedEntry = [string] $ownedProperty.Value
    $matches = @(Get-EquivalentPathEntries `
        -Entries $edgeCaseEntriesAfterInstall `
        -Expected $edgeCaseOwnedEntry)
    if ($matches.Count -ne 1) {
        $differences = Get-NormalizedPathDifferences `
            -Before $edgeCaseEntriesBefore `
            -After $edgeCaseEntriesAfterInstall
        $details = Format-NormalizedPathDifferences -Differences $differences
        throw "Edge-case install created $($matches.Count) equivalent owned PATH entries.$([Environment]::NewLine)$details"
    }
    Assert-PathEntriesPreserved `
        -Before $edgeCaseEntriesBefore `
        -After $edgeCaseEntriesAfterInstall `
        -Context 'Edge-case install'

    $uninstaller = Join-Path $installRoot 'unins000.exe'
    $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
    ) -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) { throw "Edge-case PATH uninstall failed with $($uninstall.ExitCode)." }
    $edgeCaseInstalled = $false

    $edgeCaseEntriesAfterUninstall = @(Get-PathEntrySnapshot -Value (
        [Environment]::GetEnvironmentVariable('Path', 'User')))
    $matches = @(Get-EquivalentPathEntries `
        -Entries $edgeCaseEntriesAfterUninstall `
        -Expected $edgeCaseOwnedEntry)
    if ($matches.Count -ne 0) {
        $differences = Get-NormalizedPathDifferences `
            -Before $edgeCaseEntriesBefore `
            -After $edgeCaseEntriesAfterUninstall
        $details = Format-NormalizedPathDifferences -Differences $differences
        throw "Edge-case uninstall left $($matches.Count) equivalent owned PATH entries.$([Environment]::NewLine)$details"
    }
    $ownership = Get-ItemProperty -LiteralPath $ownershipKey -ErrorAction SilentlyContinue
    $ownedProperty = if ($null -eq $ownership) { $null } else { $ownership.PSObject.Properties['OwnedPathEntry'] }
    if ($null -ne $ownedProperty) { throw 'Edge-case uninstall left the PATH ownership marker behind.' }
    Assert-PathEntriesPreserved `
        -Before $edgeCaseEntriesBefore `
        -After $edgeCaseEntriesAfterUninstall `
        -Context 'Edge-case uninstall'
}
finally {
    if ($edgeCaseInstalled -and (Test-Path -LiteralPath (Join-Path $installRoot 'unins000.exe'))) {
        Start-Process -FilePath (Join-Path $installRoot 'unins000.exe') -ArgumentList @(
            '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
        ) -Wait | Out-Null
    }
    [Environment]::SetEnvironmentVariable('Path', $pathBeforeEdgeCase, 'User')
}

# A matching entry that predates installation is not ours. The task must avoid duplicating it, must
# not write an ownership marker, and must leave the exact pre-existing text in place on uninstall.
$pathBeforeLookalike = [Environment]::GetEnvironmentVariable('Path', 'User')
$lookalike = $installRoot + '\'
$pathWithLookalike = if ([string]::IsNullOrEmpty($pathBeforeLookalike)) {
    $lookalike
}
elseif ($pathBeforeLookalike.EndsWith(';', [StringComparison]::Ordinal)) {
    $pathBeforeLookalike + $lookalike
}
else {
    $pathBeforeLookalike + ';' + $lookalike
}
$lookalikeEntriesBefore = @(Get-PathEntrySnapshot -Value $pathWithLookalike)
$lookalikeInstalled = $false
try {
    [Environment]::SetEnvironmentVariable('Path', $pathWithLookalike, 'User')
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Lookalike PATH install failed with $($process.ExitCode)." }
    $lookalikeInstalled = $true

    $lookalikeEntriesAfterInstall = @(Get-PathEntrySnapshot -Value (
        [Environment]::GetEnvironmentVariable('Path', 'User')))
    $matches = @(Get-EquivalentPathEntries `
        -Entries $lookalikeEntriesAfterInstall `
        -Expected $normalizedInstallRoot)
    if ($matches.Count -ne 1 -or $matches[0].Raw -cne $lookalike) {
        throw 'Installer duplicated or rewrote a pre-existing equivalent PATH entry.'
    }
    Assert-PathEntriesPreserved `
        -Before $lookalikeEntriesBefore `
        -After $lookalikeEntriesAfterInstall `
        -Context 'Lookalike install'
    $ownership = Get-ItemProperty -LiteralPath $ownershipKey -ErrorAction SilentlyContinue
    $ownedProperty = if ($null -eq $ownership) { $null } else { $ownership.PSObject.Properties['OwnedPathEntry'] }
    if ($null -ne $ownedProperty) { throw 'Installer claimed a pre-existing equivalent PATH entry.' }

    $uninstaller = Join-Path $installRoot 'unins000.exe'
    $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
    ) -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) { throw "Lookalike PATH uninstall failed with $($uninstall.ExitCode)." }
    $lookalikeInstalled = $false
    $lookalikeEntriesAfterUninstall = @(Get-PathEntrySnapshot -Value (
        [Environment]::GetEnvironmentVariable('Path', 'User')))
    $matches = @(Get-EquivalentPathEntries `
        -Entries $lookalikeEntriesAfterUninstall `
        -Expected $normalizedInstallRoot)
    if ($matches.Count -ne 1 -or $matches[0].Raw -cne $lookalike) {
        throw 'Uninstall removed or rewrote a pre-existing equivalent PATH entry.'
    }
    $ownership = Get-ItemProperty -LiteralPath $ownershipKey -ErrorAction SilentlyContinue
    $ownedProperty = if ($null -eq $ownership) { $null } else { $ownership.PSObject.Properties['OwnedPathEntry'] }
    if ($null -ne $ownedProperty) { throw 'Lookalike uninstall created or retained a PATH ownership marker.' }
    Assert-PathEntriesPreserved `
        -Before $lookalikeEntriesBefore `
        -After $lookalikeEntriesAfterUninstall `
        -Context 'Lookalike uninstall'
}
finally {
    if ($lookalikeInstalled -and (Test-Path -LiteralPath (Join-Path $installRoot 'unins000.exe'))) {
        Start-Process -FilePath (Join-Path $installRoot 'unins000.exe') -ArgumentList @(
            '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
        ) -Wait | Out-Null
    }
    [Environment]::SetEnvironmentVariable('Path', $pathBeforeLookalike, 'User')
}

Write-Host 'Validated per-user install/reinstall, GUI + CLI contents, PATH ownership/non-ownership, ARP metadata, and uninstall.'
