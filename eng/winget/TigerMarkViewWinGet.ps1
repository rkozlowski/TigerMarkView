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
#>

Set-StrictMode -Version Latest

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

function Resolve-TigerMarkViewGitHubToken {
    <#
        .SYNOPSIS
        Finds a GitHub token that can read this repository's workflow artifacts.

        .DESCRIPTION
        Listing a public repository's artifacts needs no credential, but downloading
        one needs actions:read. The sources are tried in the order a maintainer
        would expect and the chosen source is named in the report; the token value
        itself is never printed or written to disk.
    #>
    [CmdletBinding()]
    param(
        [string] $Token
    )

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        return [pscustomobject][ordered]@{ token = $Token; source = 'the -GitHubToken argument' }
    }
    foreach ($name in @('GH_TOKEN', 'GITHUB_TOKEN')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return [pscustomobject][ordered]@{ token = $value; source = $name }
        }
    }
    $gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $gh) {
        try {
            $previous = $global:LASTEXITCODE
            $value = (& $gh.Source auth token 2>$null | Select-Object -First 1)
            $exitCode = $LASTEXITCODE
            $global:LASTEXITCODE = $previous
            if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($value)) {
                return [pscustomobject][ordered]@{ token = ([string] $value).Trim(); source = 'gh auth token' }
            }
        }
        catch {
            # An unusable gh is not an error here; the next caller reports that no
            # token was found at all, which is the actionable message.
        }
    }
    [pscustomobject][ordered]@{ token = $null; source = $null }
}

