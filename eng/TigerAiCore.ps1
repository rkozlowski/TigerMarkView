#Requires -Version 7.0
<#
    .SYNOPSIS
    TigerAiCore resource discovery for TigerMarkView engineering scripts.

    .DESCRIPTION
    TigerMarkView is one project inside the TigerAiCore ecosystem, and it must not
    know where the rest of that ecosystem lives. The machine states that once, in
    the TOML file named by the TigerAiCoreConfig environment variable, and every
    Lab or shared tool this repository uses is resolved from there.

    That is the whole discovery rule. There is deliberately no sibling-checkout
    guess, no per-resource environment variable, and no hardcoded C:\Projects path:
    a wrong Lab is worse than a missing one, because it silently validates a
    release against something nobody chose. When the configuration is absent or
    does not register the resource, resolution reports why and the caller records
    the check as not run. It never falls back.

    An explicit path passed by the operator still wins, because that is a decision
    rather than a guess.

    The configuration holds locations and non-secret integration metadata only.
    Credentials never belong in it, so nothing here reads or forwards secrets.

    Dot-source this file:

        . (Join-Path $PSScriptRoot '..\TigerAiCore.ps1')
#>

Set-StrictMode -Version Latest

$script:TigerAiCoreConfigurationVariable = 'TigerAiCoreConfig'

function ConvertFrom-TigerAiCoreToml {
    <#
        .SYNOPSIS
        Reads the small TOML subset TigerAiCore configuration uses.

        .DESCRIPTION
        PowerShell has no TOML reader, and taking a dependency to parse four kinds
        of line would be worse than reading them. Supported: comments, blank lines,
        `[table]` and `[table.sub]` headers, and `key = "value"` with basic or
        literal strings.

        Anything else throws. A configuration line this cannot read is ambiguous,
        and guessing at it is how a script ends up pointed somewhere nobody meant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Origin
    )

    $root = [ordered] @{}
    $table = $root
    $lineNumber = 0

    foreach ($rawLine in ($Text -split "\r?\n")) {
        $lineNumber++
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }

        if ($line.StartsWith('[')) {
            if (-not ($line -match '^\[\s*([^\]]+?)\s*\]$')) {
                throw "$Origin line ${lineNumber}: '$rawLine' is not a table header this reader understands."
            }

            $table = $root
            foreach ($segment in ($Matches[1] -split '\.')) {
                $key = $segment.Trim()
                if ($key.Length -eq 0) {
                    throw "$Origin line ${lineNumber}: '$rawLine' contains an empty table name."
                }

                if (-not $table.Contains($key)) { $table[$key] = [ordered] @{} }
                $table = $table[$key]
            }

            continue
        }

        if (-not ($line -match '^([^=\s]+)\s*=\s*(.+)$')) {
            throw "$Origin line ${lineNumber}: '$rawLine' is not a key/value assignment this reader understands."
        }

        $name = $Matches[1]
        $literal = $Matches[2].Trim()
        $table[$name] = ConvertFrom-TigerAiCoreTomlString -Literal $literal -Origin $Origin -LineNumber $lineNumber
    }

    return $root
}

function ConvertFrom-TigerAiCoreTomlString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Literal,

        [Parameter(Mandatory)]
        [string] $Origin,

        [Parameter(Mandatory)]
        [int] $LineNumber
    )

    if ($Literal.StartsWith("'") -and $Literal.EndsWith("'") -and $Literal.Length -ge 2) {
        # A TOML literal string has no escapes at all, which is why Windows paths
        # are usually written this way.
        return $Literal.Substring(1, $Literal.Length - 2)
    }

    if ($Literal.StartsWith('"') -and $Literal.EndsWith('"') -and $Literal.Length -ge 2) {
        $body = $Literal.Substring(1, $Literal.Length - 2)
        $builder = [Text.StringBuilder]::new()
        for ($index = 0; $index -lt $body.Length; $index++) {
            $character = $body[$index]
            if ($character -ne '\') {
                [void] $builder.Append($character)
                continue
            }

            $index++
            if ($index -ge $body.Length) {
                throw "$Origin line ${LineNumber}: the string value ends with an incomplete escape."
            }

            switch ($body[$index]) {
                '\' { [void] $builder.Append('\') }
                '"' { [void] $builder.Append('"') }
                'n' { [void] $builder.Append("`n") }
                'r' { [void] $builder.Append("`r") }
                't' { [void] $builder.Append("`t") }
                default {
                    throw "$Origin line ${LineNumber}: '\$($body[$index])' is not an escape this reader understands."
                }
            }
        }

        return $builder.ToString()
    }

    throw "$Origin line ${LineNumber}: '$Literal' is not a quoted string; only string values are supported."
}

