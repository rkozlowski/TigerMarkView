[CmdletBinding()]
param(
    [string] $InstallerPath,
    [string] $TigerWinLabRoot,
    [string] $UpgradeFromInstallerPath,
    [string] $UpgradeFromVersion,
    [string] $DesktopPublishDirectory,
    [ValidateRange(1, 240)]
    [int] $TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$env:AVALONIA_TELEMETRY_OPTOUT = '1'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
[xml] $versionProps = Get-Content -LiteralPath (Join-Path $repoRoot 'Version.props') -Raw
$version = [string] $versionProps.Project.PropertyGroup.Version
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = Join-Path $repoRoot "artifacts\installer\TigerMarkView-$version-win-x64-setup.exe"
}
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw "Installer not found: $InstallerPath" }

if ([string]::IsNullOrWhiteSpace($TigerWinLabRoot)) { $TigerWinLabRoot = $env:TIGERWINLAB_ROOT }
if ([string]::IsNullOrWhiteSpace($TigerWinLabRoot)) {
    $TigerWinLabRoot = Join-Path (Split-Path -Parent $repoRoot) 'TigerWinLab'
}
$TigerWinLabRoot = [IO.Path]::GetFullPath($TigerWinLabRoot)
foreach ($command in @(
    'Invoke-TigerWinLabJob.ps1'
    'Invoke-TigerWinLabInstallerScenario.ps1'
    'Invoke-TigerWinLabDesktopScenario.ps1'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $TigerWinLabRoot $command) -PathType Leaf)) {
        throw "TigerWinLab command not found: $command"
    }
}

