#Requires -Version 7.0
<#
    .SYNOPSIS
    Resolves the pinned Inno Setup compiler, installing it when it is absent.

    .DESCRIPTION
    A hosted runner has no Inno Setup; a maintainer workstation normally does. The
    installer is downloaded only when the pinned version is not already present,
    and it is accepted only when its SHA-256 matches the pinned hash and its
    Authenticode signature is valid.

    .PARAMETER Version
    The pinned Inno Setup version.

    .PARAMETER InstallerUri
    Where to download that exact version from.

    .PARAMETER InstallerSha256
    The hash the downloaded installer must have.

    .PARAMETER GitHubOutput
    When supplied, a GITHUB_OUTPUT file to append 'compiler' to.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,

    [Parameter(Mandatory)]
    [uri] $InstallerUri,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string] $InstallerSha256,

    [string] $GitHubOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Inno Setup can only be provisioned on Windows.' }

function Write-CompilerPath {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "ISCC.exe was not provisioned at '$Path'." }
    if (-not [string]::IsNullOrWhiteSpace($GitHubOutput)) {
        "compiler=$Path" | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
    }
    Write-Output $Path
}

$innoKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 7_is1'
function Resolve-InnoSetupCompiler {
    param([Parameter(Mandatory)][string] $ExpectedVersion)

    $installation = Get-ItemProperty -LiteralPath $innoKey -ErrorAction SilentlyContinue
    if ($null -eq $installation -or
        [string] $installation.DisplayVersion -cne $ExpectedVersion -or
        [string]::IsNullOrWhiteSpace([string] $installation.InstallLocation)) {
        return $null
    }
    $compiler = Join-Path ([string] $installation.InstallLocation) 'ISCC.exe'
    if (Test-Path -LiteralPath $compiler -PathType Leaf) { return [IO.Path]::GetFullPath($compiler) }
    return $null
}

$compilerPath = Resolve-InnoSetupCompiler -ExpectedVersion $Version
if ($null -ne $compilerPath) {
    Write-CompilerPath -Path $compilerPath
    return
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('TigerMarkView-InnoSetup-' + [Guid]::NewGuid().ToString('N'))
$installerPath = Join-Path $temporaryRoot ([IO.Path]::GetFileName($InstallerUri.LocalPath))
try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    Invoke-WebRequest -Uri $InstallerUri -OutFile $installerPath
    $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
    if ($actualHash -cne $InstallerSha256.ToUpperInvariant()) {
        throw "Inno Setup installer SHA-256 '$actualHash' does not match the pinned hash."
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $installerPath
    $subject = if ($null -eq $signature.SignerCertificate) { '<none>' } else { $signature.SignerCertificate.Subject }
    if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $subject -notlike 'CN=Pyrsys B.V.,*') {
        throw "Inno Setup Authenticode validation failed: '$($signature.Status)', signer '$subject'."
    }

    $process = Start-Process -FilePath $installerPath -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/ALLUSERS'
    ) -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "Inno Setup installation failed with $($process.ExitCode)." }

    $compilerPath = Resolve-InnoSetupCompiler -ExpectedVersion $Version
    if ($null -eq $compilerPath) { throw "Inno Setup $Version installed without a resolvable ISCC.exe." }
    Write-CompilerPath -Path $compilerPath
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