function Get-TigerAiCoreConfiguration {
    <#
        .SYNOPSIS
        Loads the TigerAiCore configuration named by TigerAiCoreConfig.

        .DESCRIPTION
        Always returns a result. `Available` says whether the configuration was
        read; `Reason` says why not, in words a maintainer can act on. Only a file
        that exists but cannot be read as configuration throws, because that is a
        broken machine rather than an unconfigured one.

        .PARAMETER ConfigurationPath
        An explicit configuration file, for tests and for a maintainer pointing at
        a different machine profile. Defaults to the TigerAiCoreConfig value.
    #>
    [CmdletBinding()]
    param(
        [string] $ConfigurationPath
    )

    $source = 'the -ConfigurationPath argument'
    if ([string]::IsNullOrWhiteSpace($ConfigurationPath)) {
        $ConfigurationPath = [Environment]::GetEnvironmentVariable($script:TigerAiCoreConfigurationVariable)
        $source = "the $($script:TigerAiCoreConfigurationVariable) environment variable"
    }

    if ([string]::IsNullOrWhiteSpace($ConfigurationPath)) {
        return [pscustomobject] [ordered] @{
            Available = $false
            Path      = $null
            Source    = $source
            Reason    = "$($script:TigerAiCoreConfigurationVariable) is not set, so TigerAiCore and its configured Labs and tools are unavailable."
            Document  = $null
        }
    }

    $ConfigurationPath = [IO.Path]::GetFullPath($ConfigurationPath)
    if (-not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf)) {
        return [pscustomobject] [ordered] @{
            Available = $false
            Path      = $ConfigurationPath
            Source    = $source
            Reason    = "The TigerAiCore configuration named by $source was not found at '$ConfigurationPath'."
            Document  = $null
        }
    }

    $text = Get-Content -LiteralPath $ConfigurationPath -Raw
    $document = ConvertFrom-TigerAiCoreToml -Text $text -Origin "TigerAiCore configuration '$ConfigurationPath'"

    return [pscustomobject] [ordered] @{
        Available = $true
        Path      = $ConfigurationPath
        Source    = $source
        Reason    = $null
        Document  = $document
    }
}

