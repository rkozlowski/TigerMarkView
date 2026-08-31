#Requires -Version 7.0
<#
    .SYNOPSIS
    Resolves a working winget.exe, repairing it through Microsoft.WinGet.Client
    when the machine has none.

    .DESCRIPTION
    The release workflow runs `winget validate` over the manifests it generates, and
    a hosted runner may have no usable WinGet at all. This resolves one, proves it
    runs by asking it for `--info`, and prints its path. A maintainer workstation
    normally has WinGet already, so this is a no-op there and can be run to confirm
    that before a release.

    Nothing is installed unless the discovered winget.exe is absent or unusable.

    .PARAMETER ClientModuleVersion
    The pinned Microsoft.WinGet.Client version used for repair.

    .PARAMETER GitHubOutput
    When supplied, a GITHUB_OUTPUT file to append 'path' to.
#>
[CmdletBinding()]
param(
    [string] $ClientModuleVersion = '1.29.280',

    [string] $GitHubOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-WorkingWinGet {
    $candidate = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $candidate -or -not (Test-Path -LiteralPath $candidate.Source -PathType Leaf)) {
        return $null
    }
    & $candidate.Source --info | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "The discovered winget.exe at '$($candidate.Source)' exited with code $LASTEXITCODE."
        return $null
    }
    $candidate
}

$winget = Resolve-WorkingWinGet
if ($null -eq $winget) {
    if ($null -eq (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
        throw 'WinGet is absent or unusable and Install-Module is unavailable, so Microsoft.WinGet.Client cannot repair it.'
    }
    Install-Module Microsoft.WinGet.Client `
        -RequiredVersion $ClientModuleVersion `
        -Repository PSGallery `
        -Scope CurrentUser `
        -Force
    Import-Module Microsoft.WinGet.Client -RequiredVersion $ClientModuleVersion
    if ($null -eq (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue)) {
        throw "Microsoft.WinGet.Client $ClientModuleVersion did not expose Repair-WinGetPackageManager."
    }
    Repair-WinGetPackageManager -AllUsers
    $winget = Resolve-WorkingWinGet
}
if ($null -eq $winget) {
    throw 'WinGet provisioning completed without resolving an executable winget.exe.'
}

Write-Host "Using WinGet at '$($winget.Source)'."
if (-not [string]::IsNullOrWhiteSpace($GitHubOutput)) {
    "path=$($winget.Source)" | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
}

Write-Output $winget.Source
