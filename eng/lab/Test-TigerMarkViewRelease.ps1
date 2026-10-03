#Requires -Version 7.0
<#
    .SYNOPSIS
    Proves a TigerMarkView installer, its shell integration, and the desktop application in
    TigerWinLab.

    .DESCRIPTION
    Two lab phases, both on a clean Windows 11 guest and never on this desktop:

      1. The installer acceptance, eng\lab\installer\accept.ps1, as one TigerWinLab -Desktop job per
         Windows theme: a fresh per-user install and removal; an upgrade over the published Inno
         Setup installation; Open with on a path with spaces and Unicode; a followed link, File >
         Open and a drag from Explorer onto the document, each against Open Recent; an in-place
         upgrade to a later installer, which keeps the local data; Clear Recent Files; the removal of
         the installation with its local data; and an all-users upgrade and removal. Every assertion
         is this repository's; TigerWinLab supplies the guest, the interactive desktop and the
         evidence.
      2. The generic desktop scenario on a self-contained build: UI Automation exposure, physical
         menu input, modal handling, occlusion, and F1 Help.

    The installer is the exact file named by -InstallerPath (a local candidate or a retrieved
    release asset). The installation it migrates from is a published Inno Setup release, taken from a
    retained copy of its published bytes and refused unless it matches the SHA-256 recorded while
    GitHub still served it; the v0.8.x assets were withdrawn on purpose and are never downloaded. The
    later installer
    it is upgraded to only has to be newer and carry this repository's installer; by default it is a
    local build of the next patch version.

    .PARAMETER InstallerPath
    Defaults to artifacts\installer\TigerMarkView-<version>-win-x64-setup.exe, where <version> is
    -Version or Version.props.

    .PARAMETER Version
    The candidate's version when it was built with installer\Build-Installer.ps1 -Version.

    .PARAMETER UpgradeFromVersion
    The published Inno Setup release to migrate from. Defaults to 0.8.1, the last one published as a
    GitHub release (0.9.0, the last Inno Setup build, was tagged but not published). Releases from
    0.10.0 on are TigerSetup installations; the in-place upgrade covers those. The script records the
    published SHA-256 of each release it accepts.

    .PARAMETER UpgradeFromInstallerPath
    The retained copy of that published installer. Defaults to
    artifacts\lab\retained\TigerMarkView-<UpgradeFromVersion>-win-x64-setup.exe. It is used only when
    it hashes to the recorded published SHA-256 and its version resource names that release.

    .PARAMETER UpgradeToInstallerPath
    A later TigerMarkView installer to upgrade the candidate to in place. Defaults to
    artifacts\installer\TigerMarkView-<next patch version>-win-x64-setup.exe, built with
    installer\Build-Installer.ps1 -Version when it is not there.

    .PARAMETER Theme
    light, dark, or both (the default): one installer acceptance run per Windows theme, with the
    viewer's own theme set to match.

    .PARAMETER SkipInstallerAcceptance
    Runs only the desktop scenario. -SkipDesktopScenario is the converse.

    .PARAMETER TigerWinLabRoot
    An explicit TigerWinLab working copy. Omit it and the lab is discovered from the TigerAiCore
    configuration named by TigerAiCoreConfig; there is no sibling checkout or environment-variable
    fallback.
#>
[CmdletBinding()]
param(
    [string] $InstallerPath,
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $UpgradeFromVersion = '0.8.1',
    [string] $UpgradeFromInstallerPath,
    [string] $UpgradeToInstallerPath,
    [ValidateSet('light', 'dark', 'both')]
    [string] $Theme = 'both',
    [switch] $SkipInstallerAcceptance,
    [switch] $SkipDesktopScenario,
    [string] $TigerWinLabRoot,
    [string] $Baseline = 'TigerWinLab-Win11-Clean',
    [ValidateRange(10, 240)]
    [int] $TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$env:AVALONIA_TELEMETRY_OPTOUT = '1'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'TigerAiCore.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
[xml] $versionProps = Get-Content -LiteralPath (Join-Path $repoRoot 'Version.props') -Raw
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = [string] $versionProps.Project.PropertyGroup.Version }
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = Join-Path $repoRoot "artifacts\installer\TigerMarkView-$Version-win-x64-setup.exe"
}
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw "Installer not found: $InstallerPath" }