function Get-TigerAiCoreResource {
    <#
        .SYNOPSIS
        Resolves one registered Lab or tool from the TigerAiCore configuration.

        .DESCRIPTION
        Reports availability instead of throwing, so a caller can record a missing
        Lab as a check that did not run rather than as a crash. `Type` and
        `RequiredCommand` are verified when supplied: a registered entry of the
        wrong type, or one whose entry point is absent, is a misconfiguration, and
        reporting it here is the difference between a clear message and a failure
        deep inside a scenario.

        .PARAMETER Section
        The configuration section, `labs` or `tools`.

        .PARAMETER Name
        The registered resource name, for example TigerWinLab.

        .PARAMETER Type
        The capability the caller depends on, for example WindowsLab. A registered
        entry of a different type is refused rather than used.

        .PARAMETER RequiredCommand
        Entry-point files that must exist under a resolved directory.

        .PARAMETER Path
        An explicit path supplied by the operator. It wins over configuration and
        is still checked, because an explicit choice deserves the same proof.

        .PARAMETER ConfigurationPath
        Passed through to Get-TigerAiCoreConfiguration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('labs', 'tools')]
        [string] $Section,

        [Parameter(Mandatory)]
        [string] $Name,

        [string] $Type,

        [string[]] $RequiredCommand = @(),

        [string] $Path,

        [string] $ConfigurationPath
    )

    $result = [ordered] @{
        Available         = $false
        Name              = $Name
        Type              = $null
        ExpectedType      = $Type
        Path              = $null
        Source            = $null
        Reason            = $null
        ConfigurationPath = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $result.Path = [IO.Path]::GetFullPath($Path)
        $result.Source = "an explicit path"
        $result.Type = $Type
    }
    else {
        $configuration = Get-TigerAiCoreConfiguration -ConfigurationPath $ConfigurationPath
        $result.ConfigurationPath = $configuration.Path
        if (-not $configuration.Available) {
            $result.Reason = $configuration.Reason
            return [pscustomobject] $result
        }

        $document = $configuration.Document
        if (-not $document.Contains($Section) -or -not $document[$Section].Contains($Name)) {
            $result.Reason = "$Name is not registered under [$Section] in '$($configuration.Path)'."
            return [pscustomobject] $result
        }

        $entry = $document[$Section][$Name]
        if (-not $entry.Contains('path') -or [string]::IsNullOrWhiteSpace([string] $entry['path'])) {
            $result.Reason = "[$Section.$Name] in '$($configuration.Path)' declares no path."
            return [pscustomobject] $result
        }

        $result.Type = if ($entry.Contains('type')) { [string] $entry['type'] } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($Type) -and $result.Type -ne $Type) {
            $result.Reason = "[$Section.$Name] in '$($configuration.Path)' is type '$($result.Type)', not the required '$Type'."
            return [pscustomobject] $result
        }

        $result.Path = [IO.Path]::GetFullPath([string] $entry['path'])
        $result.Source = "the TigerAiCore configuration '$($configuration.Path)'"
    }

    if ($Section -eq 'labs') {
        if (-not (Test-Path -LiteralPath $result.Path -PathType Container)) {
            $result.Reason = "$Name was resolved from $($result.Source) to '$($result.Path)', which is not a directory."
            return [pscustomobject] $result
        }
    }
    elseif (-not (Test-Path -LiteralPath $result.Path)) {
        $result.Reason = "$Name was resolved from $($result.Source) to '$($result.Path)', which does not exist."
        return [pscustomobject] $result
    }

    foreach ($command in $RequiredCommand) {
        if (-not (Test-Path -LiteralPath (Join-Path $result.Path $command) -PathType Leaf)) {
            $result.Reason = "$Name at '$($result.Path)' (from $($result.Source)) does not provide '$command'."
            return [pscustomobject] $result
        }
    }

    $result.Available = $true
    return [pscustomobject] $result
}

function Get-TigerAiCoreLab {
    <#
        .SYNOPSIS
        Resolves a registered Lab. See Get-TigerAiCoreResource.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [string] $Type,

        [string[]] $RequiredCommand = @(),

        [string] $Path,

        [string] $ConfigurationPath
    )

    return Get-TigerAiCoreResource -Section 'labs' -Name $Name -Type $Type `
        -RequiredCommand $RequiredCommand -Path $Path -ConfigurationPath $ConfigurationPath
}

function Assert-TigerAiCoreLab {
    <#
        .SYNOPSIS
        Resolves a registered Lab and throws when it is unavailable.

        .DESCRIPTION
        For scripts whose whole purpose is the Lab run. The message says what was
        missing and how the machine is expected to declare it, because a
        maintainer meeting this for the first time should not have to read the
        discovery code to fix it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [string] $Type,

        [string[]] $RequiredCommand = @(),

        [string] $Path,

        [string] $ConfigurationPath
    )

    $lab = Get-TigerAiCoreLab -Name $Name -Type $Type -RequiredCommand $RequiredCommand `
        -Path $Path -ConfigurationPath $ConfigurationPath
    if ($lab.Available) { return $lab }

    throw ("$Name is unavailable: $($lab.Reason) " +
        "Register it as [labs.$Name] with type '$Type' and a path in the TOML file named by " +
        "$($script:TigerAiCoreConfigurationVariable), or pass the path explicitly.")
}
