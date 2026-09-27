#Requires -Version 7.0
<#
    .SYNOPSIS
    Checks a built TigerMarkView installer without running it.

    .DESCRIPTION
    The installer is a TigerSetup Setup.exe, so what it will do is declared in its embedded
    metadata. `tiger-setup verify` proves the bytes are intact (hashes, CRCs, the declared files),
    and `tiger-setup inspect --json` is read for the product's contract:

      - identity: ItTiger.TigerMarkView, TigerMarkView, IT Tiger, the expected version, x64, both
        scopes with per-user first, and the Add/Remove Programs key;
      - content: the GUI, tiger-mark, and the offline documentation, and no .pdb or .xml file;
      - integration: the PATH option on by default, the Start Menu shortcut, the Markdown handler
        registration (never a default), the Inno Setup installation it replaces, and the two
        prerequisites.

    Installation behaviour - install, upgrade, uninstall, PATH, the shell registration - is proven
    on the exact bytes in TigerWinLab (eng\lab\Test-TigerMarkViewRelease.ps1), not here.

    .PARAMETER TigerSetupPath
    tiger-setup.exe; defaults to the one on PATH. Must be the version installer\tigersetup.json pins.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $InstallerPath,

    [Parameter(Mandatory)]
    [string] $ExpectedVersion,

    [string] $TigerSetupPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'installer' 'TigerSetupBuilder.ps1')

$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw "Installer not found: $InstallerPath" }
$expectedName = "TigerMarkView-$ExpectedVersion-win-x64-setup.exe"
if ([IO.Path]::GetFileName($InstallerPath) -cne $expectedName) { throw "Installer file name must be '$expectedName'." }

$tigerSetup = Resolve-TigerMarkViewTigerSetup -RepositoryRoot $repoRoot -Path $TigerSetupPath

& $tigerSetup verify $InstallerPath | Out-Host
if ($LASTEXITCODE -ne 0) { throw "tiger-setup verify rejected '$InstallerPath' (exit code $LASTEXITCODE)." }

$json = & $tigerSetup inspect $InstallerPath --json
if ($LASTEXITCODE -ne 0) { throw "tiger-setup inspect failed for '$InstallerPath' (exit code $LASTEXITCODE)." }
$inspection = ($json -join "`n") | ConvertFrom-Json

$failures = [Collections.Generic.List[string]]::new()
function Assert-That([bool] $Condition, [string] $Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

$package = $inspection.package
Assert-That ($package.id -ceq 'ItTiger.TigerMarkView') "package id is '$($package.id)'."
Assert-That ($package.name -ceq 'TigerMarkView') "package name is '$($package.name)'."
Assert-That ($package.publisher -ceq 'IT Tiger') "package publisher is '$($package.publisher)'."
Assert-That ($package.version -ceq $ExpectedVersion) "package version is '$($package.version)', not '$ExpectedVersion'."
Assert-That ($package.architecture -ceq 'x64') "package architecture is '$($package.architecture)'."
Assert-That ((@($package.scopes) -join ',') -ceq 'user,machine') "scopes are '$(@($package.scopes) -join ',')', not per-user first then all users."
Assert-That ($inspection.registration.key_name -ceq 'ItTiger.TigerMarkView') "registration key is '$($inspection.registration.key_name)'."

# inspect reports install-relative paths with forward slashes.
$paths = @($inspection.files | ForEach-Object { ([string] $_.path).Replace('/', '\') })
foreach ($required in 'TigerMarkView.exe', 'tiger-mark.exe', 'TigerMarkView.Core.dll', 'TigerMarkView.Pdf.dll',
    'WebView2Loader.dll', 'Docs\HELP.md', 'Docs\LICENSE.txt', 'Docs\THIRD-PARTY-NOTICES.md') {
    Assert-That ($paths -ccontains $required) "the payload has no '$required'."
}
$excluded = @($paths | Where-Object { $_ -match '\.(pdb|xml)$' })
Assert-That ($excluded.Count -eq 0) "the payload carries debug symbols or XML documentation: $($excluded -join ', ')."

$pathOption = @($inspection.options | Where-Object { $_.name -ceq 'path' })
Assert-That ($pathOption.Count -eq 1 -and [string] $pathOption[0].default -eq 'True') 'the PATH option is not declared on by default.'
$startMenu = @($inspection.shortcuts | Where-Object { $_.location -ceq 'start-menu' -and $_.target -ceq 'TigerMarkView.exe' })
Assert-That ($startMenu.Count -eq 1) 'there is not exactly one Start Menu shortcut to TigerMarkView.exe.'

$associations = @($inspection.file_associations)
Assert-That ($associations.Count -eq 1) "expected one file association, found $($associations.Count)."
if ($associations.Count -eq 1) {
    $association = $associations[0]
    Assert-That ($association.prog_id -ceq 'TigerMarkView.Markdown') "the handler ProgID is '$($association.prog_id)'."
    Assert-That ((@($association.extensions) -join ',') -ceq '.md,.markdown') "the handler extensions are '$(@($association.extensions) -join ',')'."
    Assert-That ($association.executable -ceq 'TigerMarkView.exe') "the handler runs '$($association.executable)'."
    Assert-That ([string]::IsNullOrEmpty([string] $association.arguments)) 'the handler overrides the quoted "%1" argument.'
    Assert-That ($null -eq $association.when) 'the handler registration is conditional.'
}

Assert-That ($inspection.legacy.installer_type -ceq 'inno' -and
    $inspection.legacy.registration_key -ceq '{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}_is1') 'the Inno Setup installation it replaces is not declared.'
$dependencies = @($inspection.dependencies | ForEach-Object { [string] $_.id }) | Sort-Object
Assert-That (($dependencies -join ',') -ceq 'Microsoft.DotNet.DesktopRuntime.10,Microsoft.EdgeWebView2Runtime') "dependencies are '$($dependencies -join ',')'."

if ($failures.Count -gt 0) {
    throw "Installer '$InstallerPath' does not meet the TigerMarkView contract:`n  - $($failures -join "`n  - ")"
}
Write-Host "PASS: $expectedName verifies and declares the TigerMarkView $ExpectedVersion installation contract." -ForegroundColor Green
