#Requires -Version 7.0
<#
    .SYNOPSIS
    Validates a published TigerMarkView release against the WinGet submission set
    its release workflow sealed.

    .DESCRIPTION
    Dot-source this file and call Invoke-TigerMarkViewWinGetReleaseValidation. It
    returns a structured result and never exits the process, so the post-release
    submission orchestrator can require the full result before it touches the
    winget-pkgs clone, while Test-TigerMarkViewWinGet.ps1 stays a thin command
    around the same function.

    Three things have to be true before a winget-pkgs pull request is honest, and
    this checks all three:

      1. the sealed manifests say what this release implies - identity, one version
         across all three documents, and the immutable asset URL;
      2. the asset actually published at that URL is the one those manifests hash;
         and
      3. WinGet can install that exact payload on a clean Windows machine, run the
         command it registers, and remove it again.

    The third is TigerWinLab's job. Nothing here builds a validation environment of
    its own: it generates a TigerWinLab WinGet scenario specification and runs
    TigerWinLab's entry point against it, then folds the lab's result into the same
    PASS / WARN / BLOCKED / FAIL vocabulary the rest of the release chain uses.

    What it validates is not a directory that happens to exist. The set is fetched
    from the release workflow's TigerMarkView-WinGet-<version>-<commit> artifact,
    selected by the commit the release tag names and verified against the digest
    GitHub recorded for it, then extracted to
    artifacts\winget-release\<version>\submission\. Nothing under artifacts\winget\
    is read: that is where Prepare-TigerMarkViewWinGet.ps1 generates locally, and a
    local set describes a locally built installer whose hash is not the published
    one. If the sealed artifact cannot be retrieved the run stops there; it never
    falls back.

    The manifests are read, never rewritten. Manifests are regenerated only into a
    throwaway directory, purely to prove they reproduce byte-for-byte; that
    comparison can never replace the sealed set.

    The run is read-only with respect to the host: nothing is installed and WinGet's
    host settings are never touched. The installation happens in the lab guest.

    GitHub is reached only through the shared authenticated `gh` session. No token
    is accepted, read from the environment, or logged.
#>

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'TigerMarkViewWinGet.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'TigerAiCore.ps1')

