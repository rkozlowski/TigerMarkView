[CmdletBinding()]
param(
    [string] $Version,
    [string] $TigerWinLabRoot,
    [ValidateRange(1, 240)]
    [int] $TimeoutMinutes = 45,
    [switch] $SkipLab
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

try {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    [xml] $versionProps = Get-Content -LiteralPath (Join-Path $repoRoot 'Version.props') -Raw
    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = [string] $versionProps.Project.PropertyGroup.Version }
    if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "Invalid version '$Version'." }

    $installerName = "TigerMarkView-$Version-win-x64-setup.exe"
    $releaseRoot = "https://github.com/rkozlowski/TigerMarkView/releases/download/v$Version"
    $validationRoot = Join-Path $repoRoot "artifacts\winget\validation\$Version"
    $publishedRoot = Join-Path $validationRoot 'published'
    New-Item -ItemType Directory -Path $publishedRoot -Force | Out-Null

    $installerPath = Join-Path $publishedRoot $installerName
    $checksumPath = Join-Path $publishedRoot 'SHA256SUMS.txt'
    $artifactManifestPath = Join-Path $publishedRoot 'release-artifacts.json'
    foreach ($name in @($installerName, 'SHA256SUMS.txt', 'release-artifacts.json')) {
        Invoke-WebRequest -Uri "$releaseRoot/$name" -OutFile (Join-Path $publishedRoot $name)
    }

    $publishedHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumLine = @(Get-Content -LiteralPath $checksumPath | Where-Object { $_ -match [regex]::Escape($installerName) })
    if ($checksumLine.Count -ne 1 -or $checksumLine[0] -cne "$publishedHash  $installerName") {
        throw 'The live installer does not match SHA256SUMS.txt.'
    }
    $releaseManifest = Get-Content -LiteralPath $artifactManifestPath -Raw | ConvertFrom-Json
    $entry = @($releaseManifest.artifacts | Where-Object name -CEQ $installerName)
    if ($releaseManifest.releaseVersion -cne $Version -or $entry.Count -ne 1 -or
        [string] $entry[0].sha256 -cne $publishedHash -or
        [long] $entry[0].length -ne (Get-Item -LiteralPath $installerPath).Length) {
        throw 'The live installer does not match release-artifacts.json.'
    }

    $localInstaller = Join-Path $repoRoot "artifacts\installer\$installerName"
    if (Test-Path -LiteralPath $localInstaller -PathType Leaf) {
        $localHash = (Get-FileHash -LiteralPath $localInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($localHash -cne $publishedHash) { throw 'The retained local installer differs from the public release.' }
    }
    else {
        Write-Warning 'No retained local installer was available for the optional fourth-way hash comparison.'
    }

    $manifestDirectory = & (Join-Path $PSScriptRoot 'Prepare-TigerMarkViewWinGet.ps1') `
        -InstallerPath $installerPath `
        -OutputRoot (Join-Path $repoRoot 'artifacts\winget') `
        -ExpectedVersion $Version `
        -InstallerUrl "$releaseRoot/$installerName" `
        -ExpectedInstallerSha256 $publishedHash `
        -Validate | Select-Object -Last 1

    if ($SkipLab) {
        Write-Host "PASS: live asset, checksums, artifact manifest, and WinGet manifests agree for $Version; TigerWinLab was intentionally skipped." -ForegroundColor Green
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($TigerWinLabRoot)) { $TigerWinLabRoot = $env:TIGERWINLAB_ROOT }
    if ([string]::IsNullOrWhiteSpace($TigerWinLabRoot)) {
        $TigerWinLabRoot = Join-Path (Split-Path -Parent $repoRoot) 'TigerWinLab'
    }
    $TigerWinLabRoot = [IO.Path]::GetFullPath($TigerWinLabRoot)
    $labCommand = Join-Path $TigerWinLabRoot 'Invoke-TigerWinLabWinGetScenario.ps1'
    if (-not (Test-Path -LiteralPath $labCommand -PathType Leaf)) {
        throw "TigerWinLab WinGet scenario command not found: $labCommand"
    }

    $spec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tigermarkview.labspec.template.json') -Raw | ConvertFrom-Json
    $spec.package.version = $Version
    $spec.manifestDirectory = [IO.Path]::GetFullPath($manifestDirectory)
    $spec.installer.path = $installerPath
    $spec.installer.expectedUrl = "$releaseRoot/$installerName"
    $specPath = Join-Path $validationRoot 'tigerwinlab-spec.json'
    $spec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $specPath -Encoding utf8NoBOM

    $labResultPath = Join-Path $validationRoot 'tigerwinlab-result.json'
    & $labCommand `
        -SpecPath $specPath `
        -OutputRoot (Join-Path $validationRoot 'tigerwinlab-artifacts') `
        -ResultPath $labResultPath `
        -TimeoutMinutes $TimeoutMinutes `
        -Json | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "TigerWinLab WinGet scenario failed with $LASTEXITCODE." }

    $labResult = Get-Content -LiteralPath $labResultPath -Raw | ConvertFrom-Json
    if ($labResult.status -cne 'OK') { throw "TigerWinLab ended with status '$($labResult.status)'." }
    Write-Host "PASS: ItTiger.TigerMarkView $Version is ready for a manual winget-pkgs submission." -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
