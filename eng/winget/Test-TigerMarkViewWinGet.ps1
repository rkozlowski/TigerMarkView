#Requires -Version 7.0
<#
    .SYNOPSIS
    Validates a published TigerMarkView release against the WinGet submission set
    its release workflow sealed, and reports whether that set is ready to copy into
    microsoft/winget-pkgs.

    .DESCRIPTION
    Three things have to be true before a winget-pkgs pull request is honest, and
    this checks all three:

      1. the sealed manifests say what this release implies - identity, one version
         across all three documents, and the immutable asset URL;
      2. the asset actually published at that URL is the one those manifests hash;
         and
      3. WinGet can install that exact payload on a clean Windows machine, run the
         command it registers, and remove it again.

    The third is TigerWinLab's job. This script builds no validation environment of
    its own: it generates a TigerWinLab WinGet scenario specification and runs
    TigerWinLab's entry point against it, then folds the lab's result into one
    PASS/FAIL verdict.

    What it validates is not a directory that happens to exist. The set is fetched
    from the release workflow's TigerMarkView-WinGet-<version>-<commit> artifact,
    selected by the commit the release tag names and verified against the digest
    GitHub recorded for it, then extracted to
    artifacts\winget-release\<version>\submission\. Nothing under artifacts\winget\
    is read: that is where Prepare-TigerMarkViewWinGet.ps1 generates locally, and a
    local set describes a locally built installer whose hash is not the published
    one. If the sealed artifact cannot be retrieved this run fails; it never falls
    back.

    The manifests are read, never rewritten. Manifests are regenerated only into a
    throwaway directory, purely to prove they reproduce byte-for-byte; that
    comparison can never replace the sealed set.

    The run is read-only with respect to the host: nothing is installed and WinGet's
    host settings are never touched. The installation happens in the lab guest.

    .PARAMETER Version
    The published release version to validate. Defaults to Version.props.

    .PARAMETER ArchivePath
    An already-downloaded TigerMarkView-WinGet-<version>-<commit>.zip, for a machine
    with no actions:read token. It is verified against the same recorded digest as a
    download, so it is a different route to the sealed bytes, not a weaker check.

    .PARAMETER ExpectedSubmissionDigest
    When supplied, the submission digest the sealed set must reproduce - the value
    the release workflow's sealing step recorded.

    .PARAMETER GitHubToken
    A token with actions:read, for downloading the sealed artifact. GH_TOKEN,
    GITHUB_TOKEN, and 'gh auth token' are used when this is omitted.

    .PARAMETER Refresh
    Re-downloads the sealed artifact even when a retained archive already matches
    the digest GitHub recorded for it.

    .PARAMETER TigerWinLabRoot
    An explicit TigerWinLab working copy. Omit it and the lab is discovered from
    the TigerAiCore configuration named by TigerAiCoreConfig. There is no sibling
    checkout or environment-variable fallback: an unregistered lab fails the lab
    check rather than being guessed at, because validating a release against a
    lab nobody chose is worse than not validating it here.

    .PARAMETER SkipLab
    Runs the manifest and published-asset checks only. Useful for re-checking a
    published release quickly; it can never produce a submission-ready PASS.

    .EXAMPLE
    .\eng\winget\Test-TigerMarkViewWinGet.ps1 -Version 0.8.1
#>
[CmdletBinding()]
param(
    [string] $Version,
    [string] $ArchivePath,
    [string] $ExpectedSubmissionDigest,
    [string] $GitHubToken,
    [string] $TigerWinLabRoot,
    [string] $WinGetPath,
    [ValidateRange(1, 240)]
    [int] $TimeoutMinutes = 45,
    [switch] $Refresh,
    [switch] $SkipLab,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'TigerMarkViewWinGet.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'TigerAiCore.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configuredVersion = [string] (Get-TigerMarkViewWinGetVersionProperty -RepositoryRoot $repoRoot).Version
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $configuredVersion }
$release = Get-TigerMarkViewWinGetRelease -Version $Version

