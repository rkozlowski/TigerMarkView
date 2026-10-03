#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$wingetDirectory = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $wingetDirectory)
$prepareScript = Join-Path $wingetDirectory 'Prepare-TigerMarkViewWinGet.ps1'
[xml] $versionXml = Get-Content -LiteralPath (Join-Path $repositoryRoot 'Version.props') -Raw
$version = [string] $versionXml.Project.PropertyGroup.Version
$pinnedTigerSetup = [string] (Get-Content -LiteralPath (Join-Path $repositoryRoot 'installer\tigersetup.json') -Raw | ConvertFrom-Json).version
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("TigerMarkViewWinGet-tests-" + [Guid]::NewGuid().ToString('N'))
$installerDirectory = Join-Path $testRoot 'installer'
$installerPath = Join-Path $installerDirectory "TigerMarkView-$version-win-x64-setup.exe"
$installerUrl = "https://github.com/rkozlowski/TigerMarkView/releases/download/v$version/TigerMarkView-$version-win-x64-setup.exe"

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Action,

        [Parameter(Mandatory)]
        [string] $MessagePattern
    )

    try {
        try {
            & $Action
        }
        finally {
            # The action is expected to fail, frequently by way of a non-zero native exit code.
            # Clear $LASTEXITCODE so a handled failure cannot become the script's exit status.
            $global:LASTEXITCODE = 0
        }
    }
    catch {
        Assert-True ($_.Exception.Message -match $MessagePattern) `
            "Expected failure matching '$MessagePattern'; received '$($_.Exception.Message)'."
        return
    }

    throw "Expected an exception matching '$MessagePattern'."
}

function Set-FakeWinGetResult {
    param(
        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [int] $ValidateExitCode,

        [Parameter(Mandatory)]
        [string] $LogPath
    )

    $env:TIGERMARKVIEW_TEST_WINGET_VERSION = $Version
    $env:TIGERMARKVIEW_TEST_WINGET_EXIT = [string] $ValidateExitCode
    $env:TIGERMARKVIEW_TEST_WINGET_LOG = $LogPath
    Set-Content -LiteralPath $LogPath -Value '' -Encoding ascii
}

try {
    New-Item -ItemType Directory -Path $installerDirectory -Force | Out-Null
    [IO.File]::WriteAllBytes($installerPath, [byte[]] (0..31))

    # --- Generation: TigerSetup writes the manifests; Prepare pins its inputs and checks its output ---

    # A stand-in for tiger-setup.exe with the command-line shape of the pinned release: --version,
    # `winget prepare <manifest> --installer <file> --output <dir>` writing the three manifests with
    # the URL unresolved, and `winget finalize <dir> --url <url> --installer <file>` filling in the
    # URL and the installer's hash. Every invocation is logged. No network and no real builder, so
    # the suite runs where TigerSetup is not installed: normal CI.
    $fakeTigerSetup = Join-Path $testRoot 'tiger-setup.ps1'
    $fakeTigerSetupLog = Join-Path $testRoot 'tiger-setup.log'
    $fakeTigerSetupSource = @'
$ErrorActionPreference = 'Stop'
$arguments = @($args)
Add-Content -LiteralPath $env:TIGERMARKVIEW_TEST_TIGERSETUP_LOG -Value ($arguments -join ' ')
function Get-Option([string] $Name) { $arguments[[array]::IndexOf($arguments, $Name) + 1] }
if ($arguments[0] -eq '--version') { "tiger-setup $env:TIGERMARKVIEW_TEST_TIGERSETUP_VERSION"; exit 0 }
if ($arguments[0] -eq 'winget' -and $arguments[1] -eq 'prepare') {
    $directory = Get-Option '--output'
    $installerName = [IO.Path]::GetFileName((Get-Option '--installer'))
    $packageVersion = $installerName -replace '^TigerMarkView-(.+)-win-x64-setup\.exe$', '$1'
    $header = '# yaml-language-server: $schema=https://aka.ms/winget-manifest.{0}.1.12.0.schema.json'
    $common = "PackageIdentifier: ItTiger.TigerMarkView`nPackageVersion: $packageVersion`n"
    [IO.File]::WriteAllText((Join-Path $directory 'ItTiger.TigerMarkView.installer.yaml'),
        ($header -f 'installer') + "`n" + $common + "InstallerType: exe`nInstallers:`n- Architecture: x64`n" +
        "  Scope: user`n  InstallerUrl: <unresolved>`n  InstallerSha256: <unresolved>`n" +
        "ManifestType: installer`nManifestVersion: 1.12.0`n")
    $privacy = if ($env:TIGERMARKVIEW_TEST_TIGERSETUP_PRIVACY_URL) { "PrivacyUrl: $env:TIGERMARKVIEW_TEST_TIGERSETUP_PRIVACY_URL`n" } else { '' }
    if ($env:TIGERMARKVIEW_TEST_TIGERSETUP_LICENSE_URL) { $privacy += "LicenseUrl: $env:TIGERMARKVIEW_TEST_TIGERSETUP_LICENSE_URL`n" }
    if ($env:TIGERMARKVIEW_TEST_TIGERSETUP_RELEASE_NOTES_URL) { $privacy += "ReleaseNotesUrl: $env:TIGERMARKVIEW_TEST_TIGERSETUP_RELEASE_NOTES_URL`n" }
    [IO.File]::WriteAllText((Join-Path $directory 'ItTiger.TigerMarkView.locale.en-US.yaml'),
        ($header -f 'defaultLocale') + "`n" + $common + "PackageLocale: en-US`n" + $privacy +
        "ManifestType: defaultLocale`nManifestVersion: 1.12.0`n")
    [IO.File]::WriteAllText((Join-Path $directory 'ItTiger.TigerMarkView.yaml'),
        ($header -f 'version') + "`n" + $common + "DefaultLocale: en-US`nManifestType: version`nManifestVersion: 1.12.0`n")
    exit 0
}
if ($arguments[0] -eq 'winget' -and $arguments[1] -eq 'finalize') {
    $url = if ($env:TIGERMARKVIEW_TEST_TIGERSETUP_URL) { $env:TIGERMARKVIEW_TEST_TIGERSETUP_URL } else { Get-Option '--url' }
    $hash = (Get-FileHash -LiteralPath (Get-Option '--installer') -Algorithm SHA256).Hash
    $path = Join-Path $arguments[2] 'ItTiger.TigerMarkView.installer.yaml'
    $text = [IO.File]::ReadAllText($path).Replace('InstallerUrl: <unresolved>', "InstallerUrl: $url")
    [IO.File]::WriteAllText($path, $text.Replace('InstallerSha256: <unresolved>', "InstallerSha256: $hash"))
    exit 0
}
exit 2
'@
    Set-Content -LiteralPath $fakeTigerSetup -Value $fakeTigerSetupSource -Encoding utf8NoBOM
    $env:TIGERMARKVIEW_TEST_TIGERSETUP_LOG = $fakeTigerSetupLog
    $env:TIGERMARKVIEW_TEST_TIGERSETUP_VERSION = $pinnedTigerSetup
    $env:TIGERMARKVIEW_TEST_TIGERSETUP_URL = ''
    # What [winget] privacy_url in installer\TigerSetup.toml makes TigerSetup write: the declared
    # value verbatim, {version} token included. Prepare must turn it into this version's asset URL.
    $privacyTemplateLine = @(Get-Content -LiteralPath (Join-Path $repositoryRoot 'installer\TigerSetup.toml') |
        Where-Object { $_ -match '^\s*privacy_url\s*=\s*"[^"]+"' })
    Assert-True ($privacyTemplateLine.Count -eq 1) 'installer\TigerSetup.toml must declare exactly one privacy_url.'
    $null = $privacyTemplateLine[0] -match '"(?<value>[^"]+)"'
    $privacyTemplate = $Matches.value
    $privacyUrl = "https://github.com/rkozlowski/TigerMarkView/releases/download/v$version/PRIVACY.md"
    $env:TIGERMARKVIEW_TEST_TIGERSETUP_PRIVACY_URL = $privacyTemplate
    # The same for license_url and release_notes_url: verbatim, {version} included.
    foreach ($key in 'license_url', 'release_notes_url') {
        $line = @(Get-Content -LiteralPath (Join-Path $repositoryRoot 'installer\TigerSetup.toml') | Where-Object { $_ -match "^\s*$key\s*=\s*`"[^`"]+`"" })
        Assert-True ($line.Count -eq 1) "installer\TigerSetup.toml must declare exactly one $key."
        $null = $line[0] -match '"(?<value>[^"]+)"'
        Set-Item -Path ('Env:TIGERMARKVIEW_TEST_TIGERSETUP_' + $key.ToUpperInvariant()) -Value $Matches.value
    }

    $defaultOutput = Join-Path $testRoot 'default'
    & $prepareScript `
        -TigerSetupPath $fakeTigerSetup `
        -InstallerPath $installerPath `
        -OutputRoot $defaultOutput `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl | Out-Host
    $invocations = @(Get-Content -LiteralPath $fakeTigerSetupLog)
    $manifestPath = Join-Path $repositoryRoot 'installer\TigerSetup.toml'
    $manifestDirectory = Join-Path $defaultOutput "manifests\i\ItTiger\TigerMarkView\$version"
    Assert-True ($invocations -ccontains "winget prepare $manifestPath --installer $installerPath --output $manifestDirectory") `
        "Prepare must run tiger-setup winget prepare on installer\TigerSetup.toml; it ran: $($invocations -join ' | ')"
    Assert-True ($invocations -ccontains "winget finalize $manifestDirectory --url $installerUrl --installer $installerPath") `
        'Prepare must finalize the set with the immutable release URL and the same installer.'
    Write-Host 'PASS: generation is tiger-setup winget prepare and finalize over the pinned inputs'

    $manifestFiles = @(Get-ChildItem -LiteralPath $manifestDirectory -File)
    Assert-True ($manifestFiles.Count -eq 3) 'Expected exactly three generated WinGet manifests.'
    Write-Host 'PASS: generation leaves exactly the three submission manifests'

    $env:TIGERMARKVIEW_TEST_TIGERSETUP_VERSION = '0.0.1'
    Assert-Throws -MessagePattern 'pins' -Action {
        & $prepareScript -TigerSetupPath $fakeTigerSetup -InstallerPath $installerPath `
            -OutputRoot (Join-Path $testRoot 'unpinned') -ExpectedVersion $version | Out-Host
    }
    $env:TIGERMARKVIEW_TEST_TIGERSETUP_VERSION = $pinnedTigerSetup
    Write-Host 'PASS: a builder other than the pinned TigerSetup release is refused'

    $env:TIGERMARKVIEW_TEST_TIGERSETUP_URL = 'https://example.com/elsewhere.exe'
    Assert-Throws -MessagePattern 'release URL' -Action {
        & $prepareScript -TigerSetupPath $fakeTigerSetup -InstallerPath $installerPath `
            -OutputRoot (Join-Path $testRoot 'wrong-url') -ExpectedVersion $version | Out-Host
    }
    $env:TIGERMARKVIEW_TEST_TIGERSETUP_URL = ''
    Write-Host 'PASS: a generated set that does not declare the release URL is refused'

    # A PrivacyUrl that is missing, mutable, or the statement of anything but this release is refused:
    # the default branch, a tag's repository file, another release's asset, another document of this
    # release, the latest release, or a website policy.
    $foreignPrivacyUrls = @(
        ''
        'https://www.ittiger.net/privacy'
        'https://github.com/rkozlowski/TigerMarkView/blob/main/docs/PRIVACY.md'
        "https://github.com/rkozlowski/TigerMarkView/blob/v$version/docs/PRIVACY.md"
        'https://github.com/rkozlowski/TigerMarkView/releases/download/v0.11.0/PRIVACY.md'
        'https://github.com/rkozlowski/TigerMarkView/releases/download/v0.11.1/PRIVACY.md'
        "https://github.com/rkozlowski/TigerMarkView/releases/download/v$version/HELP.md"
        'https://github.com/rkozlowski/TigerMarkView/releases/latest/download/PRIVACY.md'
    )
    foreach ($generatedPrivacyUrl in $foreignPrivacyUrls) {
        $env:TIGERMARKVIEW_TEST_TIGERSETUP_PRIVACY_URL = $generatedPrivacyUrl
        Assert-Throws -MessagePattern 'PrivacyUrl' -Action {
            & $prepareScript -TigerSetupPath $fakeTigerSetup -InstallerPath $installerPath `
                -OutputRoot (Join-Path $testRoot 'wrong-privacy') -ExpectedVersion $version | Out-Host
        }
    }
    $env:TIGERMARKVIEW_TEST_TIGERSETUP_PRIVACY_URL = $privacyTemplate
    Write-Host 'PASS: a generated PrivacyUrl that is not this release''s PRIVACY.md asset is refused'

    $fakeWinGet = Join-Path $testRoot 'winget-test.cmd'
    $fakeWinGetContent = @'
@echo off
echo %*>>"%TIGERMARKVIEW_TEST_WINGET_LOG%"
if "%~1"=="--version" (
  echo v%TIGERMARKVIEW_TEST_WINGET_VERSION%
  exit /b 0
)
if "%~1"=="validate" (
  echo Fake WinGet validation result %TIGERMARKVIEW_TEST_WINGET_EXIT%
  exit /b %TIGERMARKVIEW_TEST_WINGET_EXIT%
)
exit /b 2
'@
    Set-Content -LiteralPath $fakeWinGet -Value $fakeWinGetContent -Encoding ascii

    $legacyClientLog = Join-Path $testRoot 'legacy-client-winget.log'
    Set-FakeWinGetResult -Version '1.11.510' -ValidateExitCode 0 -LogPath $legacyClientLog
    & $prepareScript `
        -TigerSetupPath $fakeTigerSetup `
        -InstallerPath $installerPath `
        -OutputRoot (Join-Path $testRoot 'legacy-client') `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -WinGetPath $fakeWinGet `
        -Validate | Out-Host
    $legacyClientInvocations = @(Get-Content -LiteralPath $legacyClientLog | Where-Object { $_ })
    Assert-True ($legacyClientInvocations.Count -eq 1 -and $legacyClientInvocations[0] -like 'validate *') `
        'The client version must not be probed; winget validate alone decides whether the manifests are acceptable.'
    Write-Host 'PASS: an older WinGet client reaches validation instead of being rejected up front'

    $successLog = Join-Path $testRoot 'success-winget.log'
    Set-FakeWinGetResult -Version '1.29.290' -ValidateExitCode 0 -LogPath $successLog
    & $prepareScript `
        -TigerSetupPath $fakeTigerSetup `
        -InstallerPath $installerPath `
        -OutputRoot (Join-Path $testRoot 'validation-success') `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -WinGetPath $fakeWinGet `
        -Validate | Out-Host
    $successInvocation = @(Get-Content -LiteralPath $successLog | Where-Object { $_ -like 'validate *' })
    Assert-True ($successInvocation.Count -eq 1 -and
        $successInvocation[0] -match '--disable-interactivity') `
        'Manifest validation must invoke WinGet exactly once with --disable-interactivity.'
    Write-Host 'PASS: supported WinGet validation is non-interactive'

    $warningLog = Join-Path $testRoot 'warning-winget.log'
    Set-FakeWinGetResult -Version '1.29.290' -ValidateExitCode -1978335192 -LogPath $warningLog
    & $prepareScript `
        -TigerSetupPath $fakeTigerSetup `
        -InstallerPath $installerPath `
        -OutputRoot (Join-Path $testRoot 'validation-warning') `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -WinGetPath $fakeWinGet `
        -Validate | Out-Host
    Write-Host 'PASS: only WinGet warning-success HRESULT 0x8A150028 is accepted'

    $failureLog = Join-Path $testRoot 'failure-winget.log'
    Set-FakeWinGetResult -Version '1.29.290' -ValidateExitCode -1978335191 -LogPath $failureLog
    Assert-Throws -MessagePattern '0x8A150029' -Action {
        & $prepareScript `
            -TigerSetupPath $fakeTigerSetup `
            -InstallerPath $installerPath `
            -OutputRoot (Join-Path $testRoot 'validation-failure') `
            -ExpectedVersion $version `
            -InstallerUrl $installerUrl `
            -WinGetPath $fakeWinGet `
            -Validate | Out-Host
    }
    Write-Host 'PASS: genuine WinGet manifest-validation failure HRESULT remains fatal'

    # --- The submission set: exactly three files, and a digest that means something ---

    . (Join-Path $wingetDirectory 'TigerMarkViewWinGet.ps1')
    $assertScript = Join-Path $wingetDirectory 'Assert-TigerMarkViewWinGetSubmission.ps1'
    $release = Get-TigerMarkViewWinGetRelease -Version $version
    $storedDirectory = Join-Path $defaultOutput $release.manifestRelativePath

    $stored = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $storedDirectory -Version $version
    Assert-True ($stored.documents.Count -eq 3) 'A submission set is exactly three documents.'
    Assert-True (
        (@($stored.documents | ForEach-Object Name) -join ',') -ceq ($release.manifestFileNames -join ',')) `
        'The submission documents must be the three expected manifests in submission order.'
    Assert-True ($stored.installer.installerUrl -ceq $release.installerUrl) `
        'The installer manifest must declare the immutable release asset URL.'
    Assert-True ($release.privacyUrl -ceq $privacyUrl -and $stored.locale.privacyUrl -ceq $privacyUrl) `
        'The default-locale manifest must declare this version''s PRIVACY.md release asset as PrivacyUrl.'
    $storedLocaleLines = @(Get-Content -LiteralPath (Join-Path $storedDirectory $release.manifestFileNames[1]))
    Assert-True (@($storedLocaleLines | Where-Object { $_ -ceq "PrivacyUrl: $privacyUrl" }).Count -eq 1 -and
        @($storedLocaleLines | Where-Object { $_ -match '\{version\}' }).Count -eq 0) `
        'The {version} token must be resolved in the one PrivacyUrl line, as a plain scalar, and nowhere else left behind.'
    Assert-True ($stored.locale.licenseUrl -ceq "https://github.com/rkozlowski/TigerMarkView/blob/v$version/LICENSE" -and
        $stored.locale.releaseNotesUrl -ceq "https://github.com/rkozlowski/TigerMarkView/releases/tag/v$version" -and
        $release.licenseUrl -ceq $stored.locale.licenseUrl -and $release.releaseNotesUrl -ceq $stored.locale.releaseNotesUrl) `
        'The default-locale manifest must declare the licence at this version''s tag and this version''s release page.'
    Write-Host 'PASS: a prepared directory reads back as the three-file submission set'

    # The rule itself, independently of generation: only the version's own release asset passes.
    Assert-True ($null -eq (Get-TigerMarkViewPrivacyStatementUrlProblem -Url $privacyUrl -Version $version)) `
        'The version''s own PRIVACY.md release asset is its privacy statement.'
    foreach ($case in @(
            @{ url = 'https://github.com/rkozlowski/TigerMarkView/blob/main/docs/PRIVACY.md'; reason = 'can change after the release' }
            @{ url = 'https://github.com/rkozlowski/TigerMarkView/raw/main/docs/PRIVACY.md'; reason = 'can change after the release' }
            @{ url = 'https://github.com/rkozlowski/TigerMarkView/releases/download/v0.11.0/PRIVACY.md'; reason = 'release v0\.11\.0, not' }
            @{ url = 'https://github.com/rkozlowski/TigerMarkView/releases/download/v0.11.1/PRIVACY.md'; reason = 'release v0\.11\.1, not' }
            @{ url = "https://github.com/rkozlowski/TigerMarkView/releases/download/v$version/HELP.md"; reason = "'HELP\.md', not the release's PRIVACY\.md" }
            @{ url = 'https://github.com/rkozlowski/TigerMarkView/releases/latest/download/PRIVACY.md'; reason = 'whichever release is latest' }
            @{ url = 'https://www.ittiger.net/privacy'; reason = 'is not the PRIVACY\.md asset' }
            @{ url = ''; reason = 'no privacy statement URL' })) {
        $problem = Get-TigerMarkViewPrivacyStatementUrlProblem -Url $case.url -Version $version
        Assert-True ($null -ne $problem -and $problem -match $case.reason) `
            "'$($case.url)' must be refused as '$($case.reason)'; the rule said '$problem'."
    }
    Write-Host 'PASS: the privacy-statement rule accepts only the version''s own PRIVACY.md release asset'

    # After publication: what PrivacyUrl serves must be the bytes both release records name and the
    # release commit's docs/PRIVACY.md. A repository with one commit stands in for the release commit.
    $privacyRepository = Join-Path $testRoot 'privacy-source'
    New-Item -ItemType Directory -Path (Join-Path $privacyRepository 'docs') -Force | Out-Null
    $committedPrivacy = Join-Path $privacyRepository 'docs\PRIVACY.md'
    [IO.File]::WriteAllText($committedPrivacy, "# TigerMarkView privacy statement`n`nŻółw: local data.`n",
        [Text.UTF8Encoding]::new($false))
    $previousNative = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        foreach ($gitArguments in @(
                @('init', '--quiet', '-b', 'main'), @('config', 'core.autocrlf', 'false'), @('add', '-A'),
                @('-c', 'user.email=test@example.com', '-c', 'user.name=Test', 'commit', '--quiet', '-m', 'release'))) {
            & git -C $privacyRepository @gitArguments | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "git $($gitArguments -join ' ') failed in the privacy fixture." }
        }
        $privacyCommit = (& git -C $privacyRepository rev-parse HEAD | Out-String).Trim()
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $previousNative
        $global:LASTEXITCODE = 0
    }
    function New-PublishedPrivacy([string] $Name, [string] $Text, [switch] $OmitSum, [switch] $OmitRecord) {
        $root = Join-Path $testRoot $Name
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'PRIVACY.md'
        [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $artifacts = @([ordered]@{ name = 'PRIVACY.md'; kind = 'PrivacyStatement'; length = (Get-Item $path).Length; sha256 = $hash })
        if ($OmitRecord) { $artifacts = @() }
        [ordered]@{ schemaVersion = 1; releaseVersion = $version; artifacts = $artifacts } | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath (Join-Path $root 'release-artifacts.json') -Encoding utf8NoBOM
        $sums = if ($OmitSum) { "$('0' * 64)  other.exe" } else { "$hash  PRIVACY.md" }
        Set-Content -LiteralPath (Join-Path $root 'SHA256SUMS.txt') -Value $sums -Encoding utf8NoBOM
        $root
    }
    $committedText = [IO.File]::ReadAllText($committedPrivacy)
    $checkPublished = {
        param([string] $Root)
        @(Get-TigerMarkViewPublishedPrivacyStatementProblem -PublishedRoot $Root -Version $version `
            -RepositoryRoot $privacyRepository -Commit $privacyCommit)
    }
    $published = @(& $checkPublished (New-PublishedPrivacy 'published-good' $committedText))
    Assert-True ($published.Count -eq 0) "The released statement passes; the check said: $($published -join '; ')"
    $absent = Join-Path $testRoot 'published-absent'
    New-Item -ItemType Directory -Path $absent -Force | Out-Null
    Assert-True (((& $checkPublished $absent) -join '; ') -match 'was not published') 'A release without PRIVACY.md is refused.'
    Assert-True (((& $checkPublished (New-PublishedPrivacy 'published-unsummed' $committedText -OmitSum)) -join '; ') -match 'SHA256SUMS\.txt') `
        'A statement SHA256SUMS.txt does not list is refused.'
    Assert-True (((& $checkPublished (New-PublishedPrivacy 'published-unrecorded' $committedText -OmitRecord)) -join '; ') -match 'release-artifacts\.json') `
        'A statement release-artifacts.json does not record is refused.'
    $rewrittenProblems = @(& $checkPublished (New-PublishedPrivacy 'published-rewritten' $committedText.Replace("`n", "`r`n")))
    Assert-True ($rewrittenProblems.Count -eq 1 -and $rewrittenProblems[0] -match "not the release commit's docs/PRIVACY\.md") `
        'A statement whose bytes differ from the release commit''s is refused even when both records agree with it.'
    Assert-True ((@(Get-TigerMarkViewPublishedPrivacyStatementProblem -PublishedRoot (Join-Path $testRoot 'published-good') `
            -Version $version -RepositoryRoot $privacyRepository -Commit ('e' * 40)) -join '; ') -match 'not available') `
        'A release commit the repository does not have is reported, never assumed to match.'
    Write-Host 'PASS: the published PRIVACY.md must be the recorded bytes and the release commit''s docs/PRIVACY.md'

    $extraFile = Join-Path $storedDirectory 'notes.txt'
    Set-Content -LiteralPath $extraFile -Value 'not part of the submission' -Encoding utf8NoBOM
    Assert-Throws -MessagePattern 'only the three' -Action {
        Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $storedDirectory -Version $version
    }
    Remove-Item -LiteralPath $extraFile -Force
    Write-Host 'PASS: an extra file disqualifies the directory as a submission set'

    $bomDirectory = Join-Path $testRoot 'bom'
    New-Item -ItemType Directory -Path $bomDirectory -Force | Out-Null
    foreach ($document in $stored.documents) {
        Copy-Item -LiteralPath $document.path -Destination (Join-Path $bomDirectory $document.name)
    }
    $bomTarget = Join-Path $bomDirectory $release.manifestFileNames[2]
    [IO.File]::WriteAllBytes(
        $bomTarget,
        (@([byte] 0xEF, [byte] 0xBB, [byte] 0xBF) + [IO.File]::ReadAllBytes($bomTarget)))
    Assert-Throws -MessagePattern 'byte-order mark' -Action {
        Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $bomDirectory -Version $version
    }
    Write-Host 'PASS: a byte-order mark disqualifies the directory as a submission set'

    $missingDirectory = Join-Path $testRoot 'missing'
    New-Item -ItemType Directory -Path $missingDirectory -Force | Out-Null
    Copy-Item -LiteralPath $stored.documents[0].path -Destination $missingDirectory
    Assert-Throws -MessagePattern 'incomplete' -Action {
        Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $missingDirectory -Version $version
    }
    Write-Host 'PASS: an incomplete directory disqualifies the directory as a submission set'

    # The digest is the transfer proof, so it must be stable across a copy and must
    # notice a single changed byte in any of the three files.
    $copyDirectory = Join-Path $testRoot 'copy'
    New-Item -ItemType Directory -Path $copyDirectory -Force | Out-Null
    foreach ($document in $stored.documents) {
        Copy-Item -LiteralPath $document.path -Destination (Join-Path $copyDirectory $document.name)
    }
    $copied = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $copyDirectory -Version $version
    Assert-True ($copied.digest -ceq $stored.digest) 'Copying a submission set must preserve its digest.'
    $tamperTarget = Join-Path $copyDirectory $release.manifestFileNames[1]
    Add-Content -LiteralPath $tamperTarget -Value '# an edit nothing validated' -Encoding utf8NoBOM
    $tampered = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $copyDirectory -Version $version
    Assert-True ($tampered.digest -cne $stored.digest) 'An edited manifest must change the submission digest.'
    Write-Host 'PASS: the submission digest survives a copy and detects an edit'

    # --- The release's WinGet archive ---

    # The archive is the same set in another container: flat, exactly the three manifests, and the
    # same submission digest as the directory it was packed from.
    $archiveRoot = Join-Path $testRoot 'archive'
    New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
    $archivePath = Join-Path $archiveRoot $release.wingetArchiveFileName
    $archive = New-TigerMarkViewWinGetArchive -ManifestDirectory $storedDirectory -Version $version -Path $archivePath
    Assert-True ($release.wingetArchiveFileName -ceq "TigerMarkView-$version-WinGet.zip") 'The archive is named after the release version.'
    Assert-True ($archive.digest -ceq $stored.digest) 'The archive holds the set it was packed from.'
    Assert-True ((Read-TigerMarkViewWinGetArchive -Path $archivePath -Version $version).digest -ceq $stored.digest) `
        'Reading the archive back reproduces the submission digest.'
    Assert-Throws -MessagePattern 'already exists|being used|exists' -Action {
        New-TigerMarkViewWinGetArchive -ManifestDirectory $storedDirectory -Version $version -Path $archivePath
    }
    Assert-Throws -MessagePattern 'must be named' -Action {
        New-TigerMarkViewWinGetArchive -ManifestDirectory $storedDirectory -Version $version -Path (Join-Path $archiveRoot 'winget.zip')
    }

    Add-Type -AssemblyName System.IO.Compression
    function New-TestArchive([string] $Name, [string[]] $Entries) {
        $path = Join-Path $archiveRoot $Name
        $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($entryName in $Entries) {
                $source = Join-Path $storedDirectory ([IO.Path]::GetFileName($entryName))
                if (Test-Path -LiteralPath $source) { $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $source, $entryName) }
                else { $null = $zip.CreateEntry($entryName) }
            }
        }
        finally { $zip.Dispose() }
        $path
    }
    $extra = New-TestArchive 'extra.zip' (@($release.manifestFileNames) + 'README.txt')
    $short = New-TestArchive 'short.zip' @($release.manifestFileNames[0], $release.manifestFileNames[1])
    $nested = New-TestArchive 'nested.zip' @($release.manifestFileNames | ForEach-Object { "manifests/$_" })
    foreach ($bad in $extra, $short, $nested) {
        Assert-Throws -MessagePattern 'exactly the three submission manifests' -Action {
            Read-TigerMarkViewWinGetArchive -Path $bad -Version $version
        }
    }
    Write-Host 'PASS: the release archive holds exactly the sealed set, and anything else is refused'

    # --- The sealing gate ---

    $installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
    $sealOutput = Join-Path $testRoot 'github-output.txt'
    Set-Content -LiteralPath $sealOutput -Value '' -Encoding utf8NoBOM
    $sealedDigest = & $assertScript `
        -ManifestDirectory $storedDirectory `
        -Version $version `
        -ExpectedInstallerSha256 $installerHash `
        -GitHubOutput $sealOutput | Select-Object -Last 1
    Assert-True ($sealedDigest -ceq $stored.digest) 'The sealing gate must report the stored submission digest.'
    Assert-True (@(Get-Content -LiteralPath $sealOutput) -contains "submission_sha256=$($stored.digest)") `
        'The sealing gate must publish submission_sha256 to GITHUB_OUTPUT.'
    Write-Host 'PASS: sealing a validated set records its digest for the publication job'

    Assert-Throws -MessagePattern 'hashes to' -Action {
        & $assertScript `
            -ManifestDirectory $storedDirectory `
            -Version $version `
            -ExpectedInstallerSha256 ('0' * 64) | Out-Host
    }
    Write-Host 'PASS: a manifest that does not describe the installer is refused'

    # The release workflow passes the installer itself rather than a hash it computed
    # in YAML, so the sealed set is tied to the release bytes with nothing in between.
    $sealedFromInstaller = & $assertScript `
        -ManifestDirectory $storedDirectory `
        -Version $version `
        -InstallerPath $installerPath | Select-Object -Last 1
    Assert-True ($sealedFromInstaller -ceq $stored.digest) `
        'Sealing against the installer file must reach the same submission digest.'

    $otherInstaller = Join-Path $testRoot ([IO.Path]::GetFileName($installerPath))
    [IO.File]::WriteAllBytes($otherInstaller, [byte[]] (1..32))
    Assert-Throws -MessagePattern 'hashes to' -Action {
        & $assertScript `
            -ManifestDirectory $storedDirectory `
            -Version $version `
            -InstallerPath $otherInstaller | Out-Host
    }
    Write-Host 'PASS: sealing hashes the installer it is given and refuses a different one'

    $noPrivacyDirectory = Join-Path $testRoot 'no-privacy'
    New-Item -ItemType Directory -Path $noPrivacyDirectory -Force | Out-Null
    foreach ($document in $stored.documents) {
        Copy-Item -LiteralPath $document.path -Destination (Join-Path $noPrivacyDirectory $document.name)
    }
    $noPrivacyLocale = Join-Path $noPrivacyDirectory $release.manifestFileNames[1]
    [IO.File]::WriteAllText($noPrivacyLocale,
        (([IO.File]::ReadAllText($noPrivacyLocale) -split "`n" | Where-Object { $_ -notmatch '^PrivacyUrl:' }) -join "`n"))
    Assert-Throws -MessagePattern 'PrivacyUrl' -Action {
        & $assertScript -ManifestDirectory $noPrivacyDirectory -Version $version -InstallerPath $installerPath | Out-Host
    }
    Write-Host 'PASS: sealing refuses a set whose default-locale manifest lacks PrivacyUrl'

    [IO.File]::WriteAllText($noPrivacyLocale, [IO.File]::ReadAllText($noPrivacyLocale).TrimEnd("`n") +
        "`nPrivacyUrl: https://github.com/rkozlowski/TigerMarkView/blob/main/docs/PRIVACY.md`n")
    Assert-Throws -MessagePattern 'PrivacyUrl.*can change after the release' -Action {
        & $assertScript -ManifestDirectory $noPrivacyDirectory -Version $version -InstallerPath $installerPath | Out-Host
    }
    Write-Host 'PASS: sealing refuses a set whose PrivacyUrl is the default branch''s mutable copy'

    Assert-Throws -MessagePattern 'not the same manifests' -Action {
        & $assertScript `
            -ManifestDirectory $copyDirectory `
            -Version $version `
            -ExpectedDigest $stored.digest | Out-Host
    }
    Write-Host 'PASS: a set that changed after validation is refused at the transfer check'

    # --- Workflow shape: what is uploaded is what was validated ---

    $releaseWorkflow = Get-Content -LiteralPath (
        Join-Path $repositoryRoot '.github\workflows\release.yml') -Raw

    $uploadMatch = [regex]::Match(
        $releaseWorkflow,
        '(?ms)^      - name: Upload the exact validated WinGet submission set\r?\n' +
            '.*?^          name: (?<name>[^\r\n]+)\r?\n' +
            '          path: (?<path>[^\r\n]+)\r?$')
    Assert-True $uploadMatch.Success 'The release workflow must upload the validated WinGet submission set.'
    $artifactName = $uploadMatch.Groups['name'].Value
    Assert-True ($artifactName.Contains('${{ inputs.version }}') -and $artifactName.Contains('${{ github.sha }}')) `
        'The WinGet artifact name must be version- and commit-specific.'

    $uploadPath = $uploadMatch.Groups['path'].Value.Replace('${{ inputs.version }}', $version)
    $sealMatch = [regex]::Match(
        $releaseWorkflow,
        '(?ms)^      - name: Seal and record the WinGet submission set\r?\n' +
            '.*?-ManifestDirectory "(?<path>[^"]+)"')
    Assert-True $sealMatch.Success 'The release workflow must seal the generated submission set.'
    $sealPath = $sealMatch.Groups['path'].Value.Replace('$env:RELEASE_VERSION', $version)
    Assert-True ($sealPath -ceq $uploadPath) `
        "The sealed directory '$sealPath' and the uploaded directory '$uploadPath' must be the same directory."
    Write-Host 'PASS: the release workflow uploads exactly the directory it sealed'

    # Resolve the workflow's upload path against a workspace holding a freshly generated
    # set, exactly as the runner would, and prove the resolved files are the validated
    # bytes and nothing else.
    $workspace = Join-Path $testRoot 'workspace'
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    & $prepareScript `
        -TigerSetupPath $fakeTigerSetup `
        -InstallerPath $installerPath `
        -OutputRoot (Join-Path $workspace 'artifacts\winget') `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl | Out-Host
    $workspaceDirectory = Join-Path $workspace ($uploadPath -replace '/', '\')
    $validated = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $workspaceDirectory -Version $version

    $uploaded = @(Get-ChildItem -LiteralPath $workspaceDirectory -Force)
    Assert-True ($uploaded.Count -eq 3) `
        "The uploaded artifact must contain exactly three files; the upload path resolves to $($uploaded.Count)."
    foreach ($document in $validated.documents) {
        $uploadedBytes = [IO.File]::ReadAllBytes((Join-Path $workspaceDirectory $document.name))
        $storedBytes = [IO.File]::ReadAllBytes((Join-Path $storedDirectory $document.name))
        Assert-True ([Linq.Enumerable]::SequenceEqual($uploadedBytes, $storedBytes)) `
            "$($document.name) is not byte-identical between the validated set and the uploaded artifact."
    }
    Assert-True ($validated.digest -ceq $stored.digest) `
        'Generation must be deterministic: two runs over the same installer must seal to one digest.'
    Write-Host 'PASS: the uploaded WinGet artifact is byte-for-byte the validated submission set'

    Assert-True ($releaseWorkflow.Contains('-ExpectedDigest $env:EXPECTED_SUBMISSION_SHA256')) `
        'The publication job must re-verify the downloaded submission set against the recorded digest.'
    Assert-True ($releaseWorkflow -cmatch '(?m)^      submission_sha256: \$\{\{ steps\.submission\.outputs\.submission_sha256 \}\}\r?$') `
        'The validation job must publish the sealed submission digest to the publication job.'
    Write-Host 'PASS: the publication job proves the artifact it downloaded is the set that was validated'

    # --- The post-release gate consumes the sealed workflow artifact ---

    # The gate itself lives in the dot-sourceable library, so the submission
    # orchestrator can require its result without a child process. The command
    # script is only a thin wrapper around that one function.
    $gateScript = Get-Content -LiteralPath (Join-Path $wingetDirectory 'WinGetReleaseValidation.ps1') -Raw
    $gateCommand = Get-Content -LiteralPath (Join-Path $wingetDirectory 'Test-TigerMarkViewWinGet.ps1') -Raw
    Assert-True ($gateCommand.Contains('Invoke-TigerMarkViewWinGetReleaseValidation')) `
        'The post-release gate command must run the shared validation function.'
    foreach ($text in @($gateScript, $gateCommand)) {
        Assert-True ($text -notmatch 'GH_TOKEN|GITHUB_TOKEN|auth token|-GitHubToken') `
            'The post-release gate must not read, forward, or log a token.'
    }

    Assert-True ($gateScript.Contains('Get-TigerMarkViewWinGetSealedSubmission')) `
        'The post-release gate must obtain the submission set from the sealed workflow artifact.'
    Assert-True ($gateScript.Contains('$submission = $acquired.submission')) `
        'The post-release gate must validate the set it acquired, not one it found on disk.'
    Assert-True (-not $gateScript.Contains('Get-TigerMarkViewWinGetManifestDirectory')) `
        'The post-release gate must not resolve a submission set under the local generation root.'
    Assert-True (-not $gateScript.Contains('artifacts\winget\manifests')) `
        'The post-release gate must never read artifacts\winget\manifests.'
    Assert-True ($gateScript -cnotmatch '(?m)^\s*\[string\] \$ManifestDirectory,') `
        'The post-release gate must not accept a -ManifestDirectory override that could point at a stale set.'
    Write-Host 'PASS: the post-release gate has no path to a locally generated manifest set'

    # The gate may regenerate only to compare. Proving that means proving there is one
    # generator invocation and that it writes to the throwaway directory, not the set
    # that gets submitted.
    $prepareInvocations = [regex]::Matches(
        $gateScript,
        [regex]::Escape("& (Join-Path `$PSScriptRoot 'Prepare-TigerMarkViewWinGet.ps1')"))
    Assert-True ($prepareInvocations.Count -eq 1) `
        "The post-release gate must invoke the generator exactly once; it invokes it $($prepareInvocations.Count) times."
    $invocationStart = $prepareInvocations[0].Index
    $invocationTail = $gateScript.Substring(
        $invocationStart,
        [Math]::Min(400, $gateScript.Length - $invocationStart))
    Assert-True ($invocationTail.Contains('-OutputRoot $regeneratedRoot')) `
        'Regeneration in the post-release gate must target the throwaway directory.'
    Assert-True ($gateScript.Contains("`$regeneratedRoot = Join-Path `$validationRoot 'regenerated'")) `
        'The throwaway regeneration directory must sit under the per-version validation directory.'
    Assert-True ($gateScript.Contains("Join-Path `$acquired.releaseRoot 'validation'")) `
        'Validation output must be retained beside the sealed submission set.'
    Assert-True ($gateScript.Contains('Invoke-TigerMarkViewWinGetValidation -ManifestDirectory $submission.directory')) `
        'The post-release gate must run winget validate against the sealed submission set.'
    Assert-True ($gateScript.Contains('$spec.manifestDirectory = $submission.directory')) `
        'TigerWinLab must be handed the exact sealed submission set.'
    Write-Host 'PASS: the post-release gate validates, labs, and submits the sealed manifests'

    # --- The authoritative post-release set is the sealed workflow artifact ---

    # A fake GitHub, so artifact selection, digest verification, and every refusal are
    # exercised without a network and without a token. The shapes returned are the ones
    # the real endpoints return; only the transport is replaced.
    $releaseCommit = 'a' * 40
    $otherCommit = 'b' * 40
    $annotatedTagSha = 'c' * 40

    function New-FakeGitHubClient {
        param(
            [Parameter(Mandatory)]
            [object[]] $Artifacts,

            [string] $ArchiveSource,

            [switch] $DraftRelease
        )

        $responses = [ordered]@{
            '*/releases/tags/*' = [pscustomobject]@{
                name = "TigerMarkView $version"
                draft = [bool] $DraftRelease
                published_at = '2026-08-28T19:41:48Z'
                html_url = "https://github.com/rkozlowski/TigerMarkView/releases/tag/v$version"
            }
            '*/git/ref/tags/*' = [pscustomobject]@{
                object = [pscustomobject]@{ sha = $annotatedTagSha; type = 'tag' }
            }
            '*/git/tags/*' = [pscustomobject]@{
                object = [pscustomobject]@{ sha = $releaseCommit; type = 'commit' }
            }
            '*/actions/artifacts*' = [pscustomobject]@{
                total_count = $Artifacts.Count
                artifacts = $Artifacts
            }
        }

        [pscustomobject][ordered]@{
            owner = 'rkozlowski'
            name = 'TigerMarkView'
            slug = 'rkozlowski/TigerMarkView'
            apiRoot = 'repos/rkozlowski/TigerMarkView'
            invoke = {
                param([Parameter(Mandatory)][string] $Path)

                foreach ($entry in $responses.GetEnumerator()) {
                    if ($Path -like $entry.Key) {
                        if ($null -eq $entry.Value) { throw "HTTP 404 for '$Path'." }
                        return $entry.Value
                    }
                }
                throw "The fake GitHub client has no response for '$Path'."
            }.GetNewClosure()
            download = {
                param(
                    [Parameter(Mandatory)][string] $Path,
                    [Parameter(Mandatory)][string] $OutFile
                )

                if ([string]::IsNullOrWhiteSpace($ArchiveSource)) {
                    throw "The fake GitHub client was asked to download '$Path' with no archive."
                }
                Copy-Item -LiteralPath $ArchiveSource -Destination $OutFile -Force
            }.GetNewClosure()
        }
    }

    function New-FakeArtifactRecord {
        param(
            [Parameter(Mandatory)][string] $Name,
            [Parameter(Mandatory)][string] $Commit,
            [Parameter(Mandatory)][long] $Id,
            [string] $Digest,
            [switch] $Expired
        )

        [pscustomobject]@{
            id = $Id
            name = $Name
            size_in_bytes = 1905L
            digest = if ([string]::IsNullOrWhiteSpace($Digest)) { $null } else { "sha256:$Digest" }
            expired = [bool] $Expired
            created_at = '2026-08-28T16:35:21Z'
            workflow_run = [pscustomobject]@{ id = 33190536269L; head_sha = $Commit }
        }
    }

    function New-SubmissionArchive {
        param(
            [Parameter(Mandatory)][string] $ManifestDirectory,
            [Parameter(Mandatory)][string] $ArchivePath
        )

        if (Test-Path -LiteralPath $ArchivePath) { Remove-Item -LiteralPath $ArchivePath -Force }
        Compress-Archive -Path (Join-Path $ManifestDirectory '*') -DestinationPath $ArchivePath
        [pscustomobject]@{
            path = $ArchivePath
            sha256 = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    # The set the workflow would have sealed: generated from the installer CI built.
    $sealedInstallerDirectory = Join-Path $testRoot 'sealed-installer'
    New-Item -ItemType Directory -Path $sealedInstallerDirectory -Force | Out-Null
    $sealedInstallerPath = Join-Path $sealedInstallerDirectory "TigerMarkView-$version-win-x64-setup.exe"
    [IO.File]::WriteAllBytes($sealedInstallerPath, [byte[]] (100..179))
    $sealedInstallerHash = (Get-FileHash -LiteralPath $sealedInstallerPath -Algorithm SHA256).Hash
    $sealedOutput = Join-Path $testRoot 'sealed'
    & $prepareScript `
        -TigerSetupPath $fakeTigerSetup `
        -InstallerPath $sealedInstallerPath `
        -OutputRoot $sealedOutput `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl | Out-Host
    $sealedDirectory = Join-Path $sealedOutput $release.manifestRelativePath
    $sealedSet = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $sealedDirectory -Version $version
    $sealedArchive = New-SubmissionArchive -ManifestDirectory $sealedDirectory `
        -ArchivePath (Join-Path $testRoot 'sealed.zip')

    $artifactName = Get-TigerMarkViewWinGetWorkflowArtifactName -Version $version -Commit $releaseCommit
    Assert-True ($artifactName -ceq "TigerMarkView-WinGet-$version-$releaseCommit") `
        'The sealed artifact name must be TigerMarkView-WinGet-<version>-<commit>.'

    # A repository root that already holds a stale locally generated set for the same
    # version, declaring a hash no release ever published. This is the 0.8.1 failure.
    $fakeRepoRoot = Join-Path $testRoot 'consumer'
    New-Item -ItemType Directory -Path $fakeRepoRoot -Force | Out-Null
    $staleRoot = Join-Path $fakeRepoRoot 'artifacts\winget'
    & $prepareScript `
        -TigerSetupPath $fakeTigerSetup `
        -InstallerPath $installerPath `
        -OutputRoot $staleRoot `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl | Out-Host
    $staleDirectory = Join-Path $staleRoot $release.manifestRelativePath
    $staleSet = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $staleDirectory -Version $version
    Assert-True ($staleSet.installer.installerSha256 -cne $sealedSet.installer.installerSha256) `
        'The stale local set must declare a different installer hash from the sealed set.'

    $goodArtifact = New-FakeArtifactRecord -Name $artifactName -Commit $releaseCommit -Id 9693585025 `
        -Digest $sealedArchive.sha256
    $client = New-FakeGitHubClient -Artifacts @($goodArtifact) -ArchiveSource $sealedArchive.path
    $acquired = Get-TigerMarkViewWinGetSealedSubmission `
        -RepositoryRoot $fakeRepoRoot -Version $version -Client $client

    $expectedSubmissionDirectory = Get-TigerMarkViewWinGetSealedSubmissionDirectory `
        -RepositoryRoot $fakeRepoRoot -Version $version
    Assert-True ($acquired.submission.directory -ceq [IO.Path]::GetFullPath($expectedSubmissionDirectory)) `
        "The sealed set must be extracted to '$expectedSubmissionDirectory'."
    Assert-True ($acquired.submission.digest -ceq $sealedSet.digest) `
        'The extracted set must be byte-for-byte the set the workflow sealed.'
    Assert-True ($acquired.submission.installer.installerSha256 -ceq $sealedInstallerHash) `
        'The extracted set must declare the sealed installer hash, not the local one.'
    Assert-True ($acquired.provenance.commit -ceq $releaseCommit -and
        $acquired.provenance.artifactName -ceq $artifactName -and
        $acquired.provenance.archiveSha256 -ceq $sealedArchive.sha256) `
        'The provenance record must name the artifact, its commit, and the verified archive digest.'
    Assert-True (Test-Path -LiteralPath (Join-Path $acquired.releaseRoot 'submission.json') -PathType Leaf) `
        'The provenance record must be written beside the sealed submission set.'
    Write-Host 'PASS: the sealed workflow artifact is downloaded, verified, and extracted'

    # The stale set is the trap this whole change exists to avoid: it must neither be
    # read nor altered, and the authoritative set must not be inside artifacts\winget.
    $staleAfter = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $staleDirectory -Version $version
    Assert-True ($staleAfter.digest -ceq $staleSet.digest) `
        'Post-release acquisition must leave a stale local manifest set untouched.'
    Assert-True ($acquired.submission.digest -cne $staleSet.digest) `
        'Post-release validation must not resolve to the stale local manifest set.'
    Assert-True (-not $acquired.submission.directory.StartsWith(
            [IO.Path]::GetFullPath((Join-Path $fakeRepoRoot 'artifacts\winget\')),
            [StringComparison]::OrdinalIgnoreCase)) `
        'The authoritative set must not live under artifacts\winget, where local generation writes.'
    Write-Host 'PASS: a stale locally generated set cannot become the post-release submission'

    # Selection is by version and commit, never by recency. A run for another commit and
    # a run for another version are both present, and neither may be chosen.
    $decoyName = Get-TigerMarkViewWinGetWorkflowArtifactName -Version $version -Commit $otherCommit
    $decoyArtifacts = @(
        New-FakeArtifactRecord -Name $decoyName -Commit $otherCommit -Id 1 -Digest ('0' * 64)
        New-FakeArtifactRecord -Name "TigerMarkView-WinGet-9.9.9-$releaseCommit" -Commit $releaseCommit `
            -Id 2 -Digest ('0' * 64)
        $goodArtifact
    )
    $selecting = New-FakeGitHubClient -Artifacts $decoyArtifacts -ArchiveSource $sealedArchive.path
    $tagged = Resolve-TigerMarkViewWinGetReleaseCommit -Client $selecting -Version $version
    Assert-True ($tagged.commit -ceq $releaseCommit) `
        'An annotated release tag must be dereferenced to the commit the workflow built.'
    $selected = Find-TigerMarkViewWinGetWorkflowArtifact -Client $selecting -Version $version `
        -Commit $tagged.commit
    Assert-True ($selected.id -eq 9693585025 -and $selected.name -ceq $artifactName) `
        'Artifact selection must match both the version in the name and the run''s head commit.'
    Write-Host 'PASS: the workflow artifact is selected by version and release commit'

    $missing = New-FakeGitHubClient -Artifacts @($decoyArtifacts[0], $decoyArtifacts[1]) `
        -ArchiveSource $sealedArchive.path
    Assert-Throws -MessagePattern 'No GitHub Actions artifact named' -Action {
        Get-TigerMarkViewWinGetSealedSubmission `
            -RepositoryRoot (Join-Path $testRoot 'missing-consumer') -Version $version -Client $missing
    }
    Write-Host 'PASS: an absent workflow artifact fails instead of falling back'

    $expiredClient = New-FakeGitHubClient -ArchiveSource $sealedArchive.path -Artifacts @(
        New-FakeArtifactRecord -Name $artifactName -Commit $releaseCommit -Id 3 `
            -Digest $sealedArchive.sha256 -Expired)
    Assert-Throws -MessagePattern 'has expired' -Action {
        Get-TigerMarkViewWinGetSealedSubmission `
            -RepositoryRoot (Join-Path $testRoot 'expired-consumer') -Version $version -Client $expiredClient
    }
    Write-Host 'PASS: an expired workflow artifact fails instead of falling back'

    $draftClient = New-FakeGitHubClient -Artifacts @($goodArtifact) -ArchiveSource $sealedArchive.path `
        -DraftRelease
    Assert-Throws -MessagePattern 'still a draft' -Action {
        Get-TigerMarkViewWinGetSealedSubmission `
            -RepositoryRoot (Join-Path $testRoot 'draft-consumer') -Version $version -Client $draftClient
    }
    Write-Host 'PASS: an unpublished release fails before any manifest is read'

    # A download that does not reproduce the digest GitHub sealed is never extracted.
    $staleArchive = New-SubmissionArchive -ManifestDirectory $staleDirectory `
        -ArchivePath (Join-Path $testRoot 'stale.zip')
    $wrongDigestClient = New-FakeGitHubClient -Artifacts @($goodArtifact) -ArchiveSource $staleArchive.path
    $wrongDigestRoot = Join-Path $testRoot 'wrong-digest-consumer'
    Assert-Throws -MessagePattern 'not the same bytes' -Action {
        Get-TigerMarkViewWinGetSealedSubmission `
            -RepositoryRoot $wrongDigestRoot -Version $version -Client $wrongDigestClient
    }
    Assert-True (-not (Test-Path -LiteralPath (Get-TigerMarkViewWinGetSealedSubmissionDirectory `
            -RepositoryRoot $wrongDigestRoot -Version $version))) `
        'An archive that fails the digest check must never be extracted into the submission directory.'
    Write-Host 'PASS: an archive that is not the sealed bytes is refused before extraction'

    Assert-Throws -MessagePattern 'not the same manifests' -Action {
        Get-TigerMarkViewWinGetSealedSubmission `
            -RepositoryRoot (Join-Path $testRoot 'digest-consumer') -Version $version -Client $client `
            -ExpectedSubmissionDigest ('0' * 64)
    }
    Write-Host 'PASS: a sealed set that does not reproduce the recorded submission digest is refused'

    # A hand-supplied archive is a route to the same bytes, not a weaker check.
    $suppliedRoot = Join-Path $testRoot 'supplied-consumer'
    $offline = New-FakeGitHubClient -Artifacts @($goodArtifact)
    $supplied = Get-TigerMarkViewWinGetSealedSubmission -RepositoryRoot $suppliedRoot -Version $version `
        -Client $offline -ArchivePath $sealedArchive.path
    Assert-True ($supplied.submission.digest -ceq $sealedSet.digest) `
        'A supplied archive that matches the recorded digest yields the sealed set.'
    Assert-Throws -MessagePattern 'not the same bytes' -Action {
        Get-TigerMarkViewWinGetSealedSubmission -RepositoryRoot (Join-Path $testRoot 'supplied-bad') `
            -Version $version -Client $offline -ArchivePath $staleArchive.path
    }
    Write-Host 'PASS: a supplied archive is verified against the same recorded digest'

    # --- Every GitHub read goes through the authenticated gh session ---

    # The repository client is a face on the shared gh adapter, so the whole release
    # chain has one authentication contract. The paths it asks for must be gh api
    # paths, and no token may appear anywhere in the invocation.
    $recordedGhArgs = [Collections.Generic.List[object]]::new()
    $recordingCli = New-TigerMarkViewGitHubCli -Invoker {
        param([string[]] $GhArgs)
        $recordedGhArgs.Add($GhArgs)
        [pscustomobject]@{ ExitCode = 0; StdOut = '{"login":"octocat"}'; StdErr = '' }
    }.GetNewClosure() -Downloader {
        param([string[]] $GhArgs, [string] $OutFile)
        $recordedGhArgs.Add($GhArgs)
        [IO.File]::WriteAllBytes($OutFile, [byte[]] (1, 2, 3))
        [pscustomobject]@{ ExitCode = 0; StdErr = '' }
    }.GetNewClosure()
    $ghBacked = New-TigerMarkViewGitHubClient -Cli $recordingCli `
        -RepositoryUrl 'https://github.com/rkozlowski/TigerMarkView'
    Assert-True ($ghBacked.apiRoot -ceq 'repos/rkozlowski/TigerMarkView') `
        'The client addresses GitHub by gh api path, not by absolute URL.'
    $null = & $ghBacked.invoke "$($ghBacked.apiRoot)/releases/tags/v$version"
    & $ghBacked.download "$($ghBacked.apiRoot)/actions/artifacts/1/zip" (Join-Path $testRoot 'gh-download.bin')
    Assert-True (@($recordedGhArgs).Count -eq 2) 'Both the read and the download reached the session.'
    foreach ($invocation in $recordedGhArgs) {
        Assert-True ($invocation[0] -ceq 'api') 'Every GitHub call is a gh api call.'
        Assert-True (@($invocation | Where-Object { $_ -match 'ghp_|github_pat_|token' }).Count -eq 0) `
            'No token ever appears in a gh invocation.'
    }
    $libraryText = Get-Content -LiteralPath (Join-Path $wingetDirectory 'TigerMarkViewWinGet.ps1') -Raw
    Assert-True ($libraryText -notmatch 'GH_TOKEN|GITHUB_TOKEN|auth token|-GitHubToken') `
        'The WinGet library never reads, forwards, or logs a token.'
    Write-Host 'PASS: WinGet GitHub reads go through the shared gh session with no token route'

    # --- Provenance-bound reuse of a retained sealed set ---

    # A rerun after an interruption should not re-download what is already proven,
    # and must never reuse a directory whose provenance no longer matches GitHub.
    function New-CountingClient {
        param(
            [Parameter(Mandatory)][object[]] $Artifacts,
            [Parameter(Mandatory)][string] $ArchiveSource,
            [Parameter(Mandatory)][ref] $Counter
        )
        $inner = New-FakeGitHubClient -Artifacts $Artifacts -ArchiveSource $ArchiveSource
        $innerDownload = $inner.download
        [pscustomobject][ordered]@{
            owner = $inner.owner
            name = $inner.name
            slug = $inner.slug
            apiRoot = $inner.apiRoot
            invoke = $inner.invoke
            download = {
                param(
                    [Parameter(Mandatory)][string] $Path,
                    [Parameter(Mandatory)][string] $OutFile
                )
                $Counter.Value++
                & $innerDownload $Path $OutFile
            }.GetNewClosure()
        }
    }

    $downloads = 0
    $counting = New-CountingClient -Artifacts @($goodArtifact) -ArchiveSource $sealedArchive.path `
        -Counter ([ref] $downloads)
    $reused = Get-TigerMarkViewWinGetSealedSubmission -RepositoryRoot $fakeRepoRoot -Version $version -Client $counting
    Assert-True ($downloads -eq 0) 'A rerun whose provenance still binds must not re-download the artifact.'
    Assert-True ($reused.submission.digest -ceq $sealedSet.digest) 'The reused set is still the sealed set.'
    Assert-True ($reused.provenance.archiveSource -match 'provenance-bound') `
        'The provenance record says the set was reused rather than downloaded.'

    $forced = Get-TigerMarkViewWinGetSealedSubmission -RepositoryRoot $fakeRepoRoot -Version $version `
        -Client $counting -Force
    Assert-True ($downloads -eq 1) '-Force always re-downloads.'
    Assert-True ($forced.submission.digest -ceq $sealedSet.digest) 'A forced re-download yields the same sealed set.'

    # A different sealed artifact for the same version and commit is a different
    # binding, so the retained copy is not a cache hit for it.
    $rerunArtifact = New-FakeArtifactRecord -Name $artifactName -Commit $releaseCommit -Id 424242 `
        -Digest $sealedArchive.sha256
    $rebound = New-CountingClient -Artifacts @($rerunArtifact) -ArchiveSource $sealedArchive.path `
        -Counter ([ref] $downloads)
    $reacquired = Get-TigerMarkViewWinGetSealedSubmission -RepositoryRoot $fakeRepoRoot -Version $version `
        -Client $rebound
    Assert-True ($reacquired.provenance.archiveSource -notmatch 'provenance-bound') `
        'A changed artifact id invalidates the retained set rather than being reused.'
    Assert-True ($reacquired.provenance.artifactId -eq 424242) `
        'The rewritten provenance record names the artifact that was actually verified.'

    # A retained set whose bytes have moved on since the record was written is not a
    # cache hit either; the sealed archive is re-verified and re-extracted over it.
    $tamperedPath = Join-Path $reused.submission.directory $release.manifestFileNames[2]
    Add-Content -LiteralPath $tamperedPath -Value '# tampered' -Encoding utf8NoBOM
    $tamperedClient = New-CountingClient -Artifacts @($rerunArtifact) -ArchiveSource $sealedArchive.path `
        -Counter ([ref] $downloads)
    $restored = Get-TigerMarkViewWinGetSealedSubmission -RepositoryRoot $fakeRepoRoot -Version $version `
        -Client $tamperedClient
    Assert-True ($restored.provenance.archiveSource -notmatch 'provenance-bound') `
        'A retained set that no longer hashes to its record is not reused.'
    Assert-True ($restored.submission.digest -ceq $sealedSet.digest) `
        'Re-extracting the verified archive restores the sealed bytes.'
    Write-Host 'PASS: a retained sealed set is reused only while its whole provenance still binds'

    # The published installer is what the sealed manifests must describe. A release whose
    # asset hashes to something else fails the same seal the workflow ran.
    Assert-Throws -MessagePattern 'hashes to' -Action {
        & $assertScript `
            -ManifestDirectory $acquired.submission.directory `
            -Version $version `
            -ExpectedInstallerSha256 (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash |
            Out-Host
    }
    $null = & $assertScript `
        -ManifestDirectory $acquired.submission.directory `
        -Version $version `
        -ExpectedInstallerSha256 $sealedInstallerHash
    Write-Host 'PASS: the sealed set is accepted only against the installer it actually hashes'

    # Reproducibility is a comparison, and a regeneration from a different installer must
    # not be able to pass as the sealed set.
    $regenerated = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $staleDirectory -Version $version
    Assert-True ($regenerated.digest -cne $acquired.submission.digest) `
        'A regenerated set built from a different installer must not share the sealed digest.'
    Assert-True ($gateScript.Contains('$regenerated.digest -cne $submission.digest')) `
        'The post-release gate must fail reproducibility when the regenerated set differs from the sealed set.'
    Write-Host 'PASS: a regenerated set that differs from the sealed set fails reproducibility'

}
finally {
    Remove-Item Env:TIGERMARKVIEW_TEST_WINGET_VERSION -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_WINGET_EXIT -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_WINGET_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_TIGERSETUP_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_TIGERSETUP_VERSION -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_TIGERSETUP_URL -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_TIGERSETUP_PRIVACY_URL -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_TIGERSETUP_LICENSE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_TIGERSETUP_RELEASE_NOTES_URL -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
