<#
    .SYNOPSIS
    Resolves the pinned TigerSetup builder. Dot-source this file.

    .DESCRIPTION
    installer\tigersetup.json names the one TigerSetup release every TigerMarkView installer and
    WinGet manifest set is built with: locally, in the release workflow (which installs exactly that
    release with eng\release-automation\Install-TigerSetup.ps1), and when the post-release gate
    regenerates a manifest set for comparison. A builder of another version would produce different
    bytes, so it is refused rather than used.

    Kept compatible with Windows PowerShell 5.1: Install-TigerSetup.ps1 uses it there too.

    The builder is an explicit path, or tiger-setup.exe on PATH - how the TigerAiCore configuration
    registers the TigerSetup tool (a command, not a path) and how its installer offers it.
#>

Set-StrictMode -Version Latest

function Get-TigerMarkViewTigerSetupPin {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepositoryRoot)

    $pin = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'installer\tigersetup.json') -Raw | ConvertFrom-Json
    foreach ($name in 'version', 'installerUrl', 'installerSha256') {
        if ([string]::IsNullOrWhiteSpace([string] $pin.$name)) { throw "installer\tigersetup.json does not define '$name'." }
    }
    if ([string] $pin.version -notmatch '^\d+\.\d+\.\d+$') { throw "installer\tigersetup.json version '$($pin.version)' is not a release version." }
    if ([string] $pin.installerSha256 -notmatch '^[0-9A-F]{64}$') { throw 'installer\tigersetup.json installerSha256 must be 64 upper-case hex digits.' }
    $expectedUrl = "https://github.com/rkozlowski/TigerSetup/releases/download/v$($pin.version)/TigerSetup-$($pin.version)-Setup.exe"
    if ([string] $pin.installerUrl -cne $expectedUrl) { throw "installer\tigersetup.json installerUrl must be '$expectedUrl'." }
    $pin
}

function Get-TigerMarkViewTigerSetupVersion {
    <# The version tiger-setup.exe reports: "tiger-setup 0.12.0". #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $reported = (& $Path --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $reported -notmatch '^tiger-setup (?<version>\d+\.\d+\.\d+)$') {
        throw "'$Path --version' reported '$reported' (exit $LASTEXITCODE), not 'tiger-setup <version>'."
    }
    $Matches.version
}

function Resolve-TigerMarkViewTigerSetup {
    <#
        .SYNOPSIS
        The full path of the pinned tiger-setup.exe, or a failure that says how to get it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [string] $Path
    )

    $pin = Get-TigerMarkViewTigerSetupPin -RepositoryRoot $RepositoryRoot
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "tiger-setup.exe not found at '$Path'." }
        $resolved = (Resolve-Path -LiteralPath $Path).Path
    }
    else {
        $command = Get-Command 'tiger-setup.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $command) {
            throw ("TigerSetup's builder (tiger-setup.exe) was not found on PATH. Install TigerSetup " +
                "$($pin.version) from $($pin.installerUrl) (or: winget install ItTiger.TigerSetup --version " +
                "$($pin.version)), or pass the path to tiger-setup.exe explicitly.")
        }
        $resolved = $command.Source
    }

    $version = Get-TigerMarkViewTigerSetupVersion -Path $resolved
    if ($version -cne [string] $pin.version) {
        throw "'$resolved' is TigerSetup $version; installer\tigersetup.json pins $($pin.version)."
    }
    $resolved
}