# Acquiring the sealed set is a precondition, not a validation result: until the
# release workflow's artifact is in hand there is no submission to report on, and
# the one thing that must never happen here is quietly validating something else.
$acquired = $null
try {
    $client = New-TigerMarkViewGitHubClient -Token $GitHubToken
    $acquired = Get-TigerMarkViewWinGetSealedSubmission `
        -RepositoryRoot $repoRoot `
        -Version $Version `
        -Client $client `
        -ArchivePath $ArchivePath `
        -ExpectedSubmissionDigest $ExpectedSubmissionDigest `
        -Force:$Refresh
}
catch {
    Write-Host
    Write-Host "FAIL: the sealed WinGet submission set for $Version could not be obtained." -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host
    Write-Host '  This gate validates only the set the release workflow sealed as' -ForegroundColor DarkGray
    Write-Host "  TigerMarkView-WinGet-$Version-<commit>. It does not fall back to a locally" -ForegroundColor DarkGray
    Write-Host '  generated set under artifacts\winget\, because that describes a locally built' -ForegroundColor DarkGray
    Write-Host '  installer rather than the published one.' -ForegroundColor DarkGray
    exit 1
}

$submission = $acquired.submission
$provenance = $acquired.provenance
$validationRoot = [IO.Path]::GetFullPath((Join-Path $acquired.releaseRoot 'validation'))
$publishedRoot = Join-Path $validationRoot 'published'
New-Item -ItemType Directory -Path $publishedRoot -Force | Out-Null
Write-Host "Validating the sealed submission set at '$($submission.directory)'."

$checks = [Collections.Generic.List[object]]::new()
$publishedHash = $null
$publishedLength = 0L
$installerPath = Join-Path $publishedRoot $release.installerFileName

# 1. Provenance. Which artifact these three files came from, proven rather than
#    assumed, is the fact the rest of the run rests on, so it is recorded as a check
#    and lands in result.json alongside the verdict.
$provenanceMessage = ("Sealed artifact $($provenance.artifactName) (id $($provenance.artifactId), " +
    "run $($provenance.workflowRunId)) from $($provenance.archiveSource), archive SHA-256 " +
    "$($provenance.archiveSha256).")
