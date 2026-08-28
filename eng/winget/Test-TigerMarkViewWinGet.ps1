#Requires -Version 7.0
<#
    .SYNOPSIS
    Validates a published TigerMarkView release against the stored WinGet submission
    set and reports whether that set is ready to copy into microsoft/winget-pkgs.

    .DESCRIPTION
    Three things have to be true before a winget-pkgs pull request is honest, and
    this checks all three:

      1. the stored manifests say what this release implies - identity, one version
         across all three documents, and the immutable asset URL;
      2. the asset actually published at that URL is the one those manifests hash;
         and
      3. WinGet can install that exact payload on a clean Windows machine, run the
         command it registers, and remove it again.

    The third is TigerWinLab's job. This script builds no validation environment of
    its own: it generates a TigerWinLab WinGet scenario specification and runs
    TigerWinLab's entry point against it, then folds the lab's result into one
    PASS/FAIL verdict.

    The manifests are read, never rewritten. The set this validates is the set the
    release workflow generated and validated, so the files copied into winget-pkgs
    after a PASS are byte-for-byte the files that were proven. Manifests are
    regenerated only into a throwaway directory, purely to prove they reproduce
    byte-for-byte; that comparison can never replace the stored set.

    The run is read-only with respect to the host: nothing is installed and WinGet's
    host settings are never touched. The installation happens in the lab guest.

    .PARAMETER Version
    The published release version to validate. Defaults to Version.props.

    .PARAMETER ManifestDirectory
    The stored submission set. Defaults to
    artifacts\winget\manifests\i\ItTiger\TigerMarkView\<version>, which is both
    where Prepare-TigerMarkViewWinGet.ps1 writes and where the release workflow's
    TigerMarkView-WinGet-<version>-<commit> artifact should be extracted.

    .PARAMETER TigerWinLabRoot
    The TigerWinLab working copy. Defaults to TIGERWINLAB_ROOT, then to a
    TigerWinLab checkout beside this repository.

    .PARAMETER SkipLab
    Runs the manifest and published-asset checks only. Useful for re-checking a
    published release quickly; it can never produce a submission-ready PASS.

    .EXAMPLE
    .\eng\winget\Test-TigerMarkViewWinGet.ps1 -Version 0.8.1
#>
[CmdletBinding()]
param(
    [string] $Version,
    [string] $ManifestDirectory,
    [string] $TigerWinLabRoot,
    [string] $WinGetPath,
    [ValidateRange(1, 240)]
    [int] $TimeoutMinutes = 45,
    [switch] $SkipLab,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'TigerMarkViewWinGet.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configuredVersion = [string] (Get-TigerMarkViewWinGetVersionProperty -RepositoryRoot $repoRoot).Version
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $configuredVersion }
$release = Get-TigerMarkViewWinGetRelease -Version $Version

