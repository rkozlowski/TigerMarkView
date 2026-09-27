#Requires -Version 7.0
<#
    .SYNOPSIS
    Proves in TigerWinLab that hostile Markdown cannot run or exfiltrate from the viewer or tiger-mark.

    .DESCRIPTION
    Publishes self-contained TigerMarkView and tiger-mark, then runs eng/lab/active-content/accept.ps1
    as a TigerWinLab -Desktop job. The guest opens active-content/hostile.md in the real viewer and
    converts it with the real tiger-mark while a loopback request logger records every request, and
    asserts that passive images load (remote and local), that no active construct reaches the network,
    that document script cannot message the host while the shell's own script still can, and that the
    viewer and PDF conversion make the same requests.

    The guest runs with its network adapter disconnected: the loopback logger is the only reachable
    endpoint, so nothing the hostile document tries can leave the lab either.

    .PARAMETER TigerWinLabRoot
    An explicit TigerWinLab working copy. Omit it and the lab is discovered from the TigerAiCore
    configuration named by TigerAiCoreConfig; there is no sibling-checkout or environment fallback.

    .PARAMETER Baseline
    The TigerWinLab baseline. Windows 11 ships the Evergreen WebView2 Runtime, and the application is
    published self-contained, so a clean baseline needs no prerequisites.
#>
[CmdletBinding()]
param(
    [string] $TigerWinLabRoot,
    [string] $Baseline = 'TigerWinLab-Win11-Clean',
    [ValidateRange(5, 120)]
    [int] $TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$env:AVALONIA_TELEMETRY_OPTOUT = '1'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'TigerAiCore.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$lab = Assert-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab' -Path $TigerWinLabRoot -RequiredCommand @(
    'Invoke-TigerWinLabJob.ps1'
)
Write-Host "TigerWinLab resolved from $($lab.Source): $($lab.Path)"

$outputRoot = Join-Path $repoRoot 'artifacts\lab\active-content'
$publishRoot = Join-Path $outputRoot 'publish'
$payloadRoot = Join-Path $outputRoot 'payload'
foreach ($directory in @($publishRoot, $payloadRoot)) {
    $resolvedDirectory = [IO.Path]::GetFullPath($directory)
    if (-not $resolvedDirectory.StartsWith([IO.Path]::GetFullPath($outputRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear output outside $outputRoot."
    }
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

# One tree holding both programs, as the installer ships them; self-contained because the clean
# guest has no .NET runtime.
foreach ($project in @('src\TigerMarkView\TigerMarkView.csproj', 'src\TigerMarkView.Cli\TigerMarkView.Cli.csproj', 'eng\lab\active-content\probe\ActiveContentProbe.csproj', 'eng\lab\active-content\lifecycle\LifecycleProbe.csproj')) {
    dotnet publish (Join-Path $repoRoot $project) --configuration Release --runtime win-x64 --self-contained true `
        --output $publishRoot -m:1 -nologo -v q
    if ($LASTEXITCODE -ne 0) { throw "Could not publish $project for the lab payload." }
}

Compress-Archive -Path (Join-Path $publishRoot '*') -DestinationPath (Join-Path $payloadRoot 'app.zip')
foreach ($file in @('accept.ps1', 'hostile.md', 'shares.md', 'code.md')) {
    # The guest uses Windows PowerShell 5.1, which otherwise reads BOM-less UTF-8 as ANSI.
    Get-Content -LiteralPath (Join-Path $PSScriptRoot "active-content\$file") -Raw -Encoding utf8 |
        Set-Content -LiteralPath (Join-Path $payloadRoot $file) -Encoding utf8BOM -NoNewline
}

$env:TMV_ACCEPTANCE_SCRIPT = Join-Path $payloadRoot 'accept.ps1'
try {
    powershell.exe -NoProfile -NonInteractive -Command '$tokens = $null; $parseErrors = $null; [System.Management.Automation.Language.Parser]::ParseFile($env:TMV_ACCEPTANCE_SCRIPT, [ref]$tokens, [ref]$parseErrors) | Out-Null; if ($parseErrors.Count) { $parseErrors | Out-String | Write-Error; exit 1 }'
    if ($LASTEXITCODE -ne 0) { throw 'The guest acceptance script does not parse in Windows PowerShell 5.1.' }
}
finally { Remove-Item Env:TMV_ACCEPTANCE_SCRIPT }

$resultPath = Join-Path $outputRoot 'result.json'
if (Test-Path -LiteralPath $resultPath) { Remove-Item -LiteralPath $resultPath -Force }

$labArguments = @(
    '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $lab.Path 'Invoke-TigerWinLabJob.ps1'),
    '-Name', 'tigermarkview-active-content',
    '-PayloadPath', $payloadRoot,
    '-EntryScript', 'accept.ps1',
    '-Desktop',
    '-Baseline', $Baseline,
    '-NetworkState', 'offline',
    '-TimeoutMinutes', $TimeoutMinutes,
    '-OutputRoot', (Join-Path $outputRoot 'job'),
    '-ResultPath', $resultPath
)

# A child process, so the lab's exit is a result; the outer bound leaves room for the lab's own
# teardown and baseline restore after its timeout has already fired.
$process = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $labArguments -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $outputRoot 'lab.stdout.log') -RedirectStandardError (Join-Path $outputRoot 'lab.stderr.log')
$outerTimeout = [TimeSpan]::FromMinutes($TimeoutMinutes + 30)
if (-not $process.WaitForExit([int] $outerTimeout.TotalMilliseconds)) {
    $process.Kill($true)
    throw "TigerWinLab did not finish within $($outerTimeout.TotalMinutes) minutes; its job was stopped."
}
$labExit = $process.ExitCode

# Exit codes: 0 OK, 1 failed, 2 the VM could not be leased, 3 timeout. A missing or unreadable
# result is a failure whatever the exit code says.
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    Get-Content -LiteralPath (Join-Path $outputRoot 'lab.stderr.log') -ErrorAction SilentlyContinue | Write-Host
    throw "TigerWinLab exited with $labExit and wrote no result to $resultPath."
}
$result = Get-Content -LiteralPath $resultPath -Raw -Encoding utf8 | ConvertFrom-Json

$phases = @()
if ($null -ne $result.PSObject.Properties['result'] -and $null -ne $result.result -and
    $null -ne $result.result.PSObject.Properties['phases']) {
    $phases = @($result.result.phases)
}
foreach ($phase in $phases) {
    Write-Host ''
    Write-Host "[$($phase.status)] $($phase.name)"
    foreach ($check in @($phase.checks)) {
        Write-Host ("  {0,-4} {1,-24} {2}" -f $check.status, $check.code, $check.message)
    }
}
Write-Host ''
Write-Host "Evidence: $(Join-Path $outputRoot 'job')"

$failedChecks = @($phases | ForEach-Object { @($_.checks) } | Where-Object { $_.status -ne 'PASS' })
if ($labExit -ne 0 -or $result.status -ne 'OK' -or $phases.Count -eq 0 -or $failedChecks.Count -gt 0) {
    Write-Host "FAIL: TigerWinLab status $($result.status), exit $labExit, $($failedChecks.Count) failed check(s): $($result.message)" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: active content is inert in the TigerMarkView viewer and tiger-mark ($Baseline)." -ForegroundColor Green
exit 0
