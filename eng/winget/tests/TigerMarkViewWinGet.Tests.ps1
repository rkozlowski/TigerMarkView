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
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("TigerMarkViewWinGet-tests-" + [Guid]::NewGuid().ToString('N'))
$installerDirectory = Join-Path $testRoot 'installer'
$installerPath = Join-Path $installerDirectory "TigerMarkView-$version-win-x64-setup.exe"
$installerUrl = "https://github.com/rkozlowski/TigerMarkView/releases/download/v$version/TigerMarkView-$version-win-x64-setup.exe"
$productCode = [regex]::Escape("'{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}_is1'")

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

function Invoke-WorkflowValidationStep {
    param(
        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $WinGetPath
    )

    # Reproduce how GitHub Actions runs a 'shell: pwsh' step: the runner writes the step body
    # to a script that starts with the stop preference and ends with 'exit $LASTEXITCODE',
    # then dot-sources that file from a fresh pwsh process. Running the real thing is the only
    # way to prove that an accepted WinGet warning leaves no native exit state behind.
    $stepScript = Join-Path $testRoot ('step-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    $stepBody = @"
`$ErrorActionPreference = 'stop'
./eng/winget/Prepare-TigerMarkViewWinGet.ps1 ``
  -InstallerPath '$installerPath' ``
  -OutputRoot '$OutputRoot' ``
  -ExpectedVersion '$version' ``
  -InstallerUrl '$installerUrl' ``
  -WinGetPath '$WinGetPath' ``
  -Validate | Out-Host
if ((Test-Path -LiteralPath variable:\LASTEXITCODE)) { exit `$LASTEXITCODE }
"@
    Set-Content -LiteralPath $stepScript -Value $stepBody -Encoding utf8NoBOM

    $pwsh = (Get-Process -Id $PID).Path
    # The child process is expected to fail in the negative case; its exit code is the
    # assertion, not an error for this runner to raise.
    $PSNativeCommandUseErrorActionPreference = $false
    Push-Location -LiteralPath $repositoryRoot
    try {
        & $pwsh -NoProfile -NoLogo -Command ". '$stepScript'" | Out-Host
        $stepExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
        $global:LASTEXITCODE = 0
    }

    return $stepExitCode
}

function Get-InstallerManifest {
    param(
        [Parameter(Mandatory)]
        [string] $OutputRoot
    )

    Get-Content -LiteralPath (
        Join-Path $OutputRoot "manifests\i\ItTiger\TigerMarkView\$version\ItTiger.TigerMarkView.installer.yaml") -Raw
}

