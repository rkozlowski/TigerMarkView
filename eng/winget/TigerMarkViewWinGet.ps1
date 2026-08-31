#Requires -Version 7.0
<#
    .SYNOPSIS
    Shared reasoning for the TigerMarkView WinGet submission set.

    .DESCRIPTION
    Dot-source this file. It exists so that the generator, the release workflow's
    sealing step, and the post-release gate all agree on one definition of what
    the submission is: which three files it contains, what the immutable asset
    URL is, and what "these are the bytes that were validated" means.

    Nothing here writes a manifest. Generation stays in
    Prepare-TigerMarkViewWinGet.ps1, so there is still exactly one place that can
    produce a submission set.

    Generation and authority are not the same thing. Prepare produces a set
    locally, before a release exists; after publication the authoritative set is
    the one the release workflow sealed and uploaded as
    TigerMarkView-WinGet-<version>-<commit>. The acquisition functions below fetch
    exactly that artifact, so the post-release gate never has to trust a directory
    that merely happens to exist.

    GitHub is reached only through the shared, authenticated `gh` adapter in
    eng/release-automation/ReleaseAutomation.ps1, and results are reported in that
    file's PASS / WARN / BLOCKED / FAIL vocabulary. Nothing here accepts a token
    argument, reads one from the environment, or logs one.
#>

Set-StrictMode -Version Latest

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'release-automation' 'ReleaseAutomation.ps1')

function Get-TigerMarkViewWinGetRelease {
    <#
        .SYNOPSIS
        Describes everything a version implies about its submission.

        .DESCRIPTION
        The installer file name, the immutable release asset URL, the three
        manifest file names in submission order, and the winget-pkgs path are all
        functions of the version alone. Deriving them once keeps the generator and
        the gate from drifting into two slightly different opinions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Version,

        [string] $RepositoryUrl
    )

    if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
        throw "Invalid version '$Version'."
    }
    if ([string]::IsNullOrWhiteSpace($RepositoryUrl)) {
        $RepositoryUrl = (Get-TigerMarkViewWinGetVersionProperty).RepositoryUrl
    }
    $RepositoryUrl = $RepositoryUrl.TrimEnd('/')

    $packageIdentifier = 'ItTiger.TigerMarkView'
    $installerFileName = "TigerMarkView-$Version-win-x64-setup.exe"

    [pscustomobject][ordered]@{
        version = $Version
        packageIdentifier = $packageIdentifier
        repositoryUrl = $RepositoryUrl
        installerFileName = $installerFileName
        installerUrl = "$RepositoryUrl/releases/download/v$Version/$installerFileName"
        # Submission order: installer, default locale, version. Read-only consumers
        # index this array, so the order is part of the contract.
        manifestFileNames = @(
            "$packageIdentifier.installer.yaml"
            "$packageIdentifier.locale.en-US.yaml"
            "$packageIdentifier.yaml"
        )
        manifestRelativePath = Join-Path 'manifests' (Join-Path 'i' (Join-Path 'ItTiger' (Join-Path 'TigerMarkView' $Version)))
        submissionPath = "manifests/i/ItTiger/TigerMarkView/$Version"
    }
}

function Get-TigerMarkViewWinGetVersionProperty {
    <#
        .SYNOPSIS
        Reads the shared product metadata that the manifests are generated from.
    #>
    [CmdletBinding()]
    param(
        [string] $RepositoryRoot
    )

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }
    [xml] $versionProps = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'Version.props') -Raw
    $versionProps.Project.PropertyGroup
}

function Get-TigerMarkViewWinGetManifestDirectory {
    <#
        .SYNOPSIS
        Resolves the one deterministic location a submission set lives in.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $Version
    )

    $release = Get-TigerMarkViewWinGetRelease -Version $Version
    [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $release.manifestRelativePath))
}

