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

    $normalizedInstallRoot = $installRoot.TrimEnd('\', '/')
    $pathMatches = @(([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') | Where-Object {
        $_.Trim().TrimEnd('\', '/') -ieq $normalizedInstallRoot
    })
    if ($pathMatches.Count -ne 1) {
        throw "Expected one owned per-user PATH entry for '$installRoot'; found $($pathMatches.Count)."
    }

    $reinstall = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
    if ($reinstall.ExitCode -ne 0) { throw "Silent per-user reinstall failed with $($reinstall.ExitCode)." }
    $pathMatches = @(([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') | Where-Object {
        $_.Trim().TrimEnd('\', '/') -ieq $normalizedInstallRoot
    })
    if ($pathMatches.Count -ne 1) {
        throw "Per-user reinstall created $($pathMatches.Count) equivalent PATH entries."
    }

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
if ($pathAfter -cne $pathBefore) {
    throw 'Uninstall did not restore the existing per-user PATH content exactly.'
}

# A matching entry that predates installation is not ours. The task must avoid duplicating it, must
# not write an ownership marker, and must leave the exact pre-existing text in place on uninstall.
$lookalike = $installRoot + '\'
$pathWithLookalike = if ([string]::IsNullOrEmpty($pathBefore)) {
    $lookalike
}
elseif ($pathBefore.EndsWith(';', [StringComparison]::Ordinal)) {
    $pathBefore + $lookalike
}
else {
    $pathBefore + ';' + $lookalike
}
$ownershipKey = "HKCU:\Software\$($properties.Company)\$($properties.Product)\Installer"
$lookalikeInstalled = $false
try {
    [Environment]::SetEnvironmentVariable('Path', $pathWithLookalike, 'User')
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Lookalike PATH install failed with $($process.ExitCode)." }
    $lookalikeInstalled = $true

    $matches = @(([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') | Where-Object {
        $_.Trim().TrimEnd('\', '/') -ieq $normalizedInstallRoot
    })
    if ($matches.Count -ne 1 -or $matches[0] -cne $lookalike) {
        throw 'Installer duplicated or rewrote a pre-existing equivalent PATH entry.'
    }
    $ownership = Get-ItemProperty -LiteralPath $ownershipKey -ErrorAction SilentlyContinue
    $ownedProperty = if ($null -eq $ownership) { $null } else { $ownership.PSObject.Properties['OwnedPathEntry'] }
    if ($null -ne $ownedProperty) { throw 'Installer claimed a pre-existing equivalent PATH entry.' }

    $uninstaller = Join-Path $installRoot 'unins000.exe'
    $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
    ) -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) { throw "Lookalike PATH uninstall failed with $($uninstall.ExitCode)." }
    $lookalikeInstalled = $false
    if ([Environment]::GetEnvironmentVariable('Path', 'User') -cne $pathWithLookalike) {
        throw 'Uninstall removed or rewrote a pre-existing equivalent PATH entry.'
    }
}
finally {
    if ($lookalikeInstalled -and (Test-Path -LiteralPath (Join-Path $installRoot 'unins000.exe'))) {
        Start-Process -FilePath (Join-Path $installRoot 'unins000.exe') -ArgumentList @(
            '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
        ) -Wait | Out-Null
    }
    [Environment]::SetEnvironmentVariable('Path', $pathBefore, 'User')
}

Write-Host 'Validated per-user install/reinstall, GUI + CLI contents, PATH ownership/non-ownership, ARP metadata, and uninstall.'
