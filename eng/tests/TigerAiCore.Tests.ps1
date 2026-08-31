#Requires -Version 7.0
<#
    .SYNOPSIS
    Covers TigerAiCore resource discovery for TigerMarkView engineering scripts.

    .DESCRIPTION
    The behaviour worth protecting here is refusal. Discovery must resolve a Lab
    from the configured TOML or say why it cannot; it must never reach a lab this
    repository guessed at. These tests therefore run with TigerAiCoreConfig
    removed and a directory laid out exactly like a sibling checkout, and prove
    nothing finds it.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$engineeringRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $engineeringRoot
. (Join-Path $engineeringRoot 'TigerAiCore.ps1')

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('TigerAiCore-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Action,

        [Parameter(Mandatory)]
        [string] $MessagePattern
    )

    try { & $Action }
    catch {
        Assert-True ($_.Exception.Message -match $MessagePattern) `
            "Expected failure matching '$MessagePattern'; received '$($_.Exception.Message)'."
        return
    }

    throw "Expected an exception matching '$MessagePattern'."
}

function New-FakeLab {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [string[]] $Command = @('Invoke-TigerWinLabWinGetScenario.ps1')
    )

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    foreach ($name in $Command) {
        Set-Content -LiteralPath (Join-Path $Path $name) -Value '# fake lab command' -Encoding utf8NoBOM
    }

    return [IO.Path]::GetFullPath($Path)
}

$originalConfiguration = [Environment]::GetEnvironmentVariable('TigerAiCoreConfig')
try {
    # Nothing in this suite may see the maintainer's real configuration; a test that
    # passes only on a configured machine proves nothing about the refusal path.
    $env:TigerAiCoreConfig = ''

    $labPath = New-FakeLab -Path (Join-Path $testRoot 'labs\TigerWinLab') `
        -Command @('Invoke-TigerWinLabWinGetScenario.ps1', 'Invoke-TigerWinLabJob.ps1')
    $toolPath = Join-Path $testRoot 'tools\tiger-mark.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $toolPath) -Force | Out-Null
    Set-Content -LiteralPath $toolPath -Value 'fake tool' -Encoding utf8NoBOM

    $configurationPath = Join-Path $testRoot 'TigerAiCore.toml'
    Set-Content -LiteralPath $configurationPath -Encoding utf8NoBOM -Value @"
# A machine profile in the shape TigerAiCore documents.
core = "$($testRoot.Replace('\', '\\'))"
coder = "$($testRoot.Replace('\', '\\'))\\AI-CODER.md"

[labs.TigerWinLab]
type = "WindowsLab"
path = "$($labPath.Replace('\', '\\'))"

[labs.TigerHyperLab]
type = "HyperVCore"
path = "$($labPath.Replace('\', '\\'))"

[tools.TigerMarkView]
type = 'MarkdownToPdf'
path = '$toolPath'
"@

    # 1. The reader understands the shape TigerAiCore actually writes, including the
    #    literal strings Windows paths are usually quoted with.
    $configuration = Get-TigerAiCoreConfiguration -ConfigurationPath $configurationPath
    Assert-True $configuration.Available 'A configuration file that exists must load.'
    Assert-True ($configuration.Document['labs']['TigerWinLab']['type'] -ceq 'WindowsLab') `
        'A basic string value must be read verbatim.'
    Assert-True ($configuration.Document['tools']['TigerMarkView']['path'] -ceq $toolPath) `
        'A literal string must be read without escape processing.'
    Assert-True ($configuration.Document['coder'] -ceq (Join-Path $testRoot 'AI-CODER.md')) `
        'A basic string must have its backslash escapes resolved.'
    Write-Host 'PASS: the configured TOML subset is read as written'

    # 2. A line the reader cannot understand is a broken machine, not a default.
    $badConfiguration = Join-Path $testRoot 'bad.toml'
    Set-Content -LiteralPath $badConfiguration -Value "core = C:\Projects\TigerAiCore" -Encoding utf8NoBOM
    Assert-Throws -MessagePattern 'not a quoted string' -Action {
        Get-TigerAiCoreConfiguration -ConfigurationPath $badConfiguration
    }
    Write-Host 'PASS: an unreadable configuration line fails loudly'

    # 3. A registered Lab of the expected type, providing the commands the caller
    #    depends on, resolves.
    $lab = Get-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab' -ConfigurationPath $configurationPath `
        -RequiredCommand 'Invoke-TigerWinLabWinGetScenario.ps1'
    Assert-True $lab.Available "A registered lab must resolve; reported '$($lab.Reason)'."
    Assert-True ($lab.Path -ceq $labPath) 'A resolved lab must be the configured path.'
    Assert-True ($lab.Source -match [regex]::Escape($configurationPath)) `
        'A resolved lab must name the configuration it came from.'
    Write-Host 'PASS: a registered lab resolves from the configuration'

    # 4. The registered type is a contract. TigerHyperLab is the VM substrate, and
    #    handing it to a caller that asked for the Windows lab would be wrong even
    #    though the path exists.
    $wrongType = Get-TigerAiCoreLab -Name 'TigerHyperLab' -Type 'WindowsLab' -ConfigurationPath $configurationPath
    Assert-True (-not $wrongType.Available) 'A lab of the wrong type must not resolve.'
    Assert-True ($wrongType.Reason -match "is type 'HyperVCore'") `
        'A type mismatch must say which type was registered.'
    Write-Host 'PASS: a registered lab of the wrong type is refused'

    # 5. A registered lab missing the entry point the caller needs fails here rather
    #    than deep inside a scenario run.
    $missingCommand = Get-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab' -ConfigurationPath $configurationPath `
        -RequiredCommand 'Invoke-TigerWinLabDesktopScenario.ps1'
    Assert-True (-not $missingCommand.Available) 'A lab without the required command must not resolve.'
    Assert-True ($missingCommand.Reason -match 'does not provide') `
        'A missing lab command must be named in the reason.'
    Write-Host 'PASS: a lab missing a required command is refused'

    # 6. An unregistered name is reported against the configuration that was read.
    $unregistered = Get-TigerAiCoreLab -Name 'TigerWpLab' -Type 'WordPressLinuxLab' -ConfigurationPath $configurationPath
    Assert-True (-not $unregistered.Available) 'An unregistered lab must not resolve.'
    Assert-True ($unregistered.Reason -match 'is not registered under \[labs\]') `
        'An unregistered lab must say so.'
    Write-Host 'PASS: an unregistered lab is refused'

    # 7. No configuration means no lab. This is the standalone mode TigerAiCore
    #    describes: report unavailable, continue with repository-local work.
    $unconfigured = Get-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab'
    Assert-True (-not $unconfigured.Available) 'Without TigerAiCoreConfig no lab may resolve.'
    Assert-True ($unconfigured.Reason -match 'TigerAiCoreConfig is not set') `
        'An unconfigured machine must be told which variable is missing.'
    Write-Host 'PASS: an unset TigerAiCoreConfig reports unavailable rather than guessing'

    # 8. The refusal that matters most: a checkout sitting exactly where the old
    #    fallback looked must not be found.
    $siblingRoot = Join-Path $testRoot 'sibling'
    $siblingRepository = Join-Path $siblingRoot 'TigerMarkView'
    New-Item -ItemType Directory -Path $siblingRepository -Force | Out-Null
    $siblingLab = New-FakeLab -Path (Join-Path $siblingRoot 'TigerWinLab')
    $sibling = Get-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab'
    Assert-True (-not $sibling.Available) 'A sibling checkout must never be discovered.'
    Assert-True ($null -eq $sibling.Path) 'An unresolved lab must expose no path.'
    Assert-True (Test-Path -LiteralPath $siblingLab -PathType Container) `
        'The sibling fixture must exist, or this test proves nothing.'
    Write-Host 'PASS: a sibling checkout is never discovered'

    # 9. A per-lab environment variable is not a discovery route either.
    $env:TIGERWINLAB_ROOT = $siblingLab
    try {
        $viaEnvironment = Get-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab'
        Assert-True (-not $viaEnvironment.Available) 'TIGERWINLAB_ROOT must not resolve a lab.'
    }
    finally { Remove-Item Env:TIGERWINLAB_ROOT -ErrorAction SilentlyContinue }
    Write-Host 'PASS: a per-lab environment variable is not a discovery route'

    # 10. An explicit path is a decision, so it wins - and is still proven.
    $explicit = Get-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab' -Path $siblingLab `
        -RequiredCommand 'Invoke-TigerWinLabWinGetScenario.ps1'
    Assert-True $explicit.Available "An explicit lab path must resolve; reported '$($explicit.Reason)'."
    Assert-True ($explicit.Source -ceq 'an explicit path') 'An explicit lab path must be reported as such.'
    $explicitMissing = Get-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab' `
        -Path (Join-Path $testRoot 'no-such-lab')
    Assert-True (-not $explicitMissing.Available) 'An explicit path that does not exist must not resolve.'
    Write-Host 'PASS: an explicit path wins and is still verified'

    # 11. Assert-TigerAiCoreLab is for scripts whose whole run is the lab. Its
    #     failure has to tell a maintainer how the machine declares the lab.
    Assert-Throws -MessagePattern 'TigerAiCoreConfig' -Action {
        Assert-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab'
    }
    Write-Host 'PASS: a required lab fails with configuration guidance'

    # 12. The scripts must not carry a private copy of the rule they just lost.
    foreach ($relativePath in @('eng\lab\Test-TigerMarkViewRelease.ps1', 'eng\winget\WinGetReleaseValidation.ps1')) {
        $text = Get-Content -LiteralPath (Join-Path $repositoryRoot $relativePath) -Raw
        Assert-True ($text -notmatch 'TIGERWINLAB_ROOT') `
            "$relativePath must not read a per-lab environment variable."
        Assert-True ($text -match 'TigerAiCore') `
            "$relativePath must discover its lab through TigerAiCore."
    }
    Write-Host 'PASS: lab-consuming scripts discover through TigerAiCore only'

    Write-Host
    Write-Host 'PASS: TigerAiCore discovery' -ForegroundColor Green
}
finally {
    if ($null -eq $originalConfiguration) { Remove-Item Env:TigerAiCoreConfig -ErrorAction SilentlyContinue }
    else { $env:TigerAiCoreConfig = $originalConfiguration }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