if ([string]::IsNullOrWhiteSpace($ManifestDirectory)) {
    $ManifestDirectory = Get-TigerMarkViewWinGetManifestDirectory `
        -OutputRoot (Join-Path $repoRoot 'artifacts\winget') -Version $Version
}
$validationRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts\winget\validation\$Version"))
$publishedRoot = Join-Path $validationRoot 'published'
New-Item -ItemType Directory -Path $publishedRoot -Force | Out-Null

# A missing or malformed stored set is an operator error, not a validation result:
# there is nothing to report on until the submission set exists.
$submission = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $ManifestDirectory -Version $Version
Write-Host "Validating the stored submission set at '$($submission.directory)'."

$checks = [Collections.Generic.List[object]]::new()
$publishedHash = $null
$publishedLength = 0L
$installerPath = Join-Path $publishedRoot $release.installerFileName

# 1. The published release. Downloaded exactly as an unauthenticated client would,
#    and it is this download - not a local rebuild - that the lab later installs.
$downloadFailure = $null
try {
    $progress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        foreach ($name in @($release.installerFileName, 'SHA256SUMS.txt', 'release-artifacts.json')) {
            Invoke-WebRequest -Uri "$($release.repositoryUrl)/releases/download/v$Version/$name" `
                -OutFile (Join-Path $publishedRoot $name) -MaximumRedirection 5 -ErrorAction Stop
        }
    }
    finally {
        $ProgressPreference = $progress
    }
    $publishedHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
    $publishedLength = [long] (Get-Item -LiteralPath $installerPath).Length
}
catch {
    $downloadFailure = $_.Exception.Message
}
$checks.Add((New-TigerMarkViewWinGetAssertion -Name 'release/assets' `
    -Condition ($null -ne $publishedHash) `
    -Message "An unauthenticated client can download the v$Version release assets." `
    -FailureMessage ("The v$Version release assets could not be downloaded from " +
        "$($release.repositoryUrl)/releases/tag/v$Version : $downloadFailure")))

if ($null -ne $publishedHash) {
    $checksumPath = Join-Path $publishedRoot 'SHA256SUMS.txt'
    $pattern = '^(?<hash>[0-9a-fA-F]{64})\s+\*?' + [regex]::Escape($release.installerFileName) + '\s*$'
    $recorded = $null
    foreach ($line in @(Get-Content -LiteralPath $checksumPath)) {
        if ($line -cmatch $pattern) { $recorded = ([string] $Matches.hash).ToUpperInvariant(); break }
    }
    $checks.Add((New-TigerMarkViewWinGetAssertion -Name 'release/checksums-file' `
        -Condition ($null -ne $recorded -and $recorded -ceq $publishedHash) `
        -Message "SHA256SUMS.txt records the published digest for $($release.installerFileName)." `
        -FailureMessage "SHA256SUMS.txt records '$recorded'; the published asset hashes to '$publishedHash'."))

    $entry = $null
    $recordedVersion = $null
    try {
        $artifactManifest = Get-Content -LiteralPath (Join-Path $publishedRoot 'release-artifacts.json') -Raw |
            ConvertFrom-Json
        $recordedVersion = [string] $artifactManifest.releaseVersion
        $entry = @($artifactManifest.artifacts | Where-Object { $_.name -ceq $release.installerFileName }) |
            Select-Object -First 1
    }
    catch {
        $entry = $null
    }
    $matched = $null -ne $entry -and $recordedVersion -ceq $Version -and
        ([string] $entry.sha256).ToUpperInvariant() -ceq $publishedHash -and
        [long] $entry.length -eq $publishedLength
    $checks.Add((New-TigerMarkViewWinGetAssertion -Name 'release/artifact-manifest' `
        -Condition $matched `
        -Message "release-artifacts.json records $($release.installerFileName) for $Version with the same digest and length." `
        -FailureMessage ("release-artifacts.json does not record $($release.installerFileName) for $Version " +
            "with digest $publishedHash and length $publishedLength.")))

    # A retained copy of the release artifact is a cross-check, not a submission gate:
    # the pair that matters is the manifests and the published asset. Retaining it is
    # optional, so its absence warns; a retained copy that disagrees still fails.
    #
    # This deliberately looks under artifacts\winget-release, where the workflow-produced
    # installer is kept, and never under artifacts\installer. The latter holds the
    # maintainer's own Release build, and an Inno rebuild is never byte-identical to the
    # one CI compiled, so comparing against it would fail every release for no reason.
    $retainedInstaller = @(
        Join-Path $repoRoot "artifacts\winget-release\v$Version\$($release.installerFileName)"
        Join-Path $repoRoot "artifacts\winget-release\$($release.installerFileName)"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($null -ne $retainedInstaller) {
        $retainedHash = (Get-FileHash -LiteralPath $retainedInstaller -Algorithm SHA256).Hash.ToUpperInvariant()
        $checks.Add((New-TigerMarkViewWinGetAssertion -Name 'release/retained-installer' `
            -Condition ($retainedHash -ceq $publishedHash) `
            -Message "The retained release installer at '$retainedInstaller' is byte-identical to the published asset." `
            -FailureMessage "The retained release installer at '$retainedInstaller' hashes to '$retainedHash'; the published asset hashes to '$publishedHash'."))
    }
    else {
        $checks.Add((New-TigerMarkViewWinGetCheck -Name 'release/retained-installer' -Status 'WARN' `
            -Message ("$($release.installerFileName) is not retained under artifacts\winget-release, " +
                'so the workflow-produced installer was not compared with the published asset.')))
    }
}

# 2. The stored submission set. One rule source decides identity, version agreement,
#    the immutable URL, and the declared installer digest; a violation is one FAIL.
$submissionFailure = $null
try {
    # With no published hash the digest comparison cannot run, so the message below
    # claims only what was actually checked.
    & (Join-Path $PSScriptRoot 'Assert-TigerMarkViewWinGetSubmission.ps1') `
        -ManifestDirectory $submission.directory `
        -Version $Version `
        -ExpectedInstallerSha256 $publishedHash |
        Out-Null
}
catch {
    $submissionFailure = $_.Exception.Message
}
$submissionMessage = "The stored manifests are the $($release.packageIdentifier) $Version submission set"
$submissionMessage += if ($null -eq $publishedHash) {
    ', though no published asset was available to compare their InstallerSha256 with.'
}
else {
    ' and declare the published asset.'
}
$checks.Add((New-TigerMarkViewWinGetAssertion -Name 'submission/set' `
    -Condition ($null -eq $submissionFailure) `
    -Message $submissionMessage `
    -FailureMessage "The stored manifests are not a submission set for the published release: $submissionFailure"))

# 3. Reproducibility, comparison only. Regenerating from the published installer into
#    a throwaway directory proves the stored bytes are still what the generator emits.
#    The stored set is never touched, so a reproducible run and an unreproducible one
#    submit the same files - one of them just does not get to submit.
$regeneratedRoot = Join-Path $validationRoot 'regenerated'
if ($null -eq $publishedHash) {
    $checks.Add((New-TigerMarkViewWinGetCheck -Name 'submission/reproducible' -Status 'FAIL' `
        -Message 'The published installer could not be downloaded, so byte identity could not be re-derived.'))
}
elseif ($configuredVersion -cne $Version) {
    $checks.Add((New-TigerMarkViewWinGetCheck -Name 'submission/reproducible' -Status 'WARN' `
        -Message ("Version.props is at $configuredVersion, not $Version, so this checkout cannot regenerate " +
            'the set for comparison. The stored set is still what would be submitted.')))
}
else {
    $regenerationFailure = $null
    try {
        if (Test-Path -LiteralPath $regeneratedRoot) { Remove-Item -LiteralPath $regeneratedRoot -Recurse -Force }
        $regeneratedDirectory = & (Join-Path $PSScriptRoot 'Prepare-TigerMarkViewWinGet.ps1') `
            -InstallerPath $installerPath `
            -OutputRoot $regeneratedRoot `
            -ExpectedVersion $Version `
            -InstallerUrl $release.installerUrl `
            -ExpectedInstallerSha256 $publishedHash |
            Select-Object -Last 1
        $regenerated = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $regeneratedDirectory -Version $Version
        if ($regenerated.digest -cne $submission.digest) {
            $regenerationFailure = ("the regenerated set hashes to '$($regenerated.digest)'; " +
                "the stored set hashes to '$($submission.digest)'")
        }
    }
    catch {
        $regenerationFailure = $_.Exception.Message
    }
    $checks.Add((New-TigerMarkViewWinGetAssertion -Name 'submission/reproducible' `
        -Condition ($null -eq $regenerationFailure) `
        -Message 'Regenerating from the published installer reproduces the stored manifests byte for byte.' `
        -FailureMessage "The stored manifests are not reproducible: $regenerationFailure"))
}

# 4. WinGet's own opinion of the stored set - the exact directory that gets copied.
$validationFailure = $null
try {
    $null = Invoke-TigerMarkViewWinGetValidation -ManifestDirectory $submission.directory -WinGetPath $WinGetPath
}
catch {
    $validationFailure = $_.Exception.Message
}
$checks.Add((New-TigerMarkViewWinGetAssertion -Name 'submission/winget-validate' `
    -Condition ($null -eq $validationFailure) `
    -Message 'winget validate accepts the stored submission set.' `
    -FailureMessage "winget validate rejected the stored submission set: $validationFailure"))

# 5. The lab. It installs the downloaded release asset against the stored manifests.
$lab = $null
if ($SkipLab) {
    $checks.Add((New-TigerMarkViewWinGetCheck -Name 'lab/scenario' -Status 'FAIL' `
        -Message '-SkipLab was requested, so the WinGet install and uninstall lifecycle was not validated in TigerWinLab.'))
}
elseif ($null -eq $publishedHash) {
    $checks.Add((New-TigerMarkViewWinGetCheck -Name 'lab/scenario' -Status 'FAIL' `
        -Message 'The published installer could not be downloaded, so there was nothing to validate in TigerWinLab.'))
}
else {
    $labSource = 'the -TigerWinLabRoot argument'
    if ([string]::IsNullOrWhiteSpace($TigerWinLabRoot)) {
        $TigerWinLabRoot = $env:TIGERWINLAB_ROOT
        $labSource = 'TIGERWINLAB_ROOT'
    }
    if ([string]::IsNullOrWhiteSpace($TigerWinLabRoot)) {
        $TigerWinLabRoot = Join-Path (Split-Path -Parent $repoRoot) 'TigerWinLab'
        $labSource = 'a sibling checkout'
    }
    $TigerWinLabRoot = [IO.Path]::GetFullPath($TigerWinLabRoot)
    $labCommand = Join-Path $TigerWinLabRoot 'Invoke-TigerWinLabWinGetScenario.ps1'

    if (-not (Test-Path -LiteralPath $labCommand -PathType Leaf)) {
        $checks.Add((New-TigerMarkViewWinGetCheck -Name 'lab/location' -Status 'FAIL' `
            -Message "TigerWinLab's WinGet scenario was not found at '$labCommand' (resolved from $labSource)."))
    }
    else {
        $checks.Add((New-TigerMarkViewWinGetCheck -Name 'lab/location' -Status 'PASS' `
            -Message "TigerWinLab resolved from ${labSource}: $TigerWinLabRoot."))

        $spec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tigermarkview.labspec.template.json') -Raw |
            ConvertFrom-Json
        $spec.package.version = $Version
        $spec.manifestDirectory = $submission.directory
        $spec.installer.path = $installerPath
        $spec.installer.expectedUrl = $release.installerUrl
        $specPath = Join-Path $validationRoot 'tigerwinlab-spec.json'
        $spec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $specPath -Encoding utf8NoBOM

        $labResultPath = Join-Path $validationRoot 'tigerwinlab-result.json'
        if (Test-Path -LiteralPath $labResultPath -PathType Leaf) {
            Remove-Item -LiteralPath $labResultPath -Force
        }

        Write-Host "Running the TigerWinLab WinGet scenario (timeout: $TimeoutMinutes minutes)..."
        $labExitCode = $null
        try {
            & $labCommand `
                -SpecPath $specPath `
                -OutputRoot (Join-Path $validationRoot 'tigerwinlab-artifacts') `
                -ResultPath $labResultPath `
                -TimeoutMinutes $TimeoutMinutes `
                -Json | Out-Host
            $labExitCode = $LASTEXITCODE
        }
        catch {
            $checks.Add((New-TigerMarkViewWinGetCheck -Name 'lab/invocation' -Status 'FAIL' `
                -Message "The TigerWinLab WinGet scenario could not be run: $($_.Exception.Message)"))
        }

        $labResult = $null
        if (Test-Path -LiteralPath $labResultPath -PathType Leaf) {
            try { $labResult = Get-Content -LiteralPath $labResultPath -Raw | ConvertFrom-Json }
            catch {
                $checks.Add((New-TigerMarkViewWinGetCheck -Name 'lab/result' -Status 'FAIL' `
                    -Message "TigerWinLab wrote an unreadable result at '$labResultPath': $($_.Exception.Message)"))
            }
        }
        else {
            $checks.Add((New-TigerMarkViewWinGetCheck -Name 'lab/result' -Status 'FAIL' `
                -Message ("TigerWinLab wrote no result at '$labResultPath' (exit code $labExitCode). " +
                    'Check that the lab is provisioned and that this session is elevated.')))
        }

        # A BUSY lease result is a smaller shape than a job result, so every member is
        # read through PSObject rather than assumed to exist.
        $labStatus = $null
        if ($null -ne $labResult -and $null -ne $labResult.PSObject.Properties['status']) {
            $labStatus = [string] $labResult.status
        }
        if ($null -ne $labResult) {
            $checks.Add((New-TigerMarkViewWinGetAssertion -Name 'lab/scenario' `
                -Condition ($labStatus -ceq 'OK' -and $labExitCode -eq 0) `
                -Message 'TigerWinLab installed, exercised, and removed the published package in a clean guest.' `
                -FailureMessage "TigerWinLab ended with status '$labStatus' and exit code $labExitCode."))
        }

        $lab = [pscustomobject][ordered]@{
            root = $TigerWinLabRoot
            source = $labSource
            scenario = $labCommand
            specPath = $specPath
            resultPath = $labResultPath
            exitCode = $labExitCode
            status = $labStatus
        }
    }
}

$verdict = Get-TigerMarkViewWinGetVerdict -Checks $checks.ToArray()
$resultPath = Join-Path $validationRoot 'result.json'
$result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = $verdict.status
    package = $release.packageIdentifier
    version = $Version
    completedUtc = [DateTime]::UtcNow.ToString('o')
    summary = $verdict
    installer = [pscustomobject][ordered]@{
        url = $release.installerUrl
        fileName = $release.installerFileName
        declaredSha256 = [string] $submission.installer.installerSha256
        publishedSha256 = $publishedHash
        publishedLength = $publishedLength
    }
    submission = [pscustomobject][ordered]@{
        repository = 'microsoft/winget-pkgs'
        path = $release.submissionPath
        directory = $submission.directory
        digest = $submission.digest
        files = @($submission.documents | ForEach-Object {
            [pscustomobject][ordered]@{
                name = $_.name
                sourcePath = $_.path
                submissionPath = '{0}/{1}' -f $release.submissionPath, $_.name
                length = $_.length
                sha256 = $_.sha256
            }
        })
    }
    lab = $lab
    checks = @($checks.ToArray())
    resultPath = $resultPath
}

[IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
$summaryLines = @(Format-TigerMarkViewWinGetSummary -Result $result)
[IO.File]::WriteAllLines(
    (Join-Path $validationRoot 'summary.txt'),
    [string[]] @($summaryLines | ForEach-Object { [string] $_.text }),
    [Text.UTF8Encoding]::new($false))

if ($Json) {
    $result | ConvertTo-Json -Depth 12
}
else {
    foreach ($line in $summaryLines) { Write-Host $line.text -ForegroundColor $line.colour }
}

if ($result.status -ceq 'PASS') { exit 0 }
exit 1
