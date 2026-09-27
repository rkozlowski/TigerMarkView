#Requires -Version 7.0
<#
    .SYNOPSIS
    Rehearses the release workflow's TigerSetup provisioning in TigerWinLab.

    .DESCRIPTION
    The release workflow runs eng\release-automation\Install-TigerSetup.ps1 on a hosted runner, which
    has no TigerSetup and runs with an elevated administrator token - a state no developer shell
    reproduces. This runs the same script, with the same pinned installer\tigersetup.json, as the
    elevated lab administrator in a clean, online TigerWinLab guest, then has the provisioned builder
    build and verify a small package, which needs the loader and engine installed beside it.

    Run it when installer\tigersetup.json or Install-TigerSetup.ps1 changes. It is not part of the
    release: the release workflow's own run is the step it rehearses.

    .PARAMETER TigerWinLabRoot
    An explicit TigerWinLab working copy. Omit it and the lab is discovered from the TigerAiCore
    configuration named by TigerAiCoreConfig.
#>
[CmdletBinding()]
param(
    [string] $TigerWinLabRoot,
    [string] $Baseline = 'TigerWinLab-Win11-Clean',
    [ValidateRange(5, 60)]
    [int] $TimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'TigerAiCore.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$lab = Assert-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab' -Path $TigerWinLabRoot -RequiredCommand @('Invoke-TigerWinLabJob.ps1')
$outputRoot = Join-Path $repoRoot 'artifacts\lab\tigersetup-provisioning'
$payloadRoot = Join-Path $outputRoot 'payload'
if (Test-Path -LiteralPath $payloadRoot) { Remove-Item -LiteralPath $payloadRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $payloadRoot 'eng\release-automation'), (Join-Path $payloadRoot 'installer') -Force | Out-Null

# The scripts exactly as the workflow runs them, staged with a BOM for Windows PowerShell 5.1.
foreach ($file in 'eng\release-automation\Install-TigerSetup.ps1', 'installer\TigerSetupBuilder.ps1') {
    Get-Content -LiteralPath (Join-Path $repoRoot $file) -Raw -Encoding utf8 |
        Set-Content -LiteralPath (Join-Path $payloadRoot $file) -Encoding utf8BOM -NoNewline
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'installer\tigersetup.json') -Destination (Join-Path $payloadRoot 'installer')

$entry = @'
$ErrorActionPreference = 'Stop'
$directory = 'C:\RunnerTemp\tigersetup'
$output = 'C:\RunnerTemp\github-output.txt'
$null = New-Item -ItemType Directory -Force 'C:\RunnerTemp'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$transcript = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'eng\release-automation\Install-TigerSetup.ps1') -Directory $directory -GitHubOutput $output 2>&1
$provisionExit = $LASTEXITCODE
$transcript | Set-Content -LiteralPath (Join-Path $env:TIGERWINLAB_JOB_ARTIFACTS 'install-tigersetup.log') -Encoding UTF8
$pathLine = @(Get-Content -LiteralPath $output -ErrorAction SilentlyContinue | Where-Object { $_ -like 'path=*' })
$builder = if ($pathLine.Count -eq 1) { $pathLine[0].Substring(5) } else { $null }

$work = 'C:\RunnerTemp\package'
$null = New-Item -ItemType Directory -Force (Join-Path $work 'publish')
Set-Content -LiteralPath (Join-Path $work 'publish\readme.txt') -Value 'rehearsal' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $work 'TigerSetup.toml') -Encoding ASCII -Value @"
[package]
id = "ItTiger.ProvisioningRehearsal"
name = "ProvisioningRehearsal"
version = "1.0.0"
publisher = "IT Tiger"

[[files]]
source = "publish/**"
"@
$buildExit = -1; $verifyExit = -1
if ($builder) {
    & $builder build (Join-Path $work 'TigerSetup.toml') --output (Join-Path $work 'out') --offline --fast 2>&1 | Out-Null
    $buildExit = $LASTEXITCODE
    & $builder verify (Join-Path $work 'out\ProvisioningRehearsal-1.0.0-Setup.exe') 2>&1 | Out-Null
    $verifyExit = $LASTEXITCODE
}
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$checks = @(
    @{ name = 'Elevated administrator token'; code = 'context.elevated'; status = $(if ($elevated) { 'PASS' } else { 'FAIL' }); message = $identity.Name }
    @{ name = 'Install-TigerSetup.ps1 succeeds'; code = 'provision.exit'; status = $(if ($provisionExit -eq 0 -and $builder) { 'PASS' } else { 'FAIL' }); message = "Exit $provisionExit; path output: $builder" }
    @{ name = 'No PATH entry is added'; code = 'provision.path'; status = $(if ($userPath -notlike "*$directory*") { 'PASS' } else { 'FAIL' }); message = "User PATH: $userPath" }
    @{ name = 'The provisioned builder builds and verifies'; code = 'provision.build'; status = $(if ($buildExit -eq 0 -and $verifyExit -eq 0) { 'PASS' } else { 'FAIL' }); message = "build exit $buildExit; verify exit $verifyExit" }
)
$status = if (@($checks | Where-Object { $_.status -ne 'PASS' }).Count -eq 0) { 'PASS' } else { 'FAIL' }
@{ status = $status; phases = @(@{ name = 'provisioning'; status = $status; checks = $checks }) } | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $env:TIGERWINLAB_JOB_RESULT -Encoding UTF8
if ($status -ne 'PASS') { exit 1 }
exit 0
'@
Set-Content -LiteralPath (Join-Path $payloadRoot 'rehearse.ps1') -Value $entry -Encoding utf8BOM

$resultPath = Join-Path $outputRoot 'result.json'
Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
$arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $lab.Path 'Invoke-TigerWinLabJob.ps1'), '-Name', 'tmv-tigersetup-provisioning',
    '-PayloadPath', $payloadRoot, '-EntryScript', 'rehearse.ps1', '-Baseline', $Baseline,
    '-TimeoutMinutes', $TimeoutMinutes, '-OutputRoot', (Join-Path $outputRoot 'job'), '-ResultPath', $resultPath)
$process = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $outputRoot 'lab.stdout.log') -RedirectStandardError (Join-Path $outputRoot 'lab.stderr.log')
if (-not $process.WaitForExit([int] [TimeSpan]::FromMinutes($TimeoutMinutes + 30).TotalMilliseconds)) {
    $process.Kill($true)
    throw 'TigerWinLab did not finish; its job was stopped.'
}
if (-not (Test-Path -LiteralPath $resultPath)) { throw "TigerWinLab exited with $($process.ExitCode) and wrote no result." }
$result = Get-Content -LiteralPath $resultPath -Raw -Encoding utf8 | ConvertFrom-Json
$checks = @()
if ($null -ne $result.PSObject.Properties['result'] -and $null -ne $result.result) { $checks = @($result.result.phases | ForEach-Object { @($_.checks) }) }
foreach ($check in $checks) { Write-Host ("  {0,-4} {1,-24} {2}" -f $check.status, $check.code, $check.message) }
if ($process.ExitCode -ne 0 -or $result.status -ne 'OK' -or $checks.Count -eq 0 -or @($checks | Where-Object { $_.status -ne 'PASS' }).Count -gt 0) {
    Write-Host "FAIL: TigerWinLab status $($result.status), exit $($process.ExitCode): $($result.message)" -ForegroundColor Red
    exit 1
}
Write-Host 'PASS: Install-TigerSetup.ps1 provisions a working pinned builder under an elevated token.' -ForegroundColor Green
exit 0
