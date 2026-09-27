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
         Open and a drag from Explorer onto the document, each against Open Recent; the removal of
         the upgraded installation; and an all-users upgrade and removal. Every assertion is this
         repository's; TigerWinLab supplies the guest, the interactive desktop and the evidence.
      2. The generic desktop scenario on a self-contained build: UI Automation exposure, physical
         menu input, modal handling, occlusion, and F1 Help.

    The installer is the exact file named by -InstallerPath (a local candidate or a retrieved
    release asset). The installation it upgrades is the latest published release, downloaded from
    GitHub and refused unless it matches the digest GitHub recorded for it.

    .PARAMETER InstallerPath
    Defaults to artifacts\installer\TigerMarkView-<version>-win-x64-setup.exe, where <version> is
    -Version or Version.props.

    .PARAMETER Version
    The candidate's version when it was built with installer\Build-Installer.ps1 -Version.

    .PARAMETER UpgradeFromVersion
    The published release to upgrade from. Defaults to the latest published release.

    .PARAMETER UpgradeFromInstallerPath
    A published Inno Setup installer to upgrade from, when GitHub no longer serves it: an explicit
    maintainer decision, used as given and recorded by its SHA-256 and version resource.

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
    [string] $UpgradeFromVersion,
    [string] $UpgradeFromInstallerPath,
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
$repositoryUrl = ([string] $versionProps.Project.PropertyGroup.RepositoryUrl).TrimEnd('/')
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
if (-not [string]::IsNullOrWhiteSpace($UpgradeFromInstallerPath)) {
    $legacyPath = (Resolve-Path -LiteralPath $UpgradeFromInstallerPath).Path
    $legacyInfo = (Get-Item -LiteralPath $legacyPath).VersionInfo
    # Inno Setup pads its version-resource strings.
    if (([string] $legacyInfo.ProductName).Trim() -cne 'TigerMarkView' -or ([string] $legacyInfo.ProductVersion).Trim() -notmatch '^(?<version>\d+\.\d+\.\d+)') {
        throw "$legacyPath is not a TigerMarkView installer ($($legacyInfo.ProductName) $($legacyInfo.ProductVersion))."
    }
    $UpgradeFromVersion = $Matches.version
    $legacyName = [IO.Path]::GetFileName($legacyPath)
    $legacyHash = (Get-FileHash -LiteralPath $legacyPath -Algorithm SHA256).Hash
}
else {
    $api = $repositoryUrl -replace '^https://github\.com/', 'https://api.github.com/repos/'
    $release = if ($UpgradeFromVersion) { Invoke-RestMethod "$api/releases/tags/v$UpgradeFromVersion" } else { Invoke-RestMethod "$api/releases/latest" }
    if ($release.draft -or $release.prerelease) { throw "Release $($release.tag_name) is not a published release." }
    $UpgradeFromVersion = ([string] $release.tag_name).TrimStart('v')
    $legacyName = "TigerMarkView-$UpgradeFromVersion-win-x64-setup.exe"
    $asset = @($release.assets | Where-Object { $_.name -ceq $legacyName })
    if ($asset.Count -ne 1 -or [string] $asset[0].digest -notmatch '^sha256:(?<hash>[0-9a-f]{64})$') {
        throw ("Release $($release.tag_name) no longer serves $legacyName with a recorded SHA-256 digest. " +
            'Pass -UpgradeFromInstallerPath with a retained copy of the published installer.')
    }
    $legacyHash = $Matches.hash.ToUpperInvariant()
    $legacyPath = Join-Path $cacheRoot $legacyName
    if (-not (Test-Path -LiteralPath $legacyPath) -or (Get-FileHash -LiteralPath $legacyPath -Algorithm SHA256).Hash -cne $legacyHash) {
        Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $legacyPath
    }
    if ((Get-FileHash -LiteralPath $legacyPath -Algorithm SHA256).Hash -cne $legacyHash) { throw "$legacyName does not match the digest GitHub recorded." }
}
Write-Host "Upgrading from $legacyName, TigerMarkView $UpgradeFromVersion (SHA-256 $legacyHash)."

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
foreach ($file in @($InstallerPath, $legacyPath, $runtimePath)) { Copy-Item -LiteralPath $file -Destination $payloadRoot }
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