function Read-TigerMarkViewWinGetSubmissionSet {
    <#
        .SYNOPSIS
        Reads a submission set and proves it is exactly the three expected files.

        .DESCRIPTION
        A submission directory that holds anything other than the three manifests
        is not a submission set, because what would be copied into winget-pkgs
        would no longer be obvious. Extra files, missing files, and a byte-order
        mark are all rejected here rather than being noticed by a reviewer.

        The returned digests are what later steps compare, so a set can be proven
        to be the same set after it has crossed an artifact upload.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestDirectory,

        [Parameter(Mandatory)]
        [string] $Version
    )

    $release = Get-TigerMarkViewWinGetRelease -Version $Version
    $ManifestDirectory = [IO.Path]::GetFullPath($ManifestDirectory)
    if (-not (Test-Path -LiteralPath $ManifestDirectory -PathType Container)) {
        throw ("WinGet submission directory not found: $ManifestDirectory. " +
            "The post-release submission set is the release workflow's " +
            "TigerMarkView-WinGet-$Version-<commit> artifact, downloaded by " +
            'eng\winget\Get-TigerMarkViewWinGetReleaseSubmission.ps1; ' +
            'eng\winget\Prepare-TigerMarkViewWinGet.ps1 generates a local set only.')
    }

    $presentNames = @(Get-ChildItem -LiteralPath $ManifestDirectory -Force | ForEach-Object Name)
    $missing = @($release.manifestFileNames | Where-Object { $_ -cnotin $presentNames })
    if ($missing.Count -ne 0) {
        throw "The WinGet submission set in '$ManifestDirectory' is incomplete. Missing: $($missing -join ', ')."
    }
    $unexpected = @($presentNames | Where-Object { $_ -cnotin $release.manifestFileNames })
    if ($unexpected.Count -ne 0) {
        throw ("The WinGet submission set in '$ManifestDirectory' must contain only the three " +
            "submission manifests. Unexpected: $($unexpected -join ', ').")
    }

    $documents = foreach ($name in $release.manifestFileNames) {
        $path = Join-Path $ManifestDirectory $name
        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            throw "'$name' must be UTF-8 without a byte-order mark."
        }
        [pscustomobject][ordered]@{
            name = $name
            path = $path
            length = [long] $bytes.Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
            lines = @(([Text.UTF8Encoding]::new($false, $true).GetString($bytes)) -split "`r?`n")
        }
    }
    $documents = @($documents)

    [pscustomobject][ordered]@{
        directory = $ManifestDirectory
        release = $release
        documents = $documents
        digest = Get-TigerMarkViewWinGetSubmissionDigest -Documents $documents
        installer = [pscustomobject][ordered]@{
            packageIdentifier = Get-TigerMarkViewWinGetManifestField -Lines $documents[0].lines -Name 'PackageIdentifier'
            packageVersion = Get-TigerMarkViewWinGetManifestField -Lines $documents[0].lines -Name 'PackageVersion'
            installerUrl = Get-TigerMarkViewWinGetManifestField -Lines $documents[0].lines -Name 'InstallerUrl'
            installerSha256 = Get-TigerMarkViewWinGetManifestField -Lines $documents[0].lines -Name 'InstallerSha256'
        }
        locale = [pscustomobject][ordered]@{
            packageIdentifier = Get-TigerMarkViewWinGetManifestField -Lines $documents[1].lines -Name 'PackageIdentifier'
            packageVersion = Get-TigerMarkViewWinGetManifestField -Lines $documents[1].lines -Name 'PackageVersion'
        }
        version = [pscustomobject][ordered]@{
            packageIdentifier = Get-TigerMarkViewWinGetManifestField -Lines $documents[2].lines -Name 'PackageIdentifier'
            packageVersion = Get-TigerMarkViewWinGetManifestField -Lines $documents[2].lines -Name 'PackageVersion'
        }
    }
}

function Get-TigerMarkViewWinGetManifestField {
    <#
        .SYNOPSIS
        Reads the first value of a scalar manifest key, or $null.

        .DESCRIPTION
        The manifests are generated here and are flat enough that a line read is
        honest and needs no YAML parser. Leading whitespace is allowed because
        InstallerUrl and InstallerSha256 sit inside the Installers list; the first
        occurrence wins, and both installer entries carry the same values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Lines,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $pattern = '^\s*' + [regex]::Escape($Name) + ':\s*(?<value>.*?)\s*$'
    foreach ($line in $Lines) {
        if ($line -cmatch $pattern) {
            return ([string] $Matches.value).Trim("'", '"')
        }
    }
    return $null
}

