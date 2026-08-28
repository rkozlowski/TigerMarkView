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
        throw ("Prepared WinGet manifest directory not found: $ManifestDirectory. " +
            'Run eng\winget\Prepare-TigerMarkViewWinGet.ps1, or extract the release ' +
            "workflow's TigerMarkView-WinGet-$Version-<commit> artifact into it.")
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