function Assert-AppsAndFeaturesBlocks {
    param(
        [Parameter(Mandatory)]
        [string] $Manifest,

        [string] $ExpectedDisplayVersion
    )

    $displayVersionLine = if ([string]::IsNullOrEmpty($ExpectedDisplayVersion)) {
        ''
    }
    else {
        "    DisplayVersion: $([regex]::Escape($ExpectedDisplayVersion))\r?\n"
    }
    $pattern = "(?m)^  AppsAndFeaturesEntries:\r?\n" +
        "  - DisplayName: TigerMarkView\r?\n" +
        "    Publisher: IT Tiger\r?\n" +
        $displayVersionLine +
        "    ProductCode: $productCode\r?\n" +
        '    InstallerType: inno\r?$'
    $matches = [regex]::Matches($Manifest, $pattern)
    Assert-True ($matches.Count -eq 2) `
        "Expected two correctly indented AppsAndFeaturesEntries blocks; found $($matches.Count)."
}

try {
    New-Item -ItemType Directory -Path $installerDirectory -Force | Out-Null
    [IO.File]::WriteAllBytes($installerPath, [byte[]] (0..31))

    $defaultOutput = Join-Path $testRoot 'default'
    & $prepareScript `
        -InstallerPath $installerPath `
        -OutputRoot $defaultOutput `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl
    $defaultManifest = Get-InstallerManifest -OutputRoot $defaultOutput
    Assert-True ($defaultManifest -cnotmatch '(?m)^\s+DisplayVersion:') `
        'DisplayVersion must be omitted when no installed display version is supplied.'
    Assert-AppsAndFeaturesBlocks -Manifest $defaultManifest
    Write-Host 'PASS: default DisplayVersion is omitted'

    $manifestDirectory = Join-Path $defaultOutput "manifests\i\ItTiger\TigerMarkView\$version"
    $manifestFiles = @(Get-ChildItem -LiteralPath $manifestDirectory -File -Filter '*.yaml')
    Assert-True ($manifestFiles.Count -eq 3) 'Expected exactly three generated WinGet manifests.'
    foreach ($manifestFile in $manifestFiles) {
        $manifestText = Get-Content -LiteralPath $manifestFile.FullName -Raw
        Assert-True ($manifestText -match '(?m)^# yaml-language-server: \$schema=https://aka\.ms/winget-manifest\..*\.1\.12\.0\.schema\.json\r?$') `
            "$($manifestFile.Name) does not target a schema 1.12.0 header URL."
        Assert-True ($manifestText -match '(?m)^ManifestVersion: 1\.12\.0\r?$') `
            "$($manifestFile.Name) does not declare ManifestVersion 1.12.0."
    }
    Write-Host 'PASS: all generated manifests consistently target schema 1.12.0'

    $sameOutput = Join-Path $testRoot 'same'
    & $prepareScript `
        -InstallerPath $installerPath `
        -OutputRoot $sameOutput `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -InstalledDisplayVersion $version
    $sameManifest = Get-InstallerManifest -OutputRoot $sameOutput
    Assert-True ($sameManifest -cnotmatch '(?m)^\s+DisplayVersion:') `
        'DisplayVersion must be omitted when the installed version equals PackageVersion.'
    Assert-AppsAndFeaturesBlocks -Manifest $sameManifest
    Write-Host 'PASS: equal DisplayVersion is omitted'

    $differentOutput = Join-Path $testRoot 'different'
    $differentVersion = "$version.0"
    & $prepareScript `
        -InstallerPath $installerPath `
        -OutputRoot $differentOutput `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -InstalledDisplayVersion $differentVersion
    $differentManifest = Get-InstallerManifest -OutputRoot $differentOutput
    $displayVersionMatches = [regex]::Matches(
        $differentManifest,
        "(?m)^    DisplayVersion: $([regex]::Escape($differentVersion))\r?$")
    Assert-True ($displayVersionMatches.Count -eq 2) `
        'A differing DisplayVersion must be emitted for both installer scopes.'
    Assert-AppsAndFeaturesBlocks -Manifest $differentManifest -ExpectedDisplayVersion $differentVersion
    Write-Host 'PASS: differing DisplayVersion is preserved with valid indentation'

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
        -InstallerPath $installerPath `
        -OutputRoot (Join-Path $testRoot 'validation-warning') `
        -ExpectedVersion $version `
        -InstallerUrl $installerUrl `
        -WinGetPath $fakeWinGet `
        -Validate | Out-Host
    Write-Host 'PASS: only WinGet warning-success HRESULT 0x8A150028 is accepted'

    $warningStepLog = Join-Path $testRoot 'warning-step-winget.log'
    Set-FakeWinGetResult -Version '1.29.290' -ValidateExitCode -1978335192 -LogPath $warningStepLog
    $warningStepExitCode = Invoke-WorkflowValidationStep `
        -OutputRoot (Join-Path $testRoot 'validation-warning-step') `
        -WinGetPath $fakeWinGet
    Assert-True ($warningStepExitCode -eq 0) `
        ('An accepted WinGet warning must leave the workflow step at exit code 0; ' +
            "received $warningStepExitCode.")
    Write-Host 'PASS: warning-success validation exits the workflow pwsh process with 0'

    $failureLog = Join-Path $testRoot 'failure-winget.log'
    Set-FakeWinGetResult -Version '1.29.290' -ValidateExitCode -1978335191 -LogPath $failureLog
    Assert-Throws -MessagePattern '0x8A150029' -Action {
        & $prepareScript `
            -InstallerPath $installerPath `
            -OutputRoot (Join-Path $testRoot 'validation-failure') `
            -ExpectedVersion $version `
            -InstallerUrl $installerUrl `
            -WinGetPath $fakeWinGet `
            -Validate | Out-Host
    }
    Write-Host 'PASS: genuine WinGet manifest-validation failure HRESULT remains fatal'

    $failureStepLog = Join-Path $testRoot 'failure-step-winget.log'
    Set-FakeWinGetResult -Version '1.29.290' -ValidateExitCode -1978335191 -LogPath $failureStepLog
    $failureStepExitCode = Invoke-WorkflowValidationStep `
        -OutputRoot (Join-Path $testRoot 'validation-failure-step') `
        -WinGetPath $fakeWinGet
    Assert-True ($failureStepExitCode -ne 0) `
        'A genuine WinGet validation failure must fail the workflow pwsh process.'
    Write-Host 'PASS: genuine validation failure exits the workflow pwsh process non-zero'

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
    Write-Host 'PASS: a prepared directory reads back as the three-file submission set'

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
        '(?ms)^      - name: Seal and record the validated WinGet submission set\r?\n' +
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

    # --- The post-release gate consumes the stored set rather than replacing it ---

    $gateScript = Get-Content -LiteralPath (Join-Path $wingetDirectory 'Test-TigerMarkViewWinGet.ps1') -Raw
    Assert-True ($gateScript.Contains('$submission = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $ManifestDirectory')) `
        'The post-release gate must read the stored submission set.'
    # The gate may regenerate only to compare. Proving that means proving there is one
    # generator invocation and that it writes to the throwaway directory, not the store.
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
    Assert-True ($gateScript.Contains('Invoke-TigerMarkViewWinGetValidation -ManifestDirectory $submission.directory')) `
        'The post-release gate must run winget validate against the stored submission set.'
    Write-Host 'PASS: the post-release gate validates and submits the stored manifests'
}
finally {
    Remove-Item Env:TIGERMARKVIEW_TEST_WINGET_VERSION -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_WINGET_EXIT -ErrorAction SilentlyContinue
    Remove-Item Env:TIGERMARKVIEW_TEST_WINGET_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