function Get-TigerMarkViewWinGetSubmissionDigest {
    <#
        .SYNOPSIS
        Reduces a submission set to one digest over its file names and bytes.

        .DESCRIPTION
        This is what lets the publication job say that the artifact it downloaded
        is the artifact the validation job validated, without shipping three
        separate hashes through the workflow. Names are included so that a
        renamed-but-identical file cannot pass.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Documents
    )

    $lines = foreach ($document in $Documents) {
        '{0} {1}' -f $document.sha256, $document.name
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n") + "`n")
    $stream = [IO.MemoryStream]::new($bytes)
    try {
        (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
    }
}

function Get-TigerMarkViewWinGetWorkflowArtifactName {
    <#
        .SYNOPSIS
        Names the sealed WinGet artifact a release workflow run uploads.

        .DESCRIPTION
        The release workflow uploads the validated submission set as
        TigerMarkView-WinGet-<version>-<commit>. That name is the whole identity
        of the authoritative submission: it pins both the version and the exact
        commit whose installer the manifests hash, so a set produced by any other
        run cannot be mistaken for it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [string] $Commit
    )

    if ($Commit -notmatch '^[0-9a-fA-F]{40}$') {
        throw "Expected a full 40-character commit SHA; received '$Commit'."
    }
    "TigerMarkView-WinGet-$Version-$($Commit.ToLowerInvariant())"
}

function Get-TigerMarkViewWinGetReleaseRoot {
    <#
        .SYNOPSIS
        The retained location for everything a published release's WinGet gate reads.

        .DESCRIPTION
        artifacts\winget-release\<version>\ is deliberately not artifacts\winget\.
        The latter is where Prepare-TigerMarkViewWinGet.ps1 generates locally, and a
        set left there by an earlier local run is exactly the stale input that must
        never reach post-release validation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Version
    )

    [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath($RepositoryRoot)) "artifacts\winget-release\$Version"))
}

function Get-TigerMarkViewWinGetSealedSubmissionDirectory {
    <#
        .SYNOPSIS
        The one directory a downloaded workflow submission set is extracted into.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Version
    )

    Join-Path (Get-TigerMarkViewWinGetReleaseRoot -RepositoryRoot $RepositoryRoot -Version $Version) 'submission'
}

function New-TigerMarkViewGitHubClient {
    <#
        .SYNOPSIS
        Binds every GitHub read this gate performs to one repository and one
        authenticated `gh` session.

        .DESCRIPTION
        This is a repository-scoped face on the shared adapter in
        eng/release-automation/ReleaseAutomation.ps1, so there is one place that
        decides how GitHub is reached and one authentication contract for the
        whole release chain: whatever `gh auth login` established.

        No token is accepted, read from the environment, logged, or written to
        disk. A machine without a usable session repairs it with `gh auth login`.

        .PARAMETER Cli
        An existing shared adapter. One is created when this is omitted; tests pass
        a fake so no check here needs a credential or a network.

        .PARAMETER RepositoryUrl
        The repository the reads are bound to. Defaults to Version.props.
    #>
    [CmdletBinding()]
    param(
        [object] $Cli,

        [string] $RepositoryUrl
    )

    if ([string]::IsNullOrWhiteSpace($RepositoryUrl)) {
        $RepositoryUrl = (Get-TigerMarkViewWinGetVersionProperty).RepositoryUrl
    }
    $RepositoryUrl = ([string] $RepositoryUrl).TrimEnd('/')
    if ($RepositoryUrl -notmatch '^https://github\.com/(?<owner>[^/]+)/(?<name>[^/]+)$') {
        throw "Cannot derive a GitHub owner and repository from '$RepositoryUrl'."
    }
    $owner = $Matches.owner
    $name = $Matches.name
    if ($null -eq $Cli) { $Cli = New-TigerMarkViewGitHubCli }
    $adapter = $Cli

    [pscustomobject][ordered]@{
        owner = $owner
        name = $name
        slug = "$owner/$name"
        # A `gh api` path, not an absolute URL: the session decides the host.
        apiRoot = "repos/$owner/$name"
        cli = $adapter
        invoke = {
            param([Parameter(Mandatory)][string] $Path)
            & $adapter.api $Path
        }.GetNewClosure()
        download = {
            param(
                [Parameter(Mandatory)][string] $Path,
                [Parameter(Mandatory)][string] $OutFile
            )
            $null = & $adapter.downloadApi $Path $OutFile
        }.GetNewClosure()
    }
}

function Resolve-TigerMarkViewWinGetReleaseCommit {
    <#
        .SYNOPSIS
        Resolves a version to the published release and the exact commit it tags.

        .DESCRIPTION
        The commit is what selects the workflow artifact, so it is read from the tag
        rather than assumed to be the local HEAD: a maintainer validating an older
        release, or one whose checkout has moved on, must still reach the set that
        release was built from. Annotated tags are dereferenced to their commit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Client,

        [Parameter(Mandatory)]
        [string] $Version
    )

    $tag = "v$Version"
    try {
        $release = & $Client.invoke "$($Client.apiRoot)/releases/tags/$tag"
    }
    catch {
        throw ("No published GitHub release is tagged '$tag' in $($Client.slug): $($_.Exception.Message). " +
            'The post-release WinGet gate runs after the release is public.')
    }
    if ($null -ne $release.PSObject.Properties['draft'] -and [bool] $release.draft) {
        throw ("The GitHub release tagged '$tag' is still a draft. Its asset URL does not resolve, " +
            'so there is nothing to validate yet.')
    }

    try {
        $reference = & $Client.invoke "$($Client.apiRoot)/git/ref/tags/$tag"
    }
    catch {
        throw "Could not resolve the git tag '$tag' in $($Client.slug): $($_.Exception.Message)."
    }
    $commit = [string] $reference.object.sha
    if ([string] $reference.object.type -ceq 'tag') {
        $annotated = & $Client.invoke "$($Client.apiRoot)/git/tags/$commit"
        $commit = [string] $annotated.object.sha
    }
    if ($commit -notmatch '^[0-9a-fA-F]{40}$') {
        throw "The tag '$tag' did not resolve to a commit SHA."
    }

    [pscustomobject][ordered]@{
        tag = $tag
        commit = $commit.ToLowerInvariant()
        releaseName = [string] $release.name
        publishedUtc = [string] $release.published_at
        releaseUrl = [string] $release.html_url
    }
}

function Find-TigerMarkViewWinGetWorkflowArtifact {
    <#
        .SYNOPSIS
        Finds the one sealed WinGet artifact belonging to a release commit.

        .DESCRIPTION
        Selection is by exact name and by the run's head commit, never by "the most
        recent WinGet artifact". Repeated release attempts leave several artifacts
        of the same version behind, and only the one built from the tagged commit
        describes the installer that was published.

        Nothing here falls back. An absent, expired, or ambiguous artifact throws,
        because the alternative would be validating a set that no release sealed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Client,

        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [string] $Commit
    )

    $name = Get-TigerMarkViewWinGetWorkflowArtifactName -Version $Version -Commit $Commit
    $matched = [Collections.Generic.List[object]]::new()
    $page = 1
    do {
        $uri = "$($Client.apiRoot)/actions/artifacts?per_page=100&page=$page&name=$([Uri]::EscapeDataString($name))"
        $response = & $Client.invoke $uri
        $artifacts = @()
        if ($null -ne $response -and $null -ne $response.PSObject.Properties['artifacts']) {
            $artifacts = @($response.artifacts)
        }
        foreach ($artifact in $artifacts) {
            if ([string] $artifact.name -cne $name) { continue }
            $headSha = ''
            if ($null -ne $artifact.PSObject.Properties['workflow_run'] -and $null -ne $artifact.workflow_run) {
                $headSha = [string] $artifact.workflow_run.head_sha
            }
            if ($headSha.ToLowerInvariant() -cne $Commit.ToLowerInvariant()) { continue }
            $matched.Add($artifact)
        }
        $page++
    } while ($artifacts.Count -eq 100 -and $page -le 10)

    if ($matched.Count -eq 0) {
        throw ("No GitHub Actions artifact named '$name' was found in $($Client.slug). " +
            'The post-release gate validates only what the release workflow sealed; it will not ' +
            'fall back to a locally generated manifest set.')
    }

    $live = @($matched | Where-Object {
        $null -eq $_.PSObject.Properties['expired'] -or -not [bool] $_.expired
    })
    if ($live.Count -eq 0) {
        throw ("The GitHub Actions artifact '$name' has expired, so the sealed submission set can no " +
            'longer be downloaded. Re-run the release workflow for this commit, or submit the ' +
            'manifests already recorded for this release.')
    }
    $artifact = @($live | Sort-Object -Property @{ Expression = { [DateTime] $_.created_at } } -Descending)[0]

    $digest = $null
    if ($null -ne $artifact.PSObject.Properties['digest'] -and
        -not [string]::IsNullOrWhiteSpace([string] $artifact.digest)) {
        $digest = ([string] $artifact.digest) -replace '^sha256:', ''
        $digest = $digest.ToLowerInvariant()
    }

    [pscustomobject][ordered]@{
        id = [long] $artifact.id
        name = $name
        commit = $Commit.ToLowerInvariant()
        sizeInBytes = [long] $artifact.size_in_bytes
        digest = $digest
        createdUtc = [string] $artifact.created_at
        workflowRunId = if ($null -ne $artifact.PSObject.Properties['workflow_run'] -and
            $null -ne $artifact.workflow_run) { [long] $artifact.workflow_run.id } else { 0L }
        downloadPath = "$($Client.apiRoot)/actions/artifacts/$([long] $artifact.id)/zip"
        candidates = $matched.Count
    }
}

function Save-TigerMarkViewWinGetWorkflowArtifact {
    <#
        .SYNOPSIS
        Places the sealed artifact's three manifests in the retained submission
        directory, and refuses to place anything else there.

        .DESCRIPTION
        The archive is verified against the digest GitHub recorded for the artifact
        before a single byte is extracted, so a truncated or substituted download
        cannot become the submission. Extraction goes to a staging directory that
        replaces the submission directory only once it has been proven to hold
        exactly the three manifests.

        An archive supplied by hand is accepted and verified identically. That is an
        escape hatch for a machine with no actions:read token, not a second source
        of truth: the digest still has to be the one GitHub sealed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Client,

        [Parameter(Mandatory)]
        [object] $Artifact,

        [Parameter(Mandatory)]
        [string] $ReleaseRoot,

        [Parameter(Mandatory)]
        [string] $Version,

        [string] $ArchivePath,

        [switch] $Force
    )

    $ReleaseRoot = [IO.Path]::GetFullPath($ReleaseRoot)
    $archiveDirectory = Join-Path $ReleaseRoot 'artifact'
    New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
    $retainedArchive = Join-Path $archiveDirectory "$($Artifact.name).zip"

    $source = 'the GitHub Actions artifact download'
    if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
        $ArchivePath = [IO.Path]::GetFullPath($ArchivePath)
        if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
            throw "The supplied WinGet artifact archive was not found: $ArchivePath"
        }
        Copy-Item -LiteralPath $ArchivePath -Destination $retainedArchive -Force
        $source = "the supplied archive '$ArchivePath'"
    }
    elseif ((Test-Path -LiteralPath $retainedArchive -PathType Leaf) -and -not $Force -and
        $null -ne $Artifact.digest -and
        (Get-FileHash -LiteralPath $retainedArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $Artifact.digest) {
        $source = "the retained archive '$retainedArchive'"
    }
    else {
        Write-Host "Downloading the sealed WinGet artifact '$($Artifact.name)' from $($Client.slug)."
        & $Client.download $Artifact.downloadPath $retainedArchive
    }

    if (-not (Test-Path -LiteralPath $retainedArchive -PathType Leaf)) {
        throw "The sealed WinGet artifact archive was not written to '$retainedArchive'."
    }
    $archiveHash = (Get-FileHash -LiteralPath $retainedArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($null -ne $Artifact.digest) {
        if ($archiveHash -cne $Artifact.digest) {
            throw ("The WinGet artifact archive obtained from $source hashes to '$archiveHash'; GitHub " +
                "records the sealed artifact '$($Artifact.name)' as '$($Artifact.digest)'. " +
                'These are not the same bytes.')
        }
    }
    else {
        Write-Warning ("GitHub reported no digest for artifact '$($Artifact.name)', so the archive could " +
            'only be checked by its extracted contents.')
    }

    $staging = Join-Path $ReleaseRoot ('.extract-' + [Guid]::NewGuid().ToString('N'))
    $submissionDirectory = Join-Path $ReleaseRoot 'submission'
    try {
        Expand-Archive -LiteralPath $retainedArchive -DestinationPath $staging -Force
        # The shape gate: exactly the three sealed manifests, UTF-8 without a byte-order
        # mark. A staging directory that fails this never becomes the submission.
        $null = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $staging -Version $Version

        if (Test-Path -LiteralPath $submissionDirectory) {
            $resolved = [IO.Path]::GetFullPath($submissionDirectory)
            if (-not $resolved.StartsWith($ReleaseRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar,
                    [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to replace a submission directory outside '$ReleaseRoot'."
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
        Move-Item -LiteralPath $staging -Destination $submissionDirectory
    }
    finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }

    [pscustomobject][ordered]@{
        source = $source
        archivePath = $retainedArchive
        archiveSha256 = $archiveHash
        submissionDirectory = [IO.Path]::GetFullPath($submissionDirectory)
    }
}

function Resolve-TigerMarkViewWinGetRetainedSubmission {
    <#
        .SYNOPSIS
        Reuses an already-retained sealed set, but only when its provenance record
        still binds it to exactly the artifact GitHub names now.

        .DESCRIPTION
        Rerunning the post-release gate after an interruption should not re-download
        an artifact that is already on disk and already proven. It must also never
        reuse one merely because a directory of the right name exists: a retag, a
        re-run release workflow, or a hand-edited manifest all produce exactly that
        directory with different meaning.

        So reuse is conditional on the whole binding still holding - version, tag,
        release commit, artifact name and id, GitHub's recorded artifact digest, the
        retained archive still hashing to that digest, and the extracted set still
        hashing to the submission digest the record claims. Returns $null, meaning
        'download it', whenever anything does not line up. It never repairs, deletes,
        or rewrites; a mismatch simply is not a cache hit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ReleaseRoot,

        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [object] $Tagged,

        [Parameter(Mandatory)]
        [object] $Artifact,

        [Parameter(Mandatory)]
        [string] $Repository
    )

    if ([string]::IsNullOrWhiteSpace($Artifact.digest)) { return $null }

    $recordPath = Join-Path $ReleaseRoot 'submission.json'
    if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) { return $null }
    $record = $null
    try { $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json }
    catch { return $null }
    if ($null -eq $record) { return $null }

    foreach ($name in @('version', 'tag', 'commit', 'repository', 'artifactName', 'artifactId',
            'artifactDigest', 'archivePath', 'archiveSha256', 'submissionDirectory', 'submissionDigest')) {
        if ($null -eq $record.PSObject.Properties[$name]) { return $null }
    }

    $bindings = @(
        ([string] $record.version) -ceq $Version
        ([string] $record.tag) -ceq [string] $Tagged.tag
        ([string] $record.commit) -ceq [string] $Tagged.commit
        ([string] $record.repository) -ceq $Repository
        ([string] $record.artifactName) -ceq [string] $Artifact.name
        ([long] $record.artifactId) -eq [long] $Artifact.id
        ([string] $record.artifactDigest) -ceq [string] $Artifact.digest
    )
    if (@($bindings | Where-Object { -not $_ }).Count -ne 0) { return $null }

    $archivePath = [string] $record.archivePath
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { return $null }
    $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -cne [string] $Artifact.digest) { return $null }

    $submissionDirectory = [string] $record.submissionDirectory
    if (-not (Test-Path -LiteralPath $submissionDirectory -PathType Container)) { return $null }
    $retained = $null
    try { $retained = Read-TigerMarkViewWinGetSubmissionSet -ManifestDirectory $submissionDirectory -Version $Version }
    catch { return $null }
    if ($retained.digest -cne ([string] $record.submissionDigest)) { return $null }

    Write-Host ("Reusing the retained sealed set for $($Tagged.tag): its provenance still binds " +
        "artifact $($Artifact.name) (id $($Artifact.id)) at commit $($Tagged.commit).")
    [pscustomobject][ordered]@{
        source = "the provenance-bound retained set '$submissionDirectory'"
        archivePath = $archivePath
        archiveSha256 = $archiveHash
        submissionDirectory = [IO.Path]::GetFullPath($submissionDirectory)
    }
}

function Get-TigerMarkViewWinGetSealedSubmission {
    <#
        .SYNOPSIS
        Produces the authoritative post-release submission set and its provenance.

        .DESCRIPTION
        This is the whole answer to "which manifests is this release's submission":
        the release tag names a commit, the commit names one sealed workflow
        artifact, that artifact's recorded digest names one archive, and that
        archive extracts to exactly three manifests. Every step is checked, and a
        failure at any of them throws rather than degrading to whatever happens to
        be on disk.

        The provenance record written beside the submission is what lets a later
        run, or a reader of the result file, say which artifact these bytes came
        from without trusting the directory's mere existence.

        That record is also what makes a rerun cheap without making it careless.
        A retained submission directory is reused only when every binding in the
        record still matches what GitHub says now - version, tag, release commit,
        artifact name, artifact id, and GitHub's recorded artifact digest - and the
        directory still reads back to the submission digest it recorded. Any one
        binding that has moved re-downloads instead; -Force always re-downloads.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [object] $Client,

        [string] $ArchivePath,

        [string] $ExpectedSubmissionDigest,

        [switch] $Force
    )

    $releaseRoot = Get-TigerMarkViewWinGetReleaseRoot -RepositoryRoot $RepositoryRoot -Version $Version
    New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

    $tagged = Resolve-TigerMarkViewWinGetReleaseCommit -Client $Client -Version $Version
    Write-Host "Release $($tagged.tag) is published at commit $($tagged.commit)."
    $artifact = Find-TigerMarkViewWinGetWorkflowArtifact -Client $Client -Version $Version -Commit $tagged.commit

    $placed = $null
    if ([string]::IsNullOrWhiteSpace($ArchivePath) -and -not $Force) {
        $placed = Resolve-TigerMarkViewWinGetRetainedSubmission -ReleaseRoot $releaseRoot `
            -Version $Version -Tagged $tagged -Artifact $artifact -Repository $Client.slug
    }
    if ($null -eq $placed) {
        $placed = Save-TigerMarkViewWinGetWorkflowArtifact -Client $Client -Artifact $artifact `
            -ReleaseRoot $releaseRoot -Version $Version -ArchivePath $ArchivePath -Force:$Force
    }

    $submission = Read-TigerMarkViewWinGetSubmissionSet `
        -ManifestDirectory $placed.submissionDirectory -Version $Version
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSubmissionDigest) -and
        $submission.digest -cne $ExpectedSubmissionDigest.ToLowerInvariant()) {
        throw ("The sealed submission set hashes to '$($submission.digest)'; the expected digest is " +
            "'$($ExpectedSubmissionDigest.ToLowerInvariant())'. These are not the same manifests.")
    }

    $provenance = [pscustomobject][ordered]@{
        schemaVersion = 1
        version = $Version
        tag = $tagged.tag
        commit = $tagged.commit
        releaseUrl = $tagged.releaseUrl
        releasePublishedUtc = $tagged.publishedUtc
        repository = $Client.slug
        artifactName = $artifact.name
        artifactId = $artifact.id
        workflowRunId = $artifact.workflowRunId
        artifactCreatedUtc = $artifact.createdUtc
        artifactDigest = $artifact.digest
        archivePath = $placed.archivePath
        archiveSha256 = $placed.archiveSha256
        archiveSource = $placed.source
        submissionDirectory = $submission.directory
        submissionDigest = $submission.digest
        expectedSubmissionDigest = if ([string]::IsNullOrWhiteSpace($ExpectedSubmissionDigest)) {
            $null
        }
        else {
            $ExpectedSubmissionDigest.ToLowerInvariant()
        }
        acquiredUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText(
        (Join-Path $releaseRoot 'submission.json'),
        ($provenance | ConvertTo-Json -Depth 8),
        [Text.UTF8Encoding]::new($false))

    [pscustomobject][ordered]@{
        submission = $submission
        provenance = $provenance
        releaseRoot = $releaseRoot
    }
}