function New-TigerMarkViewGitHubClient {
    <#
        .SYNOPSIS
        Binds every GitHub read this gate performs to one repository and one token.

        .DESCRIPTION
        The reads are expressed as two script blocks so a test can substitute a
        recorded API without a network, and so there is exactly one place that
        decides how a redirect and an authorization header interact.
    #>
    [CmdletBinding()]
    param(
        [string] $RepositoryUrl,

        [string] $Token
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
    $resolved = Resolve-TigerMarkViewGitHubToken -Token $Token
    $bearer = $resolved.token

    $headers = [ordered]@{
        'User-Agent' = 'TigerMarkView-WinGet-Gate'
        'Accept' = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    [pscustomobject][ordered]@{
        owner = $owner
        name = $name
        slug = "$owner/$name"
        apiRoot = "https://api.github.com/repos/$owner/$name"
        tokenSource = $resolved.source
        hasToken = -not [string]::IsNullOrWhiteSpace($bearer)
        invoke = {
            param([Parameter(Mandatory)][string] $Uri)

            $requestHeaders = [Collections.Specialized.OrderedDictionary]::new()
            foreach ($entry in $headers.GetEnumerator()) { $requestHeaders[$entry.Key] = $entry.Value }
            if (-not [string]::IsNullOrWhiteSpace($bearer)) {
                $requestHeaders['Authorization'] = "Bearer $bearer"
            }
            Invoke-RestMethod -Uri $Uri -Headers $requestHeaders -MaximumRedirection 5 -ErrorAction Stop
        }.GetNewClosure()
        download = {
            param(
                [Parameter(Mandatory)][string] $Uri,
                [Parameter(Mandatory)][string] $OutFile
            )

            if ([string]::IsNullOrWhiteSpace($bearer)) {
                throw ('Downloading a GitHub Actions artifact requires a token with actions:read. ' +
                    'Set GH_TOKEN or GITHUB_TOKEN, sign in with gh auth login, or pass -GitHubToken.')
            }
            $requestHeaders = [Collections.Specialized.OrderedDictionary]::new()
            foreach ($entry in $headers.GetEnumerator()) { $requestHeaders[$entry.Key] = $entry.Value }
            $requestHeaders['Authorization'] = "Bearer $bearer"

            $progress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                # The artifact endpoint answers 302 to a storage host that rejects a
                # GitHub Authorization header, so the redirect is followed by hand and
                # the credential is deliberately not carried across.
                $response = Invoke-WebRequest -Uri $Uri -Headers $requestHeaders `
                    -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Stop
                $status = [int] $response.StatusCode
                if ($status -in 301, 302, 303, 307, 308) {
                    $location = @($response.Headers['Location'])[0]
                    if ([string]::IsNullOrWhiteSpace($location)) {
                        throw "GitHub answered $status for '$Uri' without a Location header."
                    }
                    Invoke-WebRequest -Uri $location -OutFile $OutFile -MaximumRedirection 5 -ErrorAction Stop
                }
                elseif ($status -eq 200) {
                    [IO.File]::WriteAllBytes($OutFile, $response.Content)
                }
                elseif ($status -in 401, 403) {
                    throw ("GitHub refused the artifact download with HTTP $status. The token was " +
                        'accepted for reading but lacks actions:read on this repository.')
                }
                else {
                    throw "GitHub answered HTTP $status for '$Uri'."
                }
            }
            finally {
                $ProgressPreference = $progress
            }
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
        downloadUrl = "$($Client.apiRoot)/actions/artifacts/$([long] $artifact.id)/zip"
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
        & $Client.download $Artifact.downloadUrl $retainedArchive
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
    $placed = Save-TigerMarkViewWinGetWorkflowArtifact -Client $Client -Artifact $artifact `
        -ReleaseRoot $releaseRoot -Version $Version -ArchivePath $ArchivePath -Force:$Force

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

function New-TigerMarkViewWinGetCheck {
    <#
        .SYNOPSIS
        Records one named observation about a release's WinGet readiness.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('PASS', 'WARN', 'FAIL')]
        [string] $Status,

        [Parameter(Mandatory)]
        [string] $Message
    )

    [pscustomobject][ordered]@{ name = $Name; status = $Status; message = $Message }
}

function New-TigerMarkViewWinGetAssertion {
    <#
        .SYNOPSIS
        Turns a condition into a PASS or FAIL check.

        .DESCRIPTION
        Reporting rather than throwing is deliberate: one run should show every
        disagreement between the manifests and the published release, not stop at
        the first one a maintainer would then have to rediscover.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [string] $FailureMessage
    )

    if ($Condition) {
        New-TigerMarkViewWinGetCheck -Name $Name -Status 'PASS' -Message $Message
    }
    else {
        New-TigerMarkViewWinGetCheck -Name $Name -Status 'FAIL' -Message $FailureMessage
    }
}

function Get-TigerMarkViewWinGetVerdict {
    <#
        .SYNOPSIS
        Reduces a check list to PASS or FAIL.

        .DESCRIPTION
        A warning is something a maintainer must read, not something that blocks a
        submission; only a FAIL does that. An empty check list is a FAIL, because
        nothing was proven.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Checks
    )

    $failed = @($Checks | Where-Object { $_.status -ceq 'FAIL' })
    $warned = @($Checks | Where-Object { $_.status -ceq 'WARN' })
    $passed = @($Checks | Where-Object { $_.status -ceq 'PASS' })

    [pscustomobject][ordered]@{
        status = if (@($Checks).Count -eq 0 -or $failed.Count -gt 0) { 'FAIL' } else { 'PASS' }
        passed = $passed.Count
        warned = $warned.Count
        failed = $failed.Count
        total = @($Checks).Count
    }
}

function Format-TigerMarkViewWinGetSummary {
    <#
        .SYNOPSIS
        Renders a readiness result as coloured lines.

        .DESCRIPTION
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
            default { 'Red' }
        }
        & $line ('  {0,-4} {1,-34} {2}' -f $check.status, $check.name, $check.message) $colour
    }

    & $line
    & $line "  $($Result.summary.passed) passed, $($Result.summary.warned) warned, $($Result.summary.failed) failed"
    & $line "  Installer: $($Result.installer.url)"
    & $line "  Published SHA-256: $($Result.installer.publishedSha256)"
    if ($null -ne $Result.PSObject.Properties['provenance'] -and $null -ne $Result.provenance) {
        & $line
        & $line "  Sealed artifact: $($Result.provenance.artifactName)"
        & $line "    Workflow run $($Result.provenance.workflowRunId) at commit $($Result.provenance.commit)"
        & $line "    Archive SHA-256: $($Result.provenance.archiveSha256)"
    }
    & $line
    & $line "  Files ready, unchanged, for microsoft/winget-pkgs at $($Result.submission.path):"
    foreach ($file in @($Result.submission.files)) {
        & $line "    $($file.name)"
        & $line "      $($file.sourcePath)"
    }
    & $line "  Submission digest: $($Result.submission.digest)"
    & $line
    & $line "  Machine-readable result: $($Result.resultPath)"

    & $line
    if ($Result.status -ceq 'PASS') {
        & $line "PASS: TigerMarkView $($Result.version) is ready for a winget-pkgs pull request." 'Green'
    }
    else {
        & $line "FAIL: TigerMarkView $($Result.version) is not ready for a winget-pkgs pull request." 'Red'
    }
}