# The installer's own declaration is what the lab checks against, not a name.
& (Join-Path $repoRoot 'eng\release-automation\Assert-Installer.ps1') -InstallerPath $InstallerPath -ExpectedVersion $Version

$lab = Assert-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab' -Path $TigerWinLabRoot -RequiredCommand @(
    'Invoke-TigerWinLabJob.ps1'
    'Invoke-TigerWinLabDesktopScenario.ps1'
)
$TigerWinLabRoot = $lab.Path
Write-Host "TigerWinLab resolved from $($lab.Source): $TigerWinLabRoot"

$outputRoot = Join-Path $repoRoot "artifacts\lab\$Version"
$cacheRoot = Join-Path $repoRoot 'artifacts\lab\cache'
New-Item -ItemType Directory -Path $outputRoot, $cacheRoot -Force | Out-Null

function Invoke-LabChild {
    <#
        Runs a TigerWinLab entry point as a child process with its own result path, and fails on a
        missing or unreadable result whatever the exit code says. Exit codes: 0 OK, 1 failed,
        2 the VM could not be leased, 3 timeout.
    #>
    param([string] $Name, [string] $Command, [string[]] $Arguments)

    $resultPath = Join-Path $outputRoot "$Name-result.json"
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    $all = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $TigerWinLabRoot $Command)) +
        $Arguments + @('-TimeoutMinutes', $TimeoutMinutes, '-OutputRoot', (Join-Path $outputRoot $Name), '-ResultPath', $resultPath)
    $process = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $all -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $outputRoot "$Name.stdout.log") -RedirectStandardError (Join-Path $outputRoot "$Name.stderr.log")
    # Headroom beyond the lab's own timeout: its teardown and baseline restore continue after it fires.
    $outerTimeout = [TimeSpan]::FromMinutes($TimeoutMinutes + 30)
    if (-not $process.WaitForExit([int] $outerTimeout.TotalMilliseconds)) {
        $process.Kill($true)
        throw "TigerWinLab $Name did not finish within $($outerTimeout.TotalMinutes) minutes; its job was stopped."
    }
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Get-Content -LiteralPath (Join-Path $outputRoot "$Name.stderr.log") -ErrorAction SilentlyContinue | Write-Host
        throw "TigerWinLab $Name exited with $($process.ExitCode) and wrote no result to $resultPath."
    }
    [pscustomobject]@{ exitCode = $process.ExitCode; result = (Get-Content -LiteralPath $resultPath -Raw -Encoding utf8 | ConvertFrom-Json) }
}