function Resolve-TigerMarkViewWinGetPath {
    <#
        .SYNOPSIS
        Binds validation to one specific winget.exe.
    #>
    [CmdletBinding()]
    param(
        [string] $WinGetPath
    )

    if ([string]::IsNullOrWhiteSpace($WinGetPath)) {
        $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $winget) { throw 'winget.exe is required for manifest validation.' }
        $WinGetPath = $winget.Source
    }
    $WinGetPath = [IO.Path]::GetFullPath($WinGetPath)
    if (-not (Test-Path -LiteralPath $WinGetPath -PathType Leaf)) {
        throw "WinGet executable not found: $WinGetPath"
    }
    $WinGetPath
}

function Invoke-TigerMarkViewWinGetValidation {
    <#
        .SYNOPSIS
        Runs winget validate over a manifest directory and decides what its exit
        code meant.

        .DESCRIPTION
        WinGet documents 0x8A150028 as MANIFEST_VALIDATION_WARNING: validation
        succeeded with warnings. That is the only nonzero result accepted; a
        genuine validation failure stays fatal. The client version is never
        probed, because winget itself decides whether it understands the schema.

        One implementation serves both the generator and the post-release gate, so
        the accepted-warning behaviour cannot be true in one and false in the other.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestDirectory,

        [string] $WinGetPath
    )

    $WinGetPath = Resolve-TigerMarkViewWinGetPath -WinGetPath $WinGetPath
    Write-Host "Validating the WinGet manifest set with '$WinGetPath'."
    $validationOutput = @(& $WinGetPath validate --manifest $ManifestDirectory --disable-interactivity 2>&1)
    $validationExitCode = $LASTEXITCODE
    $validationOutput | ForEach-Object { Write-Host $_ }

    $validationWarningExitCode = -1978335192
    if ($validationExitCode -eq $validationWarningExitCode) {
        Write-Warning 'WinGet manifest validation succeeded with warnings.'

        # The accepted warning HRESULT still lives in the caller's $LASTEXITCODE. Clear the
        # global copy so a hosting shell -- notably the GitHub Actions pwsh step, which ends
        # with 'exit $LASTEXITCODE' -- does not fail on a result this script treats as success.
        $global:LASTEXITCODE = 0
    }
    elseif ($validationExitCode -ne 0) {
        $unsignedExitCode = [uint32] ([int64] $validationExitCode -band 0xffffffffL)
        throw ('winget validate failed with exit code {0} (0x{1:X8}).' -f `
            $validationExitCode, $unsignedExitCode)
    }

    [pscustomobject][ordered]@{
        winGetPath = $WinGetPath
        exitCode = $validationExitCode
        warned = $validationExitCode -eq $validationWarningExitCode
    }
}

function Format-TigerMarkViewWinGetSummary {
    <#
        .SYNOPSIS
        Renders a post-release validation result as coloured lines.

        .DESCRIPTION
        The checks themselves are the shared release-automation result objects, so
        the status vocabulary here is the same PASS / WARN / BLOCKED / FAIL the rest
        of the release chain uses. What this adds is the WinGet-specific evidence a
        maintainer needs in front of them - the published installer, the sealed
        artifact's provenance, and the exact three files a pull request would carry.

        One layout serves both the terminal and the summary file a run leaves
        behind, so the record a maintainer keeps is the report they read.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Result
    )

    $line = { param($Text = '', $Colour = 'DarkGray') [pscustomobject]@{ text = $Text; colour = $Colour } }

    & $line
    & $line "TigerMarkView $($Result.version) WinGet readiness" 'Cyan'
    foreach ($check in @($Result.checks)) {
        $colour = switch ([string] $check.status) {
            'PASS' { 'DarkGray' }
            'WARN' { 'Yellow' }
            'BLOCKED' { 'Yellow' }
            default { 'Red' }
        }
        & $line ('  {0,-8} {1,-34} {2}' -f $check.status, $check.id, $check.observed) $colour
        if (-not [string]::IsNullOrWhiteSpace([string] $check.remediation)) {
            & $line ('           -> {0}' -f $check.remediation) $colour
        }
    }

    & $line
    & $line ("  $($Result.summary.passed) passed, $($Result.summary.warned) warned, " +
        "$($Result.summary.blocked) blocked, $($Result.summary.failed) failed")
    & $line "  Installer: $($Result.installer.url)"
    & $line "  Published SHA-256: $($Result.installer.publishedSha256)"
    if ($null -ne $Result.PSObject.Properties['provenance'] -and $null -ne $Result.provenance) {
        & $line
        & $line "  Sealed artifact: $($Result.provenance.artifactName)"
        & $line "    Workflow run $($Result.provenance.workflowRunId) at commit $($Result.provenance.commit)"
        & $line "    Archive SHA-256: $($Result.provenance.archiveSha256)"
        & $line "    Archive source: $($Result.provenance.archiveSource)"
    }
    if ($null -ne $Result.PSObject.Properties['submission'] -and $null -ne $Result.submission) {
        & $line
        & $line "  Files ready, unchanged, for microsoft/winget-pkgs at $($Result.submission.path):"
        foreach ($file in @($Result.submission.files)) {
            & $line "    $($file.name)"
            & $line "      $($file.sourcePath)"
        }
        & $line "  Submission digest: $($Result.submission.digest)"
    }
    & $line
    & $line "  Machine-readable result: $($Result.resultPath)"

    & $line
    if ($Result.status -ceq 'PASS' -or $Result.status -ceq 'WARN') {
        & $line "$($Result.status): TigerMarkView $($Result.version) is ready for a winget-pkgs pull request." 'Green'
    }
    elseif ($Result.status -ceq 'BLOCKED') {
        & $line "BLOCKED: a required checkpoint for TigerMarkView $($Result.version) is not complete." 'Yellow'
    }
    else {
        & $line "FAIL: TigerMarkView $($Result.version) is not ready for a winget-pkgs pull request." 'Red'
    }
}