function Invoke-TigerMarkViewWinGetReleaseValidation {
    <#
        .SYNOPSIS
        Runs the complete post-release WinGet gate and returns its result.

        .PARAMETER RepositoryRoot
        The TigerMarkView repository root. Retained output lands below its
        artifacts\winget-release\<version>\.

        .PARAMETER Version
        The published release version to validate.

        .PARAMETER Client
        A repository-bound GitHub client. One backed by the authenticated `gh`
        session is created when this is omitted; tests pass a fake.

        .PARAMETER ArchivePath
        An already-downloaded TigerMarkView-WinGet-<version>-<commit>.zip, for a
        machine that cannot reach the artifact endpoint. It is verified against the
        same recorded digest as a download, so it is a different route to the sealed
        bytes, not a weaker check.

        .PARAMETER ExpectedSubmissionDigest
        When supplied, the submission digest the sealed set must reproduce - the
        value the release workflow's sealing step recorded.

        .PARAMETER TigerWinLabRoot
        An explicit TigerWinLab working copy. Omit it and the lab is discovered from
        the TigerAiCore configuration named by TigerAiCoreConfig. There is no
        sibling checkout or environment-variable fallback: an unregistered lab fails
        the lab check rather than being guessed at, because validating a release
        against a lab nobody chose is worse than not validating it here.

        .PARAMETER Refresh
        Re-downloads the sealed artifact even when a retained, provenance-bound copy
        already matches everything GitHub records for it.

        .PARAMETER SkipLab
        Runs the manifest and published-asset checks only. Useful for re-checking a
        published release quickly; it can never produce a submission-ready PASS.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Version,

        [object] $Client,

        [string] $ArchivePath,

        [string] $ExpectedSubmissionDigest,

        [string] $TigerWinLabRoot,

        [string] $WinGetPath,

        [ValidateRange(1, 240)]
        [int] $TimeoutMinutes = 45,

        [switch] $Refresh,

        [switch] $SkipLab
    )

    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $configuredVersion = [string] (Get-TigerMarkViewWinGetVersionProperty -RepositoryRoot $RepositoryRoot).Version
    $release = Get-TigerMarkViewWinGetRelease -Version $Version
    if ($null -eq $Client) { $Client = New-TigerMarkViewGitHubClient }

    # Acquiring the sealed set is a precondition, not a validation result: until the
    # release workflow's artifact is in hand there is no submission to report on, and
    # the one thing that must never happen here is quietly validating something else.
    $acquired = $null
    $acquisitionFailure = $null
    try {
        $acquired = Get-TigerMarkViewWinGetSealedSubmission `
            -RepositoryRoot $RepositoryRoot `
            -Version $Version `
            -Client $Client `
            -ArchivePath $ArchivePath `
            -ExpectedSubmissionDigest $ExpectedSubmissionDigest `
            -Force:$Refresh
    }
    catch {
        $acquisitionFailure = $_.Exception.Message
    }

    if ($null -eq $acquired) {
        # A release nobody has published yet, and a workflow artifact that has not
        # appeared, are checkpoints that are not done; anything else is a check that
        # ran and found the wrong data.
        $status = if ($acquisitionFailure -match 'still a draft|No published GitHub release|No GitHub Actions artifact') {
            'BLOCKED'
        }
        else {
            'FAIL'
        }
        $check = New-TigerMarkViewReleaseCheck -Id 'submission/source' -Status $status `
            -Observed "The sealed WinGet submission set for $Version could not be obtained: $acquisitionFailure" `
            -Expected "the release workflow's TigerMarkView-WinGet-$Version-<commit> artifact" `
            -Remediation ('This gate validates only the set the release workflow sealed. It does not fall ' +
                'back to a locally generated set under artifacts\winget\, because that describes a locally ' +
                'built installer rather than the published one.')
        $report = New-TigerMarkViewReleaseReport -Title "TigerMarkView $Version WinGet readiness" `
            -Checks @($check) -Context @{ version = $Version; package = $release.packageIdentifier }
        return [pscustomobject][ordered]@{
            report = $report
            version = $Version
            release = $release
            submission = $null
            provenance = $null
            releaseRoot = $null
            validationRoot = $null
            installerPath = $null
            publishedSha256 = $null
            lab = $null
            resultPath = $null
            result = $report
        }
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
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/source' -Status 'WARN' `
            -Observed ($provenanceMessage + ' GitHub reported no recorded digest for the artifact, so the ' +
                'archive was proven only by its extracted contents.') `
            -Evidence $provenance.artifactName))
    }
    else {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/source' -Status 'PASS' `
            -Observed ($provenanceMessage + " It reproduces the digest GitHub sealed for release " +
                "$($provenance.tag) at commit $($provenance.commit).") `
            -Evidence $provenance.artifactDigest))
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSubmissionDigest)) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/sealed-digest' -Status 'PASS' `
            -Observed "The sealed set reproduces the recorded submission digest $($submission.digest)." `
            -Evidence $submission.digest))
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
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'release/assets' `
        -Condition ($null -ne $publishedHash) `
        -PassObserved "An unauthenticated client can download the v$Version release assets." `
        -FailObserved ("The v$Version release assets could not be downloaded from " +
            "$($release.repositoryUrl)/releases/tag/v$Version : $downloadFailure") `
        -FailStatus 'BLOCKED' -Expected 'the three published release assets, publicly reachable' `
        -Remediation 'Publish the release and confirm its assets are public, then rerun.'))

    if ($null -ne $publishedHash) {
        $checksumPath = Join-Path $publishedRoot 'SHA256SUMS.txt'
        $pattern = '^(?<hash>[0-9a-fA-F]{64})\s+\*?' + [regex]::Escape($release.installerFileName) + '\s*$'
        $recorded = $null
        foreach ($line in @(Get-Content -LiteralPath $checksumPath)) {
            if ($line -cmatch $pattern) { $recorded = ([string] $Matches.hash).ToUpperInvariant(); break }
        }
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'release/checksums-file' `
            -Condition ($null -ne $recorded -and $recorded -ceq $publishedHash) `
            -PassObserved "SHA256SUMS.txt records the published digest for $($release.installerFileName)." `
            -FailObserved "SHA256SUMS.txt records '$recorded'; the published asset hashes to '$publishedHash'." `
            -Evidence $publishedHash `
            -Remediation 'Never replace a published asset to make a record agree; resolve the release identity.'))

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
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'release/artifact-manifest' `
            -Condition $matched `
            -PassObserved ("release-artifacts.json records $($release.installerFileName) for $Version " +
                'with the same digest and length.') `
            -FailObserved ("release-artifacts.json does not record $($release.installerFileName) for $Version " +
                "with digest $publishedHash and length $publishedLength.") `
            -Evidence $publishedHash `
            -Remediation 'Resolve the release identity explicitly; never edit a published record.'))

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
            Join-Path $RepositoryRoot "artifacts\winget-release\v$Version\$($release.installerFileName)"
            Join-Path $RepositoryRoot "artifacts\winget-release\$($release.installerFileName)"
        ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if ($null -ne $retainedInstaller) {
            $retainedHash = (Get-FileHash -LiteralPath $retainedInstaller -Algorithm SHA256).Hash.ToUpperInvariant()
            $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'release/retained-installer' `
                -Condition ($retainedHash -ceq $publishedHash) `
                -PassObserved ("The retained release installer at '$retainedInstaller' is byte-identical " +
                    'to the published asset.') `
                -FailObserved ("The retained release installer at '$retainedInstaller' hashes to " +
                    "'$retainedHash'; the published asset hashes to '$publishedHash'.") `
                -Evidence $retainedInstaller))
        }
        else {
            $checks.Add((New-TigerMarkViewReleaseCheck -Id 'release/retained-installer' -Status 'WARN' `
                -Observed ("$($release.installerFileName) is not retained under artifacts\winget-release, " +
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
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/set' `
        -Condition ($null -eq $submissionFailure) `
        -PassObserved $submissionMessage `
        -FailObserved "The sealed manifests are not a submission set for the published release: $submissionFailure" `
        -Evidence $submission.digest `
        -Remediation 'Never edit the sealed manifests to make this pass; resolve the release identity.'))

    # 4. Reproducibility, comparison only. Regenerating from the published installer into
    #    a throwaway directory proves the sealed bytes are still what the generator emits.
    #    The sealed set is never touched, so a reproducible run and an unreproducible one
    #    submit the same files - one of them just does not get to submit.
    $regeneratedRoot = Join-Path $validationRoot 'regenerated'
    if ($null -eq $publishedHash) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/reproducible' -Status 'FAIL' `
            -Observed 'The published installer could not be downloaded, so byte identity could not be re-derived.'))
    }
    elseif ($configuredVersion -cne $Version) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'submission/reproducible' -Status 'WARN' `
            -Observed ("Version.props is at $configuredVersion, not $Version, so this checkout cannot regenerate " +
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
        $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/reproducible' `
            -Condition ($null -eq $regenerationFailure) `
            -PassObserved 'Regenerating from the published installer reproduces the sealed manifests byte for byte.' `
            -FailObserved "The sealed manifests are not reproducible: $regenerationFailure" `
            -Remediation 'Never submit the regenerated set; it exists only to be compared.'))
    }

    # 5. WinGet's own opinion of the sealed set - the exact directory that gets copied.
    $validationFailure = $null
    try {
        $null = Invoke-TigerMarkViewWinGetValidation -ManifestDirectory $submission.directory -WinGetPath $WinGetPath
    }
    catch {
        $validationFailure = $_.Exception.Message
    }
    $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'submission/winget-validate' `
        -Condition ($null -eq $validationFailure) `
        -PassObserved 'winget validate accepts the sealed submission set.' `
        -FailObserved "winget validate rejected the sealed submission set: $validationFailure"))

    # 6. The lab. It installs the downloaded release asset against the sealed manifests.
    $lab = $null
    if ($SkipLab) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'lab/scenario' -Status 'FAIL' `
            -Observed ('-SkipLab was requested, so the WinGet install and uninstall lifecycle was not ' +
                'validated in TigerWinLab.') `
            -Remediation 'Rerun without -SkipLab before anything is submitted.'))
    }
    elseif ($null -eq $publishedHash) {
        $checks.Add((New-TigerMarkViewReleaseCheck -Id 'lab/scenario' -Status 'FAIL' `
            -Observed ('The published installer could not be downloaded, so there was nothing to validate ' +
                'in TigerWinLab.')))
    }
    else {
        # The lab is discovered from the TigerAiCore configuration, or supplied outright.
        # Nothing else: a guessed lab that happens to exist would produce a PASS nobody
        # can trace to a machine's declared resources.
        $resolvedLab = Get-TigerAiCoreLab -Name 'TigerWinLab' -Type 'WindowsLab' -Path $TigerWinLabRoot `
            -RequiredCommand 'Invoke-TigerWinLabWinGetScenario.ps1'
        $labSource = $resolvedLab.Source
        $TigerWinLabRoot = $resolvedLab.Path
        $labCommand = if ($resolvedLab.Available) {
            Join-Path $TigerWinLabRoot 'Invoke-TigerWinLabWinGetScenario.ps1'
        }
        else {
            $null
        }

        if (-not $resolvedLab.Available) {
            $checks.Add((New-TigerMarkViewReleaseCheck -Id 'lab/location' -Status 'FAIL' `
                -Observed $resolvedLab.Reason `
                -Remediation 'Register TigerWinLab in the TigerAiCore configuration, or pass -TigerWinLabRoot.'))
        }
        else {
            $checks.Add((New-TigerMarkViewReleaseCheck -Id 'lab/location' -Status 'PASS' `
                -Observed "TigerWinLab resolved from ${labSource}: $TigerWinLabRoot." -Evidence $TigerWinLabRoot))

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
                $checks.Add((New-TigerMarkViewReleaseCheck -Id 'lab/invocation' -Status 'FAIL' `
                    -Observed "The TigerWinLab WinGet scenario could not be run: $($_.Exception.Message)"))
            }

            $labResult = $null
            if (Test-Path -LiteralPath $labResultPath -PathType Leaf) {
                try { $labResult = Get-Content -LiteralPath $labResultPath -Raw | ConvertFrom-Json }
                catch {
                    $checks.Add((New-TigerMarkViewReleaseCheck -Id 'lab/result' -Status 'FAIL' `
                        -Observed "TigerWinLab wrote an unreadable result at '$labResultPath': $($_.Exception.Message)"))
                }
            }
            else {
                $checks.Add((New-TigerMarkViewReleaseCheck -Id 'lab/result' -Status 'FAIL' `
                    -Observed ("TigerWinLab wrote no result at '$labResultPath' (exit code $labExitCode). " +
                        'Check that the lab is provisioned and that this session is elevated.')))
            }

            # A BUSY lease result is a smaller shape than a job result, so every member is
            # read through PSObject rather than assumed to exist.
            $labStatus = $null
            if ($null -ne $labResult -and $null -ne $labResult.PSObject.Properties['status']) {
                $labStatus = [string] $labResult.status
            }
            if ($null -ne $labResult) {
                $checks.Add((New-TigerMarkViewReleaseAssertion -Id 'lab/scenario' `
                    -Condition ($labStatus -ceq 'OK' -and $labExitCode -eq 0) `
                    -PassObserved ('TigerWinLab installed, exercised, and removed the published package ' +
                        'in a clean guest.') `
                    -FailObserved "TigerWinLab ended with status '$labStatus' and exit code $labExitCode." `
                    -Evidence $labResultPath))
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

    $resultPath = Join-Path $validationRoot 'result.json'
    $report = New-TigerMarkViewReleaseReport -Title "TigerMarkView $Version WinGet readiness" `
        -Checks $checks.ToArray() `
        -Context @{
            version = $Version
            package = $release.packageIdentifier
            commit = $provenance.commit
            artifact = $provenance.artifactName
        }

    $result = [pscustomobject][ordered]@{
        schemaVersion = 3
        status = $report.status
        package = $release.packageIdentifier
        version = $Version
        completedUtc = $report.completedUtc
        summary = $report.summary
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
        checks = @($report.checks)
        exitCode = $report.exitCode
        resultPath = $resultPath
    }

    [IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllLines(
        (Join-Path $validationRoot 'summary.txt'),
        [string[]] @(Format-TigerMarkViewWinGetSummary -Result $result | ForEach-Object { [string] $_.text }),
        [Text.UTF8Encoding]::new($false))

    [pscustomobject][ordered]@{
        report = $report
        version = $Version
        release = $release
        submission = $submission
        provenance = $provenance
        releaseRoot = $acquired.releaseRoot
        validationRoot = $validationRoot
        installerPath = $installerPath
        publishedSha256 = $publishedHash
        lab = $lab
        resultPath = $resultPath
        result = $result
    }
}