# --- the published release to upgrade from -------------------------------------------------------
# The v0.8.x installers were withdrawn from their GitHub Releases on purpose: they predate the
# active-content remediation. The migration row therefore never downloads one. It uses a retained copy
# of the bytes that were published, and refuses it unless it hashes to the digest recorded while GitHub
# still served the asset (artifacts\winget-release\0.8.1\validation\result.json, 2026-08-28).
$publishedInnoInstallers = @{
    '0.8.1' = 'B81118C96655A7E6E28642A22AE5FC14CBD4EF47F2FA5928A35408833EE4BE9F'
}
if (-not $publishedInnoInstallers.ContainsKey($UpgradeFromVersion)) {
    throw "No published SHA-256 is recorded for TigerMarkView $UpgradeFromVersion; the migration row starts from $(@($publishedInnoInstallers.Keys) -join ', ')."
}
$legacyName = "TigerMarkView-$UpgradeFromVersion-win-x64-setup.exe"
if ([string]::IsNullOrWhiteSpace($UpgradeFromInstallerPath)) {
    $UpgradeFromInstallerPath = Join-Path $repoRoot "artifacts\lab\retained\$legacyName"
}
if (-not (Test-Path -LiteralPath $UpgradeFromInstallerPath -PathType Leaf)) {
    throw ("The retained published installer $UpgradeFromInstallerPath is missing. Place the published " +
        "$legacyName (SHA-256 $($publishedInnoInstallers[$UpgradeFromVersion])) there, or pass -UpgradeFromInstallerPath.")
}
$legacyPath = (Resolve-Path -LiteralPath $UpgradeFromInstallerPath).Path
$legacyHash = (Get-FileHash -LiteralPath $legacyPath -Algorithm SHA256).Hash
if ($legacyHash -cne $publishedInnoInstallers[$UpgradeFromVersion]) {
    throw ("$legacyPath hashes to $legacyHash, not the published TigerMarkView $UpgradeFromVersion installer " +
        "$($publishedInnoInstallers[$UpgradeFromVersion]); a local or rebuilt copy is not the release it migrates from.")
}
$legacyInfo = (Get-Item -LiteralPath $legacyPath).VersionInfo
# Inno Setup pads its version-resource strings.
if (([string] $legacyInfo.ProductName).Trim() -cne 'TigerMarkView' -or ([string] $legacyInfo.ProductVersion).Trim() -notmatch '^(?<version>\d+\.\d+\.\d+)' -or
    $Matches.version -cne $UpgradeFromVersion) {
    throw "$legacyPath is not the TigerMarkView $UpgradeFromVersion installer ($($legacyInfo.ProductName) $($legacyInfo.ProductVersion))."
}
$legacyName = [IO.Path]::GetFileName($legacyPath)
if ([version] $UpgradeFromVersion -gt [version] '0.9.0') {
    throw "TigerMarkView $UpgradeFromVersion is not an Inno Setup release; the migration it proves starts from 0.9.0 or earlier."
}
Write-Host "Upgrading from $legacyName, TigerMarkView $UpgradeFromVersion (SHA-256 $legacyHash)."

# --- the later installer the candidate is upgraded to in place -----------------------------------
if ([string]::IsNullOrWhiteSpace($UpgradeToInstallerPath)) {
    $candidate = [version] $Version
    $nextVersion = '{0}.{1}.{2}' -f $candidate.Major, $candidate.Minor, ($candidate.Build + 1)
    $UpgradeToInstallerPath = Join-Path $repoRoot "artifacts\installer\TigerMarkView-$nextVersion-win-x64-setup.exe"
    if (-not (Test-Path -LiteralPath $UpgradeToInstallerPath -PathType Leaf)) {
        Write-Host "Building the later installer, TigerMarkView $nextVersion, to upgrade the candidate to..."
        & (Join-Path $repoRoot 'installer\Build-Installer.ps1') -Version $nextVersion -Fast
    }
}
$nextPath = (Resolve-Path -LiteralPath $UpgradeToInstallerPath).Path
$nextName = [IO.Path]::GetFileName($nextPath)
if ($nextName -notmatch '^TigerMarkView-(?<version>\d+\.\d+\.\d+)-win-x64-setup\.exe$' -or [version] $Matches.version -le [version] $Version) {
    throw "$nextName is not a TigerMarkView installer later than the candidate $Version."
}
$nextVersion = $Matches.version
& (Join-Path $repoRoot 'eng\release-automation\Assert-Installer.ps1') -InstallerPath $nextPath -ExpectedVersion $nextVersion
Write-Host "Upgrading in place to $nextName (SHA-256 $((Get-FileHash -LiteralPath $nextPath -Algorithm SHA256).Hash))."

# The .NET 10 Desktop Runtime the product declares, staged so the guest can run offline.
$runtimeName = 'windowsdesktop-runtime-10-win-x64.exe'
$runtimePath = Join-Path $cacheRoot $runtimeName
if (-not (Test-Path -LiteralPath $runtimePath)) {
    Invoke-WebRequest -Uri 'https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe' -OutFile $runtimePath
}
$signature = Get-AuthenticodeSignature -LiteralPath $runtimePath
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw "$runtimePath is not a valid Microsoft-signed installer ($($signature.Status))."
}