$outputRoot = Join-Path $repoRoot "artifacts\lab\$version"
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($DesktopPublishDirectory)) {
    $DesktopPublishDirectory = Join-Path $repoRoot 'artifacts\publish\win-x64-selfcontained'
}
$DesktopPublishDirectory = [IO.Path]::GetFullPath($DesktopPublishDirectory)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $DesktopPublishDirectory.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "DesktopPublishDirectory must remain below '$artifactRoot' because it is rebuilt from scratch."
}
if (Test-Path -LiteralPath $DesktopPublishDirectory) {
    Remove-Item -LiteralPath $DesktopPublishDirectory -Recurse -Force
}
dotnet publish (Join-Path $repoRoot 'src\TigerMarkView\TigerMarkView.csproj') `
    --configuration Release `
    --runtime win-x64 `
    --self-contained true `
    --output $DesktopPublishDirectory `
    -m:1
if ($LASTEXITCODE -ne 0) { throw 'Could not build the self-contained TigerWinLab desktop payload.' }

# The generic installer scenario starts from a clean guest and does not provision dependencies.
# Install the two declared WinGet dependencies first, then deliberately retain that cleanly-known
# state for the immediately following installer scenario.
$prerequisiteScript = @'
$ErrorActionPreference = 'Stop'
$downloads = @(
    @{
        Name = '.NET 10 Desktop Runtime (x64)'
        Uri = 'https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe'
        File = 'windowsdesktop-runtime.exe'
        Arguments = @('/install', '/quiet', '/norestart')
    },
    @{
        Name = 'Microsoft Edge WebView2 Runtime (x64)'
        Uri = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
        File = 'MicrosoftEdgeWebView2RuntimeInstallerX64.exe'
        Arguments = @('/silent', '/install')
    }
)
foreach ($download in $downloads) {
    $target = Join-Path $env:TIGERWINLAB_JOB_WORKSPACE $download.File
    Invoke-WebRequest -Uri $download.Uri -OutFile $target -UseBasicParsing
    $process = Start-Process -FilePath $target -ArgumentList $download.Arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Could not install $($download.Name) (exit $($process.ExitCode))."
    }
}
'@
& (Join-Path $TigerWinLabRoot 'Invoke-TigerWinLabJob.ps1') `
    -Name 'tigermarkview-prerequisites' `
    -Script $prerequisiteScript `
    -Reset `
    -TimeoutMinutes $TimeoutMinutes `
    -OutputRoot (Join-Path $outputRoot 'prerequisites') `
    -ResultPath (Join-Path $outputRoot 'prerequisites.json') | Out-Host
if ($LASTEXITCODE -ne 0) { throw "TigerWinLab prerequisite setup failed with $LASTEXITCODE." }

$installerSpec = [ordered]@{
    schemaVersion = 1
    name = 'tigermarkview'
    product = [ordered]@{
        displayName = 'TigerMarkView'
        appId = '{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}'
        publisher = [string] $versionProps.Project.PropertyGroup.Company
        installRoot = '%ProgramFiles%\TigerMarkView'
    }
    installer = [ordered]@{
        kind = 'innosetup'
        path = $InstallerPath
        version = $version
        silentArguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/ALLUSERS', '/TASKS="addtopath"')
        successExitCodes = @(0)
    }
    expected = [ordered]@{
        files = @(
            'TigerMarkView.exe', 'tiger-mark.exe', 'TigerMarkView.Core.dll', 'TigerMarkView.Pdf.dll',
            'Docs\HELP.md', 'Docs\LICENSE.txt', 'Docs\THIRD-PARTY-NOTICES.md', 'unins000.exe'
        )
        minimumFileCount = 50
        versionFile = 'TigerMarkView.exe'
        machinePathEntries = @('%ProgramFiles%\TigerMarkView')
        # TigerWinLab currently assumes every shortcut has a product-owned parent directory. The
        # installer intentionally puts its one link directly in the shared Programs directory, so
        # that assertion would incorrectly require the Windows directory itself to be absent.
        shortcuts = @()
        smoke = @(
            [ordered]@{
                name = 'version'
                path = 'tiger-mark.exe'
                arguments = @('--version')
                expectedExitCode = 0
                expectedOutputPattern = 'TigerMarkView version {version}'
            },
            [ordered]@{
                name = 'help'
                path = 'tiger-mark.exe'
                arguments = @('--help')
                expectedExitCode = 0
                expectedOutputPattern = 'tiger-mark'
            }
        )
    }
}
if (-not [string]::IsNullOrWhiteSpace($UpgradeFromInstallerPath)) {
    if ([string]::IsNullOrWhiteSpace($UpgradeFromVersion)) { throw '-UpgradeFromVersion is required with an upgrade installer.' }
    $installerSpec.upgradeFrom = [ordered]@{
        path = [IO.Path]::GetFullPath($UpgradeFromInstallerPath)
        version = $UpgradeFromVersion
    }
}
$installerSpecPath = Join-Path $outputRoot 'installer-spec.json'
$installerSpec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $installerSpecPath -Encoding utf8NoBOM

& (Join-Path $TigerWinLabRoot 'Invoke-TigerWinLabInstallerScenario.ps1') `
    -SpecPath $installerSpecPath `
    -SkipReset `
    -TimeoutMinutes $TimeoutMinutes `
    -OutputRoot (Join-Path $outputRoot 'installer') `
    -ResultPath (Join-Path $outputRoot 'installer-result.json') | Out-Host
if ($LASTEXITCODE -ne 0) { throw "TigerWinLab installer scenario failed with $LASTEXITCODE." }

$desktopSpec = [ordered]@{
    schemaVersion = 1
    name = 'tigermarkview'
    application = [ordered]@{
        displayName = 'TigerMarkView'
        path = $DesktopPublishDirectory
        executable = 'TigerMarkView.exe'
        windowTitlePattern = '(?i)TigerMarkView'
        startupTimeoutSeconds = 120
        settleMilliseconds = 5000
        document = [ordered]@{
            fileName = 'tigermarkview-release.md'
            content = "# TigerMarkView $version release verification`n`nRendered inside TigerWinLab.`n"
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

& (Join-Path $TigerWinLabRoot 'Invoke-TigerWinLabDesktopScenario.ps1') `
    -SpecPath $desktopSpecPath `
    -TimeoutMinutes $TimeoutMinutes `
    -OutputRoot (Join-Path $outputRoot 'desktop') `
    -ResultPath (Join-Path $outputRoot 'desktop-result.json') | Out-Host
if ($LASTEXITCODE -ne 0) { throw "TigerWinLab desktop scenario failed with $LASTEXITCODE." }

Write-Host "PASS: TigerMarkView $version installer and desktop scenarios passed in TigerWinLab." -ForegroundColor Green