if ($null -eq $provenance.artifactDigest) {
    $checks.Add((New-TigerMarkViewWinGetCheck -Name 'submission/source' -Status 'WARN' `
        -Message ($provenanceMessage + ' GitHub reported no recorded digest for the artifact, so the ' +
            'archive was proven only by its extracted contents.')))
}
else {
    $checks.Add((New-TigerMarkViewWinGetCheck -Name 'submission/source' -Status 'PASS' `
        -Message ($provenanceMessage + " It reproduces the digest GitHub sealed for release " +
            "$($provenance.tag) at commit $($provenance.commit).")))
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedSubmissionDigest)) {
    $checks.Add((New-TigerMarkViewWinGetCheck -Name 'submission/sealed-digest' -Status 'PASS' `
        -Message ("The sealed set reproduces the recorded submission digest " +
            "$($submission.digest).")))
}

# 2. The published release. Downloaded exactly as an unauthenticated client would,
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
        Join-Path $acquired.releaseRoot $release.installerFileName
        Join-Path $acquired.releaseRoot "installer\$($release.installerFileName)"
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

# 3. The sealed submission set. One rule source decides identity, version agreement,
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
$submissionMessage = "The sealed manifests are the $($release.packageIdentifier) $Version submission set"
$submissionMessage += if ($null -eq $publishedHash) {
    ', though no published asset was available to compare their InstallerSha256 with.'
}
else {
    ' and declare the published asset.'
}
$checks.Add((New-TigerMarkViewWinGetAssertion -Name 'submission/set' `
    -Condition ($null -eq $submissionFailure) `
    -Message $submissionMessage `
    -FailureMessage "The sealed manifests are not a submission set for the published release: $submissionFailure"))

# 4. Reproducibility, comparison only. Regenerating from the published installer into
#    a throwaway directory proves the sealed bytes are still what the generator emits.
#    The sealed set is never touched, so a reproducible run and an unreproducible one
#    submit the same files - one of them just does not get to submit.
$regeneratedRoot = Join-Path $validationRoot 'regenerated'
if ($null -eq $publishedHash) {
    $checks.Add((New-TigerMarkViewWinGetCheck -Name 'submission/reproducible' -Status 'FAIL' `
        -Message 'The published installer could not be downloaded, so byte identity could not be re-derived.'))
}
elseif ($configuredVersion -cne $Version) {
    $checks.Add((New-TigerMarkViewWinGetCheck -Name 'submission/reproducible' -Status 'WARN' `
        -Message ("Version.props is at $configuredVersion, not $Version, so this checkout cannot regenerate " +
            'the set for comparison. The sealed set is still what would be submitted.')))
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
                "the sealed set hashes to '$($submission.digest)'")
        }
    }
    catch {
        $regenerationFailure = $_.Exception.Message
    }
    $checks.Add((New-TigerMarkViewWinGetAssertion -Name 'submission/reproducible' `
        -Condition ($null -eq $regenerationFailure) `
        -Message 'Regenerating from the published installer reproduces the sealed manifests byte for byte.' `
        -FailureMessage "The sealed manifests are not reproducible: $regenerationFailure"))
}

# 5. WinGet's own opinion of the sealed set - the exact directory that gets copied.
$validationFailure = $null
try {
    $null = Invoke-TigerMarkViewWinGetValidation -ManifestDirectory $submission.directory -WinGetPath $WinGetPath
}
catch {
    $validationFailure = $_.Exception.Message
}
$checks.Add((New-TigerMarkViewWinGetAssertion -Name 'submission/winget-validate' `
    -Condition ($null -eq $validationFailure) `
    -Message 'winget validate accepts the sealed submission set.' `
    -FailureMessage "winget validate rejected the sealed submission set: $validationFailure"))

# 6. The lab. It installs the downloaded release asset against the sealed manifests.
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
    # The lab is discovered from the TigerAiCore configuration, or supplied outright.
    # Nothing else: a guessed lab that happens to exist would produce a PASS nobody
    # can trace to a machine's declared resources.
    $resolvedLab = Get-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab' -Path $TigerWinLabRoot `
        -RequiredCommand 'Invoke-TigerWinLabWinGetScenario.ps1'
    $labSource = $resolvedLab.Source
    $TigerWinLabRoot = $resolvedLab.Path
    $labCommand = if ($resolvedLab.Available) { Join-Path $TigerWinLabRoot 'Invoke-TigerWinLabWinGetScenario.ps1' } else { $null }

    if (-not $resolvedLab.Available) {
        $checks.Add((New-TigerMarkViewWinGetCheck -Name 'lab/location' -Status 'FAIL' `
            -Message $resolvedLab.Reason))
    }
    else {
        $checks.Add((New-TigerMarkViewWinGetCheck -Name 'lab/location' -Status 'PASS' `
            -Message "TigerWinLab resolved from ${labSource}: $TigerWinLabRoot."))

        $spec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tigermarkview.labspec.template.json') -Raw |
            ConvertFrom-Json
        $spec.package.version = $Version
        # The lab installs the sealed set, not a regenerated copy of it.
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
            configurationPath = $resolvedLab.ConfigurationPath
            scenario = $labCommand
            specPath = $specPath
            manifestDirectory = $submission.directory
            resultPath = $labResultPath
            exitCode = $labExitCode
            status = $labStatus
        }
    }
}

$verdict = Get-TigerMarkViewWinGetVerdict -Checks $checks.ToArray()
$resultPath = Join-Path $validationRoot 'result.json'
$result = [pscustomobject][ordered]@{
    schemaVersion = 2
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
    provenance = $provenance
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