# --- phase 1: the installer acceptance, per theme -----------------------------------------------
$payloadRoot = Join-Path $outputRoot 'payload'
if (Test-Path -LiteralPath $payloadRoot) { Remove-Item -LiteralPath $payloadRoot -Recurse -Force }
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
foreach ($file in @($InstallerPath, $legacyPath, $nextPath, $runtimePath)) { Copy-Item -LiteralPath $file -Destination $payloadRoot }
foreach ($file in 'accept.ps1', 'shell.ps1') {
    # The guest runs Windows PowerShell 5.1, which reads BOM-less UTF-8 as ANSI.
    Get-Content -LiteralPath (Join-Path $PSScriptRoot "installer\$file") -Raw -Encoding utf8 |
        Set-Content -LiteralPath (Join-Path $payloadRoot $file) -Encoding utf8BOM -NoNewline
    $env:TMV_ACCEPTANCE_SCRIPT = Join-Path $payloadRoot $file
    try {
        powershell.exe -NoProfile -NonInteractive -Command '$tokens = $null; $parseErrors = $null; [System.Management.Automation.Language.Parser]::ParseFile($env:TMV_ACCEPTANCE_SCRIPT, [ref]$tokens, [ref]$parseErrors) | Out-Null; if ($parseErrors.Count) { $parseErrors | Out-String | Write-Error; exit 1 }'
        if ($LASTEXITCODE -ne 0) { throw "The guest script $file does not parse in Windows PowerShell 5.1." }
    }
    finally { Remove-Item Env:TMV_ACCEPTANCE_SCRIPT }
}

$failures = [Collections.Generic.List[string]]::new()
$themes = @(if ($SkipInstallerAcceptance) { @() } elseif ($Theme -eq 'both') { @('light', 'dark') } else { @($Theme) })
foreach ($windowsTheme in $themes) {
    $run = [ordered]@{
        version = $Version
        candidate = [IO.Path]::GetFileName($InstallerPath)
        legacy = $legacyName
        legacyVersion = $UpgradeFromVersion
        next = $nextName
        nextVersion = $nextVersion
        runtime = $runtimeName
        windowsTheme = $windowsTheme
        appTheme = if ($windowsTheme -eq 'dark') { 'Dark' } else { 'Light' }
    }
    $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $payloadRoot 'run.json') -Encoding utf8NoBOM

    $name = "installer-$windowsTheme"
    Write-Host "Running the installer acceptance in TigerWinLab ($Baseline, $windowsTheme theme)..."
    $outcome = Invoke-LabChild -Name $name -Command 'Invoke-TigerWinLabJob.ps1' -Arguments @(
        '-Name', "tigermarkview-$name", '-PayloadPath', $payloadRoot, '-EntryScript', 'accept.ps1', '-Desktop',
        '-Baseline', $Baseline, '-Theme', $windowsTheme, '-NetworkState', 'offline')
    $phases = @()
    if ($null -ne $outcome.result.PSObject.Properties['result'] -and $null -ne $outcome.result.result -and
        $null -ne $outcome.result.result.PSObject.Properties['phases']) {
        $phases = @($outcome.result.result.phases)
    }
    foreach ($phase in $phases) {
        Write-Host ''
        Write-Host "[$($phase.status)] $name / $($phase.name)"
        foreach ($check in @($phase.checks)) { Write-Host ("  {0,-4} {1,-32} {2}" -f $check.status, $check.code, $check.message) }
    }
    $failed = @($phases | ForEach-Object { @($_.checks) } | Where-Object { $_.status -ne 'PASS' })
    if ($outcome.exitCode -ne 0 -or $outcome.result.status -ne 'OK' -or $phases.Count -eq 0 -or $failed.Count -gt 0) {
        $failures.Add("$name`: TigerWinLab status $($outcome.result.status), exit $($outcome.exitCode), $($failed.Count) failed check(s): $($outcome.result.message)")
    }
    Write-Host "Evidence: $(Join-Path $outputRoot $name)"
}

# --- phase 2: the desktop scenario --------------------------------------------------------------
if (-not $SkipDesktopScenario) {
    $desktopPublish = Join-Path $repoRoot 'artifacts\publish\win-x64-selfcontained'
    if (Test-Path -LiteralPath $desktopPublish) { Remove-Item -LiteralPath $desktopPublish -Recurse -Force }
    $versionProperty = @(if ($Version -cne [string] $versionProps.Project.PropertyGroup.Version) { "-p:Version=$Version" })
    dotnet publish (Join-Path $repoRoot 'src\TigerMarkView\TigerMarkView.csproj') --configuration Release --runtime win-x64 `
        --self-contained true --output $desktopPublish -m:1 @versionProperty
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the self-contained TigerWinLab desktop payload.' }

    $desktopSpec = [ordered]@{
        schemaVersion = 1
        name = 'tigermarkview'
        application = [ordered]@{
            displayName = 'TigerMarkView'
            path = $desktopPublish
            executable = 'TigerMarkView.exe'
            windowTitlePattern = '(?i)TigerMarkView'
            startupTimeoutSeconds = 120
            settleMilliseconds = 5000
            document = [ordered]@{
                fileName = 'tigermarkview-release.md'
                content = "# TigerMarkView $Version release verification`n`nRendered inside TigerWinLab.`n"
            }
        }
        expected = [ordered]@{
            uiFramework = 'Avalonia'
            minimumElementCount = 20
            minimumChangedPixels = 500
            controls = @(
                [ordered]@{ automationId = 'MainMenu'; controlType = 'Menu' },
                [ordered]@{ automationId = 'FileMenu'; controlType = 'MenuItem' },
                [ordered]@{ automationId = 'HelpMenu'; controlType = 'MenuItem' },
                [ordered]@{ automationId = 'OpenToolbarButton'; controlType = 'Button'; patterns = @('Invoke') },
                [ordered]@{ automationId = 'StatusText'; controlType = 'Text' }
            )
            semanticControl = [ordered]@{ automationId = 'MenuToolbarButton'; controlType = 'Button'; pattern = 'invoke' }
            physicalControl = [ordered]@{
                automationId = 'FileMenu'
                controlType = 'MenuItem'
                unsupportedPatterns = @('invoke', 'expand')
                opensItems = @('Open...', 'Export to PDF...', 'Exit')
            }
            occludedControl = [ordered]@{ automationId = 'OpenToolbarButton'; controlType = 'Button' }
            modalControl = [ordered]@{ automationId = 'OpenToolbarButton'; controlType = 'Button' }
            keyboard = [ordered]@{ keys = @('F1'); windowTitlePattern = '(?i)help' }
        }
    }
    $desktopSpecPath = Join-Path $outputRoot 'desktop-spec.json'
    $desktopSpec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $desktopSpecPath -Encoding utf8NoBOM

    Write-Host 'Running the desktop scenario in TigerWinLab...'
    $desktop = Invoke-LabChild -Name 'desktop' -Command 'Invoke-TigerWinLabDesktopScenario.ps1' -Arguments @('-SpecPath', $desktopSpecPath)
    if ($desktop.exitCode -ne 0 -or $desktop.result.status -ne 'OK') {
        $failures.Add("desktop: TigerWinLab status $($desktop.result.status), exit $($desktop.exitCode): $($desktop.result.message)")
    }
    else {
        Write-Host '[PASS] desktop scenario'
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    exit 1
}
$ran = @(if ($themes.Count -gt 0) { "installer acceptance ($($themes -join ', ') theme)" }; if (-not $SkipDesktopScenario) { 'desktop scenario' })
Write-Host "PASS: TigerMarkView $Version in TigerWinLab: $($ran -join ' and ')." -ForegroundColor Green
exit 0
