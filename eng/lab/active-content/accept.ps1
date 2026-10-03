<#
    .SYNOPSIS
    TigerWinLab guest payload: proves the active-content boundary in the real viewer and in tiger-mark.

    .DESCRIPTION
    Runs inside a TigerWinLab -Desktop job (Windows PowerShell 5.1, session 0, as LabAdmin), with the
    interactive session reached through $TigerWinLabDesktop. A loopback request logger stands in for
    "the network": hostile.md aims every active construct at /exfil/<vector> and its passive remote
    images at /img/, so the log is the oracle. The same document is then opened in TigerMarkView and
    converted by tiger-mark.

    Writes the phase/check result to TIGERWINLAB_JOB_RESULT and exits 0 only when every check passes.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Port = 47631
$Root = 'C:\TigerMarkViewAcceptance'
$AppRoot = Join-Path $Root 'app'
$DocRoot = Join-Path $Root 'documents'
$RequestLog = Join-Path $Root 'requests.log'
$Artifacts = $env:TIGERWINLAB_JOB_ARTIFACTS
$PassiveImages = @('/img/passive-markdown.png', '/img/passive-html.png')
$ShareRoot = Join-Path $Root 'share'
$MappedShareRoot = Join-Path $Root 'mapped'
# Every image file the documents name on either share; none of them may ever be asked for.
# \\127.0.0.1\tmvprobe never gets a drive letter and is the strict oracle: nothing in the guest but a
# document can lead a process to it. \\127.0.0.1\tmvmapped is what Z: and the Y: alias reach; the
# shell inspects a drive letter it has just been shown on its own, so only file opens count there.
$ShareImages = @(
    'html-backslash.png', 'html-slash.png', 'html-file.png', 'html-file-four.png', 'html-encoded.png',
    'markdown-slash.png', 'markdown-backslash.png', 'css-background.png', 'same-href.png', 'mapped.png', 'boundary.png', 'lifecycle.png'
)
# The print palette's keyword and comment colours, and the light screen theme's keyword colour.
$PrintKeyword = @(11, 61, 145)
$PrintComment = @(79, 91, 102)
$ScreenKeyword = @(207, 34, 46)

$phases = New-Object System.Collections.Generic.List[object]
$listener = $null

function New-Check {
    param([string] $Name, [string] $Code, [bool] $Passed, [string] $Message)
    $status = 'FAIL'
    if ($Passed) { $status = 'PASS' }
    [pscustomobject][ordered]@{ name = $Name; code = $Code; status = $status; message = $Message }
}

function Add-Phase {
    param([string] $Name, [object[]] $Checks)
    $status = 'PASS'
    if (@($Checks | Where-Object { $_.status -ne 'PASS' }).Count -gt 0) { $status = 'FAIL' }
    $phases.Add([pscustomobject][ordered]@{ name = $Name; status = $status; checks = @($Checks) })
}

function Get-Requests {
    # The logger appends one line per request; a read can race an append, so retry briefly.
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            if (-not (Test-Path -LiteralPath $RequestLog)) { return @() }
            return @(Get-Content -LiteralPath $RequestLog -Encoding UTF8 | ForEach-Object {
                    $parts = $_ -split "`t", 2
                    $target = (($parts[1] -split ' ')[1])
                    [pscustomobject]@{ at = $parts[0]; line = $parts[1]; path = ($target -split '\?')[0] }
                })
        }
        catch { Start-Sleep -Milliseconds 100 }
    }
    throw 'The request log could not be read.'
}

function Get-RequestsSince {
    param([int] $Mark)
    @(Get-Requests | Select-Object -Skip $Mark)
}

function Wait-PassiveImages {
    param([int] $Mark, [int] $TimeoutSeconds)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $paths = @(Get-RequestsSince -Mark $Mark | ForEach-Object { $_.path })
        if (@($PassiveImages | Where-Object { $paths -notcontains $_ }).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    $false
}

function Get-ImageObjectCount {
    param([string] $PdfPath)
    if (-not (Test-Path -LiteralPath $PdfPath)) { return -1 }
    $text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($PdfPath))
    ([regex]::Matches($text, '/Subtype\s*/Image')).Count
}

function Format-Paths {
    param([object[]] $Requests)
    $paths = @($Requests | ForEach-Object { $_.path } | Sort-Object -Unique)
    if ($paths.Count -eq 0) { return '(none)' }
    $paths -join ', '
}

function Join-Names {
    param([object[]] $Items)
    $unique = @($Items | Sort-Object -Unique)
    if ($unique.Count -eq 0) { return '(none)' }
    $unique -join ', '
}

# What the shell opens by itself on a drive letter it has just been shown: the root, then the files
# that customise a drive's icon and label. A document cannot cause these; an image request names its file.
$ShellDriveNames = @('\', 'AutoRun.inf', 'Desktop.ini')

function Get-ShareAccessRecords {
    # Detailed File Share auditing (event 5145) records every file an SMB client asked a share for;
    # the relative target name is the file, and the event names the account but never the process.
    # Returns one record per access to either probe share since $Since, oldest first.
    param([DateTime] $Since)
    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 5145; StartTime = $Since } -ErrorAction Stop) } catch { $events = @() }
    @($events | Where-Object { $_.TimeCreated -ge $Since } | Sort-Object TimeCreated | ForEach-Object {
            $data = @{}
            foreach ($node in ([xml] $_.ToXml()).Event.EventData.Data) { $data[$node.Name] = [string] $node.'#text' }
            $share = [string] $data['ShareName']
            if ($share -like '*\tmvprobe' -or $share -like '*\tmvmapped') {
                [pscustomobject]@{
                    share = $share.Substring($share.LastIndexOf('\') + 1)
                    name = [string] $data['RelativeTargetName']
                    at = $_.TimeCreated
                    accessMask = [string] $data['AccessMask']
                }
            }
        })
}

function Get-ShareAccess {
    # The names asked for on the strict share (or on -Share) since $Since.
    param([DateTime] $Since, [string] $Share = 'tmvprobe')
    @(Get-ShareAccessRecords -Since $Since | Where-Object { $_.share -eq $Share } | ForEach-Object { $_.name } | Where-Object { $_ })
}

function Select-DocumentShareAccess {
    # Keeps the accesses a document could have caused: anything on the strict share, and file opens on
    # the mapped share. Root and shell-metadata opens on the mapped share are the shell's own reaction
    # to a drive letter and cannot be attributed to any process.
    param([object[]] $Records)
    @($Records | Where-Object { $_.share -eq 'tmvprobe' -or ($ShellDriveNames -notcontains $_.name) })
}

function Get-DocumentShareAccess {
    # The accesses a document could have caused, on either share, since $Since, as share:name.
    param([DateTime] $Since)
    @(Select-DocumentShareAccess -Records @(Get-ShareAccessRecords -Since $Since) | ForEach-Object { "$($_.share):$($_.name)" })
}

function Format-ShareAccess {
    # Every access on both shares since $Since, with its time and access mask, for check messages.
    param([DateTime] $Since)
    $records = @(Get-ShareAccessRecords -Since $Since)
    if ($records.Count -eq 0) { return '(none)' }
    @($records | ForEach-Object { "$($_.share):$($_.name) at $($_.at.ToString('HH:mm:ss.fff')) mask $($_.accessMask)" }) -join '; '
}

function Wait-ShareAccess {
    param([DateTime] $Since, [string] $Name, [int] $TimeoutSeconds)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (@(Get-ShareAccess -Since $Since) -contains $Name) { return $true }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    $false
}

function Wait-Request {
    param([int] $Mark, [string] $Path, [int] $TimeoutSeconds)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (@(Get-RequestsSince -Mark $Mark | Where-Object { $_.path -eq $Path }).Count -gt 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    $false
}

function Wait-File {
    param([string] $Path, [int] $TimeoutSeconds)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if ((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length -gt 0) {
            Start-Sleep -Seconds 1
            return $true
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    $false
}

function Get-ImageSize {
    # A loaded 48x48 picture is laid out square and at least 48 px at 100% scale; a broken one shows
    # its alternative text instead, which is not square.
    param([int64] $Hwnd, [string] $Name)
    $found = $null
    try {
        $found = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-wait -Parameters @{ selector = @{ hwnd = $Hwnd; scope = 'descendants'; name = "^$([regex]::Escape($Name))$"; index = 0 }; timeoutSeconds = 60 }
    }
    catch { $found = $null }
    $bounds = $null
    if ($null -ne $found -and $null -ne $found.element) { $bounds = $found.element.bounds }
    $rendered = $null -ne $bounds -and $bounds.height -ge 40 -and [math]::Abs($bounds.width - $bounds.height) -le 4
    $description = "no element named '$Name'"
    if ($null -ne $bounds) { $description = "$($bounds.width)x$($bounds.height)" }
    [pscustomobject]@{ rendered = $rendered; description = $description }
}

function Find-Text {
    param([int64] $Hwnd, [string] $Pattern)
    try {
        $found = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-find -Parameters @{ selector = @{ hwnd = $Hwnd; scope = 'descendants'; name = $Pattern; index = 0 } }
        return [bool] $found.found
    }
    catch { return $false }
}

function Get-ColourPixelCount {
    # Pixels within a tolerance of one colour in a capture: how highlighting is seen on screen.
    param([string] $PngPath, [int] $R, [int] $G, [int] $B, [int] $Tolerance)
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap $PngPath
    try {
        $rectangle = New-Object System.Drawing.Rectangle 0, 0, $bitmap.Width, $bitmap.Height
        $data = $bitmap.LockBits($rectangle, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bytes = New-Object byte[] ($data.Stride * $bitmap.Height)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
        $bitmap.UnlockBits($data)
    }
    finally { $bitmap.Dispose() }
    $count = 0
    for ($i = 0; $i -lt $bytes.Length; $i += 4) {
        if ([math]::Abs($bytes[$i + 2] - $R) -le $Tolerance -and [math]::Abs($bytes[$i + 1] - $G) -le $Tolerance -and [math]::Abs($bytes[$i] - $B) -le $Tolerance) { $count++ }
    }
    $count
}

function Test-PdfHasColour {
    # Whether any content stream of a PDF paints with the given fill colour: how highlighting is seen
    # in a PDF, since the print palette is distinct from every other colour a document uses.
    param([string] $PdfPath, [int] $R, [int] $G, [int] $B)
    if (-not (Test-Path -LiteralPath $PdfPath)) { return $false }
    $bytes = [IO.File]::ReadAllBytes($PdfPath)
    $latin = [Text.Encoding]::GetEncoding(28591)
    $text = $latin.GetString($bytes)
    foreach ($match in [regex]::Matches($text, 'stream\r?\n')) {
        $start = $match.Index + $match.Length
        $end = $text.IndexOf('endstream', $start)
        if ($end -le $start + 2) { continue }
        $content = $null
        try {
            $stream = New-Object IO.MemoryStream (, $bytes[($start + 2)..($end - 1)])
            $deflate = New-Object IO.Compression.DeflateStream ($stream, [IO.Compression.CompressionMode]::Decompress)
            $content = (New-Object IO.StreamReader ($deflate, $latin)).ReadToEnd()
        }
        catch { $content = $null }
        if (-not $content) { continue }
        foreach ($m in [regex]::Matches($content, '(?<r>[0-9]*\.?[0-9]+)\s+(?<g>[0-9]*\.?[0-9]+)\s+(?<b>[0-9]*\.?[0-9]+)\s+(?:rg|sc|scn)\b')) {
            if ([math]::Abs([double] $m.Groups['r'].Value - $R / 255) -le 0.006 -and
                [math]::Abs([double] $m.Groups['g'].Value - $G / 255) -le 0.006 -and
                [math]::Abs([double] $m.Groups['b'].Value - $B / 255) -le 0.006) { return $true }
        }
    }
    $false
}

function Invoke-UserScript {
    # A Windows PowerShell script run as the interactive user, whose profile and hive the viewer uses.
    param([string] $Script, [int] $TimeoutSeconds = 120)
    Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'powershell.exe'; arguments = @('-NoProfile', '-NonInteractive', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))); timeoutSeconds = $TimeoutSeconds }
}

function Set-UserSettings {
    # Merges properties into the interactive user's settings.json, as a reader editing it would.
    param([hashtable] $Values, [switch] $Replace)
    $json = ($Values | ConvertTo-Json -Compress -Depth 4).Replace("'", "''")
    $merge = 'if (Test-Path $p) { $s = Get-Content -Raw $p | ConvertFrom-Json } else { $s = New-Object psobject }; ' +
        'foreach ($v in ($n.PSObject.Properties)) { $s | Add-Member -NotePropertyName $v.Name -NotePropertyValue $v.Value -Force }; '
    if ($Replace) { $merge = '$s = $n; ' }
    $script = '$d = Join-Path $env:LOCALAPPDATA ''TigerMarkView''; $null = New-Item -ItemType Directory -Force $d; $p = Join-Path $d ''settings.json''; ' +
        "`$n = '$json' | ConvertFrom-Json; " + $merge +
        '[IO.File]::WriteAllText($p, ($s | ConvertTo-Json -Depth 6))'
    $run = Invoke-UserScript -Script $script
    if ($run.exitCode -ne 0) { throw "Could not write the interactive user's settings: $(@($run.stderr) -join ' ')" }
}

function Get-UserSettings {
    $run = Invoke-UserScript -Script 'Get-Content -Raw (Join-Path $env:LOCALAPPDATA ''TigerMarkView\settings.json'')'
    if ($run.exitCode -ne 0) { return $null }
    try { return (@($run.stdout) -join "`n") | ConvertFrom-Json } catch { return $null }
}

function Test-SameFile {
    param([string] $Left, [string] $Right)
    [string]::Equals([IO.Path]::GetFullPath($Left), [IO.Path]::GetFullPath($Right), [StringComparison]::OrdinalIgnoreCase)
}

function Close-Viewer {
    # A normal close, so the window runs its closing writes; then make sure the process is gone.
    param([object] $Window, [int] $ProcessId)
    if ($null -ne $Window) {
        try { $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $Window.hwnd; action = 'close'; settleMilliseconds = 1000 } } catch { }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline -and $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 250 }
    $null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Invoke-MenuPath {
    # Avalonia's menus expose no UIA invoke or expand pattern, so they are driven by real pointer input;
    # a submenu is a popup window of the viewer's process, found by its items' automation ids or names.
    param([object] $Window, [int] $ProcessId, [hashtable[]] $Path)
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $Window.hwnd; action = 'activate'; settleMilliseconds = 1000 }
    $first = $true
    foreach ($step in $Path) {
        $selector = @{ index = 0 }
        foreach ($key in $step.Keys) { $selector[$key] = $step[$key] }
        if ($first) { $selector.hwnd = [int64] $Window.hwnd; $selector.scope = 'descendants' } else { $selector.processId = $ProcessId }
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-wait -Parameters @{ selector = $selector; timeoutSeconds = 15 }
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = $selector; action = 'click'; settleMilliseconds = 800 }
        $first = $false
    }
}

function Find-EngineMarkers {
    # Every file under the interactive user's TigerMarkView WebView2 folders (or -Root) that contains one
    # of the markers, as UTF-8 or UTF-16 text: how a browsing record would show up, whatever its format.
    param([string[]] $Markers, [string] $Root)
    $rootExpression = if ($Root) { "'" + $Root.Replace("'", "''") + "'" } else { '(Join-Path $env:LOCALAPPDATA ''TigerMarkView\WebView2'')' }
    $list = ($Markers | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ','
    # A file that cannot be read is counted, never silently skipped: a locked History could otherwise
    # hide exactly the record the scan is looking for.
    $script = '$root = ' + $rootExpression + '; $markers = @(' + $list + '); $hits = @(); $unreadable = @(); $files = 0; ' +
        'if (Test-Path $root) { foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)) { $files++; ' +
        'try { $s = New-Object IO.FileStream($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)); ' +
        'try { $b = New-Object byte[] $s.Length; $null = $s.Read($b, 0, $b.Length) } finally { $s.Dispose() } } catch { $unreadable += $f.FullName; continue }; ' +
        '$t8 = [Text.Encoding]::UTF8.GetString($b); $t16 = [Text.Encoding]::Unicode.GetString($b); ' +
        'foreach ($m in $markers) { if ($t8.Contains($m) -or $t16.Contains($m)) { $hits += ($f.FullName + '' => '' + $m) } } } }; ' +
        '$history = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -Filter History -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName + '' ('' + $_.Length + '' bytes)'' }); ' +
        '[pscustomobject]@{ root = $root; files = $files; hits = @($hits); unreadable = @($unreadable); history = @($history) } | ConvertTo-Json -Compress'
    $run = Invoke-UserScript -Script $script -TimeoutSeconds 300
    $parsed = $null
    try { $parsed = (@($run.stdout) -join "`n") | ConvertFrom-Json } catch { $parsed = $null }
    if ($run.exitCode -ne 0 -or $null -eq $parsed) { throw "The engine-folder scan failed (exit $($run.exitCode)): $(@($run.stderr) -join ' ')" }
    $parsed
}

function Invoke-GuiExport {
    # File > Export to PDF through the toolbar button and the real Save dialog; returns whether the dialog
    # was found and the PDF written.
    param([object] $Window, [int] $ProcessId, [string] $PdfPath)
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-invoke -Parameters @{ selector = @{ hwnd = [int64] $Window.hwnd; scope = 'descendants'; automationId = 'ExportPdfToolbarButton'; index = 0 }; pattern = 'invoke'; settleMilliseconds = 500 }
    $dialog = $null
    try { $dialog = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $ProcessId; titlePattern = '^Export to PDF$'; timeoutSeconds = 30 } } catch { $dialog = $null }
    if ($null -ne $dialog) {
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $dialog.hwnd; action = 'activate'; settleMilliseconds = 500 }
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command keyboard -Parameters @{ action = 'sequence'; sequence = @(@{ action = 'down'; key = 'ControlKey' }, @{ action = 'down'; key = 'A' }, @{ action = 'up'; key = 'A' }, @{ action = 'up'; key = 'ControlKey' }) }
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command keyboard -Parameters @{ action = 'text'; text = $PdfPath; settleMilliseconds = 500 }
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command keyboard -Parameters @{ action = 'keys'; keys = @('Enter') }
    }
    [pscustomobject]@{ dialog = $null -ne $dialog; exported = (Wait-File -Path $PdfPath -TimeoutSeconds 90) }
}

function Invoke-Cli {
    param([string[]] $Arguments)
    Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = $cliExe; arguments = $Arguments; workingDirectory = $DocRoot; timeoutSeconds = 180 }
}

function Test-CliCreated {
    param([object] $Run, [string] $Pdf)
    $created = @($Run.stdout | Where-Object { $_ -like 'Created: *' }).Count -eq 1
    $Run.exitCode -eq 0 -and $created -and (Test-Path -LiteralPath $Pdf)
}

try {
    # --- staging ---------------------------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]

    if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $AppRoot, $DocRoot -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $PSScriptRoot 'app.zip'), $AppRoot)
    $viewerExe = Join-Path $AppRoot 'TigerMarkView.exe'
    $cliExe = Join-Path $AppRoot 'tiger-mark.exe'

    foreach ($document in @('hostile.md', 'shares.md', 'code.md')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $document) -Destination $DocRoot
    }
    Set-Content -LiteralPath (Join-Path $DocRoot 'local-only.md') -Value "# Local image only`r`n`r`n![Local only](local.png)`r`n" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $DocRoot 'no-image.md') -Value "# No images`r`n`r`nText only.`r`n" -Encoding UTF8
    # Links to Markdown on the strict share and through the mapped drive, and a local control link.
    Set-Content -LiteralPath (Join-Path $DocRoot 'links.md') -Encoding UTF8 -Value (
        "# Links`r`n`r`n<a href=`"\\127.0.0.1\tmvprobe\linked.md`">Share link</a>`r`n`r`n<a href=`"//127.0.0.1/tmvprobe/linked-slash.md`">Slash share link</a>`r`n`r`n" +
        "[Mapped drive link](file:///Z:/linked-mapped.md)`r`n`r`n[Local link](local-target.md)`r`n")
    Set-Content -LiteralPath (Join-Path $DocRoot 'local-target.md') -Value "# Local target`r`n`r`nReached by a link.`r`n" -Encoding UTF8
    # A web image only a proxy can reach: the guest has no network and the name does not resolve.
    Set-Content -LiteralPath (Join-Path $DocRoot 'proxy.md') -Encoding UTF8 -Value (
        "# Proxy`r`n`r`n![Proxied image](http://tmv-proxy.invalid/img/proxied.png)`r`n`r`n![Local image](local.png)`r`n")
    foreach ($name in @('mw-a.md', 'mw-b.md', 'seed-1.md', 'seed-2.md')) {
        Set-Content -LiteralPath (Join-Path $DocRoot $name) -Value "# $name`r`n`r`nMulti-window fixture.`r`n" -Encoding UTF8
    }

    # A real 48x48 picture, so a rendered local image has a size a broken one cannot have.
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 48, 48
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::SteelBlue)
    $graphics.Dispose()
    $bitmap.Save((Join-Path $DocRoot 'local.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()

    # The interactive standard user runs both programs and tiger-mark writes its PDFs beside the input.
    $null = & icacls.exe $AppRoot '/grant' 'Users:(OI)(CI)RX' '/T' '/Q' 2>&1
    $appAcl = $LASTEXITCODE -eq 0
    $null = & icacls.exe $DocRoot '/grant' 'Users:(OI)(CI)M' '/T' '/Q' 2>&1
    $docAcl = $LASTEXITCODE -eq 0
    $checks.Add((New-Check 'Application staged' 'stage.app' ((Test-Path $viewerExe) -and (Test-Path $cliExe) -and $appAcl -and $docAcl) "TigerMarkView.exe and tiger-mark.exe staged under $AppRoot, documents under $DocRoot."))

    # The request logger: every request line, answered with a 1x1 PNG so any image request succeeds.
    $listener = Start-Job -ArgumentList $Port, $RequestLog -ScriptBlock {
        param($Port, $RequestLog)
        $png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==')
        $server = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), $Port
        $server.Start()
        while ($true) {
            $client = $server.AcceptTcpClient()
            try {
                $stream = $client.GetStream()
                $stream.ReadTimeout = 2000
                $buffer = New-Object byte[] 65536
                $read = 0
                try { $read = $stream.Read($buffer, 0, $buffer.Length) } catch { $read = 0 }
                if ($read -gt 0) {
                    $line = ([Text.Encoding]::ASCII.GetString($buffer, 0, $read) -split "`r`n")[0]
                    if ($line) {
                        Add-Content -LiteralPath $RequestLog -Value ([DateTimeOffset]::Now.ToString('o') + "`t" + $line) -Encoding UTF8
                    }
                    $target = ($line -split ' ')[1]
                    if ($target -like 'http://tmv-proxy.invalid/*') {
                        # Asked as a proxy for a web image: demand Windows sign-in, and record only
                        # whether a client offered credentials, never what it offered.
                        if ([Text.Encoding]::ASCII.GetString($buffer, 0, $read) -match '(?im)^Proxy-Authorization:') {
                            Add-Content -LiteralPath $RequestLog -Value ([DateTimeOffset]::Now.ToString('o') + "`tGET /proxy-auth-response HTTP/1.1") -Encoding UTF8
                        }
                        $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 407 Proxy Authentication Required`r`nProxy-Authenticate: NTLM`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                        $stream.Write($header, 0, $header.Length)
                        continue
                    }
                    if ($target -eq '/auth/ntlm') {
                        # Record only whether credentials were sent, never their contents.
                        if ([Text.Encoding]::ASCII.GetString($buffer, 0, $read) -match '(?im)^Authorization:') {
                            Add-Content -LiteralPath $RequestLog -Value ([DateTimeOffset]::Now.ToString('o') + "`tGET /auth-response HTTP/1.1") -Encoding UTF8
                        }
                        $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 401 Unauthorized`r`nWWW-Authenticate: NTLM`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                        $stream.Write($header, 0, $header.Length)
                        continue
                    }
                    $location = $null
                    if ($target -eq '/redirect/web') { $location = "http://127.0.0.1:$Port/img/redirected.png" }
                    if ($target -eq '/redirect/share') { $location = 'file://127.0.0.1/tmvprobe/boundary.png' }
                    if ($null -ne $location) {
                        $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 302 Found`r`nLocation: $location`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                        $stream.Write($header, 0, $header.Length)
                        continue
                    }
                    $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: image/png`r`nContent-Length: $($png.Length)`r`nConnection: close`r`n`r`n")
                    $stream.Write($header, 0, $header.Length)
                    $stream.Write($png, 0, $png.Length)
                }
            }
            catch { }
            finally { $client.Close() }
        }
    }

    # Prove the logger answers before anything depends on it, with a request of its own.
    $ready = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not $ready -and [DateTime]::UtcNow -lt $deadline) {
        try {
            $probe = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/probe/ready" -UseBasicParsing -TimeoutSec 5
            $ready = $probe.StatusCode -eq 200
        }
        catch { Start-Sleep -Milliseconds 500 }
    }
    $checks.Add((New-Check 'Request logger' 'stage.logger' ($ready -and (@(Get-Requests | Where-Object { $_.path -eq '/probe/ready' }).Count -ge 1)) "A loopback logger on port $Port records every request line and answers with an image."))

    # The network shares in this guest, each holding a file for every name a document aims at them, with
    # Detailed File Share auditing so each file an SMB client asks for is recorded against its share name.
    # PowerShell variable names are case-insensitive: the loop variable must not be spelled $shareRoot.
    foreach ($auditedRoot in @($ShareRoot, $MappedShareRoot)) {
        $null = New-Item -ItemType Directory -Path $auditedRoot -Force
        Set-Content -LiteralPath (Join-Path $auditedRoot 'control.txt') -Value 'control' -Encoding ASCII
        foreach ($name in $ShareImages + @('on-share.png', 'edge-control.png')) {
            Copy-Item -LiteralPath (Join-Path $DocRoot 'local.png') -Destination (Join-Path $auditedRoot $name)
        }
        $null = & icacls.exe $auditedRoot '/grant' 'Users:(OI)(CI)RX' '/T' '/Q' 2>&1
    }
    Set-Content -LiteralPath (Join-Path $ShareRoot 'on-share.md') -Encoding UTF8 -Value (
        "# On a share`r`n`r`n![Share web image](http://127.0.0.1:$Port/img/on-share-web.png)`r`n`r`n![Relative share image](on-share.png)`r`n`r`n" +
        "[Next on share](next-on-share.md)`r`n")
    foreach ($name in @('linked.md', 'linked-slash.md', 'next-on-share.md')) {
        Set-Content -LiteralPath (Join-Path $ShareRoot $name) -Value "# $name`r`n" -Encoding UTF8
    }
    Set-Content -LiteralPath (Join-Path $MappedShareRoot 'linked-mapped.md') -Value "# linked-mapped.md`r`n" -Encoding UTF8
    Start-Service -Name LanmanServer
    $null = New-SmbShare -Name 'tmvprobe' -Path $ShareRoot -ReadAccess 'Everyone'
    $null = New-SmbShare -Name 'tmvmapped' -Path $MappedShareRoot -ReadAccess 'Everyone'
    # remote-link is the relative-image fixture and keeps to the strict share; mapped-link is what the
    # Y: alias below is built on, so the shell's handling of that drive letter lands on the mapped share.
    $null = & cmd.exe /c mklink /D (Join-Path $DocRoot 'remote-link') '\\127.0.0.1\tmvprobe' 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the network symbolic-link fixture.' }
    $null = & cmd.exe /c mklink /D (Join-Path $DocRoot 'mapped-link') '\\127.0.0.1\tmvmapped' 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the mapped-share symbolic-link fixture.' }
    $null = & cmd.exe /c mklink /D (Join-Path $DocRoot 'local-link') $DocRoot 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the local symbolic-link fixture.' }
    # Detailed File Share, by GUID so the subcategory name's language does not matter.
    $null = & auditpol.exe /set '/subcategory:{0CCE9244-69AE-11D9-BED3-505054503030}' /success:enable /failure:enable 2>&1
    $auditOn = $LASTEXITCODE -eq 0
    $sharesUp = $null -ne (Get-SmbShare -Name 'tmvprobe' -ErrorAction SilentlyContinue) -and $null -ne (Get-SmbShare -Name 'tmvmapped' -ErrorAction SilentlyContinue)
    $checks.Add((New-Check 'Audited probe shares' 'stage.share' ($auditOn -and $sharesUp) "\\127.0.0.1\tmvprobe serves $ShareRoot and \\127.0.0.1\tmvmapped serves $MappedShareRoot, with Detailed File Share auditing on."))

    # The viewer runs with Syntax Highlighting on and the Export to PDF toolbar button shown, written
    # as the interactive user into that user's own settings file.
    $seed = '$d = Join-Path $env:LOCALAPPDATA ''TigerMarkView''; $null = New-Item -ItemType Directory -Force $d; ' +
        '[IO.File]::WriteAllText((Join-Path $d ''settings.json''), ''{ "syntaxHighlighting": true, "toolbarExportPdfVisible": true }'')'
    $seeded = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'powershell.exe'; arguments = @('-NoProfile', '-NonInteractive', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($seed))); timeoutSeconds = 60 }
    $checks.Add((New-Check 'Viewer settings seeded' 'stage.settings' ($seeded.exitCode -eq 0) "Syntax Highlighting and the Export to PDF toolbar button are on for the interactive user (exit $($seeded.exitCode); $(@($seeded.stderr) -join ' '))."))

    # What an earlier version's persistent engine profile left behind: a History file in each engine
    # folder's Default profile. The first viewer start and the first export must remove them.
    $residue = '$w = Join-Path $env:LOCALAPPDATA ''TigerMarkView\WebView2''; foreach ($f in ''Viewer'', ''Export'') { ' +
        '$d = Join-Path $w ($f + ''\EBWebView\Default''); $null = New-Item -ItemType Directory -Force $d; ' +
        '[IO.File]::WriteAllText((Join-Path $d ''History''), (''TMV-LEGACY-HISTORY '' + $f)) }'
    $residueRun = Invoke-UserScript -Script $residue
    $checks.Add((New-Check 'Earlier-version engine history seeded' 'stage.legacy-history' ($residueRun.exitCode -eq 0) "Viewer and Export EBWebView\Default\History hold TMV-LEGACY-HISTORY (exit $($residueRun.exitCode))."))
    Add-Phase -Name 'staging' -Checks $checks
    if (-not $ready) { throw 'The request logger did not start.' }

    # --- share controls --------------------------------------------------------------------------
    # Without these the share checks below could pass vacuously: the audit must see an SMB read, and an
    # unprotected Chromium must be shown to fetch an image from the share at all.
    $checks = New-Object System.Collections.Generic.List[object]

    $since = Get-Date
    $control = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'cmd.exe'; arguments = @('/c', 'type', '\\127.0.0.1\tmvprobe\control.txt'); timeoutSeconds = 60 }
    $oracle = Wait-ShareAccess -Since $since -Name 'control.txt' -TimeoutSeconds 30
    $checks.Add((New-Check 'The share audit sees an SMB read' 'control.share-audit' ($control.exitCode -eq 0 -and $oracle) "type over SMB exited $($control.exitCode); audited names: $(Join-Names (Get-ShareAccess -Since $since))."))

    $edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
    $edgePage = Join-Path $DocRoot 'edge-control.html'
    Set-Content -LiteralPath $edgePage -Encoding ASCII -Value '<!doctype html><html><body><img src="file://127.0.0.1/tmvprobe/edge-control.png"></body></html>'
    $since = Get-Date
    $edgeRun = $null
    if (Test-Path -LiteralPath $edge) {
        $edgeRun = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = $edge; arguments = @('--headless=new', '--disable-gpu', '--no-first-run', "--user-data-dir=$(Join-Path $DocRoot 'edge-profile')", '--virtual-time-budget=5000', '--dump-dom', ([Uri] $edgePage).AbsoluteUri); timeoutSeconds = 120 }
    }
    $vector = Wait-ShareAccess -Since $since -Name 'edge-control.png' -TimeoutSeconds 30
    $checks.Add((New-Check 'Unprotected Chromium fetches a share image' 'control.chromium-unc' $vector "Headless Edge on a local page naming file://127.0.0.1/tmvprobe/edge-control.png: present $(Test-Path -LiteralPath $edge), audited names: $(Join-Names (Get-ShareAccess -Since $since))."))
    Add-Phase -Name 'share-controls' -Checks $checks

    # Independent layer checks in real WebView2. The probe deliberately omits CSP/the sanitizer for
    # selected pages, so the other layers cannot conceal a failed assertion.
    $checks = New-Object System.Collections.Generic.List[object]
    $mapped = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'net.exe'; arguments = @('use', 'Z:', '\\127.0.0.1\tmvmapped', '/persistent:no'); timeoutSeconds = 60 }
    $mappedControl = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'cmd.exe'; arguments = @('/c', 'type', 'Z:\control.txt'); timeoutSeconds = 60 }
    $checks.Add((New-Check 'Mapped drive control' 'probe.mapped-control' ($mapped.exitCode -eq 0 -and $mappedControl.exitCode -eq 0) "Mapping exit $($mapped.exitCode), read exit $($mappedControl.exitCode)."))
    $linkControl = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'cmd.exe'; arguments = @('/c', 'type', (Join-Path $DocRoot 'remote-link\control.txt')); timeoutSeconds = 60 }
    $checks.Add((New-Check 'Network symbolic-link control' 'probe.link-control' ($linkControl.exitCode -eq 0) "Read through the local link exited $($linkControl.exitCode)."))
    $alias = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'subst.exe'; arguments = @('Y:', (Join-Path $DocRoot 'mapped-link')); timeoutSeconds = 60 }
    $aliasControl = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'cmd.exe'; arguments = @('/c', 'type', 'Y:\control.txt'); timeoutSeconds = 60 }
    $checks.Add((New-Check 'Drive alias fixture' 'probe.alias-control' ($alias.exitCode -eq 0 -and $aliasControl.exitCode -eq 0) "Alias through the network symbolic link: exit $($alias.exitCode); read through it exit $($aliasControl.exitCode)."))
    $localAlias = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'subst.exe'; arguments = @('X:', $DocRoot); timeoutSeconds = 60 }
    $checks.Add((New-Check 'Local drive alias fixture' 'probe.local-alias-control' ($localAlias.exitCode -eq 0) "Local alias: exit $($localAlias.exitCode)."))
    # Environment control: a process that calls neither browser nor policy, then a quiet pause. The
    # shell reacts to the drive letters it was just shown by opening their root, which lands on the
    # mapped share; nothing may reach the strict share, to which no drive letter leads.
    $since = Get-Date
    $startupControl = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = (Join-Path $AppRoot 'ActiveContentProbe.exe'); arguments = @($DocRoot, '--noop'); workingDirectory = $DocRoot; timeoutSeconds = 60 }
    Start-Sleep -Seconds 8
    $strictAccess = @(Get-ShareAccess -Since $since)
    $checks.Add((New-Check 'Environment control after drive mapping' 'control.environment' ($startupControl.exitCode -eq 0 -and $strictAccess.Count -eq 0) "No browser or policy called; the strict share must stay untouched. Accesses after share setup: $(Format-ShareAccess -Since $since)."))
    foreach ($mode in @('--storage', '--request')) {
        foreach ($target in @('file:///X:/local.png', 'file://127.0.0.1/tmvprobe/boundary.png', 'file:///Z:/mapped.png', 'file:///Y:/boundary.png', ([Uri] (Join-Path $DocRoot 'remote-link\boundary.png')).AbsoluteUri, ([Uri] (Join-Path $DocRoot 'local-link\local.png')).AbsoluteUri)) {
            $since = Get-Date
            $isolated = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = (Join-Path $AppRoot 'ActiveContentProbe.exe'); arguments = @($DocRoot, $mode, $target); workingDirectory = $DocRoot; timeoutSeconds = 60 }
            Start-Sleep -Milliseconds 500
            $touched = @(Get-DocumentShareAccess -Since $since)
            $checks.Add((New-Check 'Isolated storage boundary' 'probe.storage-isolation' ($isolated.exitCode -eq 0 -and $touched.Count -eq 0) "$mode $target; exit $($isolated.exitCode); share access: $(Format-ShareAccess -Since $since); output: $(@($isolated.stdout) -join ' ')."))
        }
    }
    $since = Get-Date
    $aliasRun = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = (Join-Path $AppRoot 'ActiveContentProbe.exe'); arguments = @($DocRoot, '--rendered-request', 'file:///Y:/boundary.png'); workingDirectory = $DocRoot; timeoutSeconds = 60 }
    $touched = @(Get-DocumentShareAccess -Since $since)
    $checks.Add((New-Check 'Rendered alias never reaches SMB' 'probe.alias-no-smb' ($aliasRun.exitCode -eq 0 -and $touched.Count -eq 0) "Exit $($aliasRun.exitCode); share access: $(Format-ShareAccess -Since $since)."))
    $since = Get-Date
    $mark = @(Get-Requests).Count
    $probeRun = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = (Join-Path $AppRoot 'ActiveContentProbe.exe'); arguments = @($DocRoot); workingDirectory = $DocRoot; timeoutSeconds = 180 }
    $probeResult = Join-Path $DocRoot 'probe-result.json'
    $checks.Add((New-Check 'WebView2 probe completed' 'probe.completed' ($probeRun.exitCode -eq 0 -and (Test-Path -LiteralPath $probeResult)) "Exit $($probeRun.exitCode); $(@($probeRun.stderr) -join ' ')."))
    if (Test-Path -LiteralPath $probeResult) {
        $probeChecks = Get-Content -LiteralPath $probeResult -Raw | ConvertFrom-Json
        foreach ($check in $probeChecks) { $checks.Add($check) }
        Copy-Item -LiteralPath $probeResult -Destination $Artifacts
    }
    $exfil = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -like '/exfil/*' })
    $checks.Add((New-Check 'Independent layers stop external requests' 'probe.no-exfil' ($exfil.Count -eq 0) (Format-Paths $exfil)))
    $auth = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -eq '/auth-response' })
    $challenged = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -eq '/auth/ntlm' }).Count -gt 0
    $checks.Add((New-Check 'Image challenges do not receive ambient credentials' 'probe.no-http-auth' ($challenged -and $auth.Count -eq 0) "Challenge reached: $challenged; Authorization requests: $($auth.Count)."))
    $touched = @(Get-DocumentShareAccess -Since $since)
    $checks.Add((New-Check 'Mapped and redirected resources never reach SMB' 'probe.no-smb' ($touched.Count -eq 0) (Format-ShareAccess -Since $since)))
    Add-Phase -Name 'independent-layers' -Checks $checks

    $checks = New-Object System.Collections.Generic.List[object]
    $since = Get-Date
    $lifecycleRun = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = (Join-Path $AppRoot 'LifecycleProbe.exe'); arguments = @($DocRoot); workingDirectory = $DocRoot; timeoutSeconds = 180 }
    $lifecycleResult = Join-Path $DocRoot 'lifecycle-result.json'
    $checks.Add((New-Check 'Lifecycle probe completed' 'lifecycle.completed' ($lifecycleRun.exitCode -eq 0 -and (Test-Path -LiteralPath $lifecycleResult)) "Exit $($lifecycleRun.exitCode); $(@($lifecycleRun.stderr) -join ' ')."))
    if (Test-Path -LiteralPath $lifecycleResult) {
        $lifecycleChecks = Get-Content -LiteralPath $lifecycleResult -Raw | ConvertFrom-Json
        foreach ($check in $lifecycleChecks) { $checks.Add($check) }
        Copy-Item -LiteralPath $lifecycleResult -Destination $Artifacts
    }
    $touched = @(Get-DocumentShareAccess -Since $since)
    $checks.Add((New-Check 'Adapter lifecycle never leaks SMB requests' 'lifecycle.no-smb' ($touched.Count -eq 0) (Format-ShareAccess -Since $since)))
    Add-Phase -Name 'adapter-lifecycle' -Checks $checks

    # --- viewer ----------------------------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $mark = @(Get-Requests).Count
    $hostile = Join-Path $DocRoot 'hostile.md'

    $app = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @($hostile); workingDirectory = $DocRoot }
    $window = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^hostile\.md'; timeoutSeconds = 120 }

    $imagesArrived = Wait-PassiveImages -Mark $mark -TimeoutSeconds 90
    $checks.Add((New-Check 'Remote images load in the viewer' 'viewer.remote-images' $imagesArrived "Requests since the viewer opened: $(Format-Paths (Get-RequestsSince -Mark $mark))."))

    # Long enough for every timer-driven vector to have fired: a 1 s meta refresh, autofocus, toggle.
    Start-Sleep -Seconds 8
    $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name 'viewer-hostile.png' -Destination $Artifacts -Hwnd ([int64] $window.hwnd)

    $local = $null
    try {
        $local = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-wait -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; name = '^Local image$'; index = 0 }; timeoutSeconds = 60 }
    }
    catch { $local = $null }
    $localBounds = $null
    if ($null -ne $local -and $null -ne $local.element) { $localBounds = $local.element.bounds }
    $localRendered = $null -ne $localBounds -and $localBounds.height -ge 40 -and [math]::Abs($localBounds.width - $localBounds.height) -le 4
    $localDescription = 'no element named "Local image"'
    if ($null -ne $localBounds) { $localDescription = "$($localBounds.width)x$($localBounds.height)" }
    $checks.Add((New-Check 'A relative local image renders at its own size' 'viewer.local-image' $localRendered "The unsized local image is laid out at $localDescription; a loaded 48x48 picture is square and at least 48 px at 100% scale, a broken one is not."))

    $windows = @(Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command list-windows -Parameters @{ processId = $app.processId })
    $extra = @($windows | Where-Object { $_.title -and $_.title -notmatch '^hostile\.md' })
    $checks.Add((New-Check 'Document script cannot message the host' 'viewer.no-host-message' ($extra.Count -eq 0) "Windows of the viewer process: $(@($windows | ForEach-Object { $_.title }) -join ' | '). hostile.md posts 'tigermarkview:help' from its own script, which would have opened Help."))

    # A real click on what used to be a javascript: link, which also puts keyboard focus in the page.
    # The interaction targets sit at the top of the document so they are on screen without scrolling.
    $click = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; name = '^Run javascript link$'; index = 0 }; action = 'click'; settleMilliseconds = 2000 }
    $afterClick = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command list-windows -Parameters @{ processId = $app.processId }
    $stillOnDocument = @($afterClick | Where-Object { $_.title -match '^hostile\.md' }).Count -eq 1
    $checks.Add((New-Check 'A javascript: link does nothing when clicked' 'viewer.javascript-link' ([bool] $click.targetHit -and $stillOnDocument) "Click reached the link: $($click.targetHit) at ($($click.requested.x), $($click.requested.y)); the viewer still shows hostile.md: $stillOnDocument."))

    # An in-document link scrolls in place only through the shell's anchor script: without it the
    # <base href> turns the fragment into a navigation to the folder, which the viewer refuses.
    $endSelector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; name = '^End of document$'; index = 0 }
    $endBefore = (Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-find -Parameters @{ selector = $endSelector }).element
    $jump = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; name = '^Jump to the end$'; index = 0 }; action = 'click'; settleMilliseconds = 1500 }
    $endAfter = (Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-find -Parameters @{ selector = $endSelector }).element
    $scrolled = $null -ne $endBefore -and $null -ne $endAfter -and [bool] $endBefore.offscreen -and -not [bool] $endAfter.offscreen
    $afterJump = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command list-windows -Parameters @{ processId = $app.processId }
    $stillOnDocument = @($afterJump | Where-Object { $_.title -match '^hostile\.md' }).Count -eq 1
    $endDescription = 'the heading was not found'
    if ($null -ne $endBefore -and $null -ne $endAfter) { $endDescription = "offscreen before: $($endBefore.offscreen), after: $($endAfter.offscreen)" }
    $checks.Add((New-Check 'The shell anchor script runs under the policy' 'viewer.anchor-script' ([bool] $jump.targetHit -and $scrolled -and $stillOnDocument) "Click reached the link: $($jump.targetHit); 'End of document' $endDescription; still on hostile.md: $stillOnDocument."))

    # F1 inside the page reaches the host only through the shell's own hashed script.
    $key = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command keyboard -Parameters @{ action = 'keys'; keys = @('F1'); settleMilliseconds = 500 }
    $focusInPage = $null -ne $key.focusedBeforeInput -and [int] $key.focusedBeforeInput.processId -ne [int] $app.processId
    $help = $null
    try { $help = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^Help'; timeoutSeconds = 30 } } catch { $help = $null }
    $focusDescription = 'nothing'
    if ($null -ne $key.focusedBeforeInput) { $focusDescription = "'$($key.focusedBeforeInput.name)' ($($key.focusedBeforeInput.controlType)) in process $($key.focusedBeforeInput.processId)" }
    $foreground = 'unknown'
    if ($null -ne $key.foregroundWindow) { $foreground = "'$($key.foregroundWindow.title)' (process $($key.foregroundWindow.processId))" }
    $checks.Add((New-Check 'The shell key script runs under the policy' 'viewer.shell-script' ($focusInPage -and $null -ne $help) "F1 was pressed with focus on $focusDescription, foreground $foreground (the viewer is process $($app.processId)); Help opened: $($null -ne $help)."))
    if ($null -ne $help) {
        $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name 'viewer-help.png' -Destination $Artifacts -Hwnd ([int64] $help.hwnd)
    }

    Start-Sleep -Seconds 2
    $viewerRequests = Get-RequestsSince -Mark $mark
    $viewerExfil = @($viewerRequests | Where-Object { $_.path -like '/exfil/*' -or $_.path -eq '/auth-response' })
    $checks.Add((New-Check 'No data-bearing request leaves the viewer' 'viewer.no-exfil' ($viewerExfil.Count -eq 0) "Exfiltration requests: $(Format-Paths $viewerExfil)."))

    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command stop-process -Parameters @{ processId = $app.processId }
    Add-Phase -Name 'viewer' -Checks $checks

    # --- viewer: network shares ------------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $mark = @(Get-Requests).Count
    $since = Get-Date
    $shares = Join-Path $DocRoot 'shares.md'

    $app = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @($shares); workingDirectory = $DocRoot }
    $window = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^shares\.md'; timeoutSeconds = 120 }
    $web = Wait-Request -Mark $mark -Path '/img/shares-web.png' -TimeoutSeconds 90
    Start-Sleep -Seconds 5
    $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name 'viewer-shares.png' -Destination $Artifacts -Hwnd ([int64] $window.hwnd)
    $checks.Add((New-Check 'A web image still loads beside share references' 'viewer.shares-web-image' $web "Requests: $(Format-Paths (Get-RequestsSince -Mark $mark))."))

    foreach ($name in @('Relative local image', 'Absolute local image', 'Absolute HTML local image')) {
        $size = Get-ImageSize -Hwnd ([int64] $window.hwnd) -Name $name
        $checks.Add((New-Check "$name still renders" ('viewer.' + ($name.ToLowerInvariant() -replace ' ', '-')) $size.rendered "'$name' is laid out at $($size.description)."))
    }

    $touched = @(Get-DocumentShareAccess -Since $since)
    $checks.Add((New-Check 'No share image is requested by the viewer' 'viewer.no-share-access' ($touched.Count -eq 0) "Share accesses: $(Format-ShareAccess -Since $since). The document names $($ShareImages.Count) images on the shares in every spelling it has."))
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command stop-process -Parameters @{ processId = $app.processId }

    # A document that itself lives on the share: its relative image only becomes a network path once
    # resolved against the document's base, so only the request boundary can refuse it.
    $mark = @(Get-Requests).Count
    $since = Get-Date
    $app = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @('\\127.0.0.1\tmvprobe\on-share.md'); workingDirectory = $DocRoot }
    $window = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^on-share\.md'; timeoutSeconds = 120 }
    $web = Wait-Request -Mark $mark -Path '/img/on-share-web.png' -TimeoutSeconds 90
    Start-Sleep -Seconds 5
    $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name 'viewer-on-share.png' -Destination $Artifacts -Hwnd ([int64] $window.hwnd)
    $touched = @(Get-ShareAccess -Since $since)
    $checks.Add((New-Check 'A document on a share opens, but its share image is not fetched' 'viewer.on-share' ($web -and ($touched -contains 'on-share.md') -and ($touched -notcontains 'on-share.png')) "Rendered: $web. Share files asked for: $(Join-Names $touched) — the document itself, read by the reader's own choice, and not its relative image."))
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command stop-process -Parameters @{ processId = $app.processId }
    Add-Phase -Name 'viewer-shares' -Checks $checks

    # --- viewer: code, highlighted, and GUI export --------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $mark = @(Get-Requests).Count
    $code = Join-Path $DocRoot 'code.md'
    $guiPdf = Join-Path $DocRoot 'code-gui.pdf'

    $app = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @($code); workingDirectory = $DocRoot }
    $window = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^code\.md'; timeoutSeconds = 120 }
    $null = Find-Text -Hwnd ([int64] $window.hwnd) -Pattern '^Code acceptance$'
    Start-Sleep -Seconds 5
    $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name 'viewer-code.png' -Destination $Artifacts -Hwnd ([int64] $window.hwnd)
    $keywordPixels = Get-ColourPixelCount -PngPath (Join-Path $Artifacts 'viewer-code.png') -R $ScreenKeyword[0] -G $ScreenKeyword[1] -B $ScreenKeyword[2] -Tolerance 40
    $checks.Add((New-Check 'Syntax highlighting renders in the viewer' 'viewer.highlighting' ($keywordPixels -ge 20) "$keywordPixels pixel(s) of the keyword colour #cf222e in the viewer capture."))

    $literal = (Find-Text -Hwnd ([int64] $window.hwnd) -Pattern 'exfil/code-csharp-img') -and
        (Find-Text -Hwnd ([int64] $window.hwnd) -Pattern "^<script>fetch\('http://127\.0\.0\.1:$Port/exfil/code-plain'\)</script>$")
    $checks.Add((New-Check 'Hostile code is shown as literal text' 'viewer.code-literal' $literal "The C# string literal and the plain <script> line are found as page text."))

    # GUI export of the same retained, highlighted page, through the Save dialog.
    $export = Invoke-GuiExport -Window $window -ProcessId $app.processId -PdfPath $guiPdf
    $guiKeyword = Test-PdfHasColour -PdfPath $guiPdf -R $PrintKeyword[0] -G $PrintKeyword[1] -B $PrintKeyword[2]
    $guiComment = Test-PdfHasColour -PdfPath $guiPdf -R $PrintComment[0] -G $PrintComment[1] -B $PrintComment[2]
    $checks.Add((New-Check 'Syntax highlighting reaches the exported PDF' 'pdf.gui-highlighting' ($export.exported -and $guiKeyword -and $guiComment) "Save dialog found: $($export.dialog); code-gui.pdf written: $($export.exported); print keyword colour: $guiKeyword; print comment colour: $guiComment."))

    Start-Sleep -Seconds 2
    $codeExfil = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -like '/exfil/*' })
    $checks.Add((New-Check 'Hostile code stays inert in the viewer and GUI export' 'viewer.code-no-exfil' ($codeExfil.Count -eq 0) "Exfiltration requests: $(Format-Paths $codeExfil)."))
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command stop-process -Parameters @{ processId = $app.processId }
    Add-Phase -Name 'viewer-code' -Checks $checks

    # --- PDF conversion --------------------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $mark = @(Get-Requests).Count
    $pdf = Join-Path $DocRoot 'hostile.pdf'

    $run = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = $cliExe; arguments = @($hostile, '-o', $pdf); workingDirectory = $DocRoot; timeoutSeconds = 180 }
    $created = @($run.stdout | Where-Object { $_ -like 'Created: *' }).Count -eq 1
    $checks.Add((New-Check 'tiger-mark converts the hostile document' 'pdf.convert' ($run.exitCode -eq 0 -and $created -and (Test-Path $pdf)) "Exit code $($run.exitCode); stdout: $(@($run.stdout) -join ' '); stderr: $(@($run.stderr) -join ' ')."))

    Start-Sleep -Seconds 3
    $pdfRequests = Get-RequestsSince -Mark $mark
    $pdfPaths = @($pdfRequests | ForEach-Object { $_.path })
    $pdfImages = @($PassiveImages | Where-Object { $pdfPaths -contains $_ }).Count -eq $PassiveImages.Count
    $checks.Add((New-Check 'Remote images load in PDF conversion' 'pdf.remote-images' $pdfImages "Requests during conversion: $(Format-Paths $pdfRequests)."))

    $pdfExfil = @($pdfRequests | Where-Object { $_.path -like '/exfil/*' -or $_.path -eq '/auth-response' })
    $checks.Add((New-Check 'No data-bearing request leaves PDF conversion' 'pdf.no-exfil' ($pdfExfil.Count -eq 0) "Exfiltration requests: $(Format-Paths $pdfExfil)."))

    $hostileImages = Get-ImageObjectCount -PdfPath $pdf
    $checks.Add((New-Check 'The PDF embeds the passive images' 'pdf.images' ($hostileImages -ge 3) "hostile.pdf holds $hostileImages image object(s): two remote pictures and the local one at least."))

    $localPdf = Join-Path $DocRoot 'local-only.pdf'
    $noImagePdf = Join-Path $DocRoot 'no-image.pdf'
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = $cliExe; arguments = @((Join-Path $DocRoot 'local-only.md'), '-o', $localPdf); workingDirectory = $DocRoot; timeoutSeconds = 180 }
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = $cliExe; arguments = @((Join-Path $DocRoot 'no-image.md'), '-o', $noImagePdf); workingDirectory = $DocRoot; timeoutSeconds = 180 }
    $localImages = Get-ImageObjectCount -PdfPath $localPdf
    $controlImages = Get-ImageObjectCount -PdfPath $noImagePdf
    $checks.Add((New-Check 'A relative local image is embedded in the PDF' 'pdf.local-image' ($localImages -ge 1 -and $controlImages -eq 0) "local-only.pdf holds $localImages image object(s); the image-free control holds $controlImages."))

    # Parity: one document, one policy, so both paths asked the network for exactly the same things.
    $viewerSet = Format-Paths $viewerRequests
    $pdfSet = Format-Paths $pdfRequests
    $checks.Add((New-Check 'Viewer and PDF make the same requests' 'parity.requests' ($viewerSet -eq $pdfSet) "Viewer: $viewerSet. PDF: $pdfSet."))

    foreach ($file in @($pdf, $localPdf, $noImagePdf)) {
        if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination $Artifacts }
    }
    Add-Phase -Name 'pdf' -Checks $checks

    # --- PDF conversion: network shares and code -------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $mark = @(Get-Requests).Count
    $since = Get-Date
    $sharesPdf = Join-Path $DocRoot 'shares.pdf'
    $run = Invoke-Cli -Arguments @((Join-Path $DocRoot 'shares.md'), '-o', $sharesPdf)
    $web = Wait-Request -Mark $mark -Path '/img/shares-web.png' -TimeoutSeconds 10
    $sharesImages = Get-ImageObjectCount -PdfPath $sharesPdf
    $checks.Add((New-Check 'tiger-mark still embeds local and web images beside share references' 'pdf.shares-images' ((Test-CliCreated -Run $run -Pdf $sharesPdf) -and $web -and $sharesImages -ge 2) "Exit $($run.exitCode); web image requested: $web; shares.pdf holds $sharesImages image object(s)."))
    $touched = @(Get-DocumentShareAccess -Since $since)
    $checks.Add((New-Check 'No share image is requested by PDF conversion' 'pdf.no-share-access' ($touched.Count -eq 0) "Share accesses: $(Format-ShareAccess -Since $since)."))

    $since = Get-Date
    $onSharePdf = Join-Path $DocRoot 'on-share.pdf'
    $run = Invoke-Cli -Arguments @('\\127.0.0.1\tmvprobe\on-share.md', '-o', $onSharePdf)
    Start-Sleep -Seconds 3
    $touched = @(Get-ShareAccess -Since $since)
    $checks.Add((New-Check 'A document on a share converts, but its share image is not fetched' 'pdf.on-share' ((Test-CliCreated -Run $run -Pdf $onSharePdf) -and ($touched -contains 'on-share.md') -and ($touched -notcontains 'on-share.png')) "Exit $($run.exitCode); share files asked for: $(Join-Names $touched)."))

    # tiger-mark renders with highlighting off, so its PDF of code.md is the control for the colour check.
    $mark = @(Get-Requests).Count
    $cliPdf = Join-Path $DocRoot 'code-cli.pdf'
    $run = Invoke-Cli -Arguments @((Join-Path $DocRoot 'code.md'), '-o', $cliPdf)
    $cliKeyword = Test-PdfHasColour -PdfPath $cliPdf -R $PrintKeyword[0] -G $PrintKeyword[1] -B $PrintKeyword[2]
    $checks.Add((New-Check 'The colour check tells highlighted from plain' 'pdf.highlighting-control' ((Test-CliCreated -Run $run -Pdf $cliPdf) -and -not $cliKeyword) "code-cli.pdf (highlighting off) carries the print keyword colour: $cliKeyword."))
    Start-Sleep -Seconds 2
    $codeExfil = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -like '/exfil/*' })
    $checks.Add((New-Check 'Hostile code stays inert in tiger-mark' 'pdf.code-no-exfil' ($codeExfil.Count -eq 0) "Exfiltration requests: $(Format-Paths $codeExfil)."))

    foreach ($file in @($sharesPdf, $onSharePdf, $cliPdf, (Join-Path $DocRoot 'code-gui.pdf'))) {
        if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination $Artifacts }
    }
    Add-Phase -Name 'pdf-shares-code' -Checks $checks

    # --- viewer: links to network shares ---------------------------------------------------------
    # A followed link must not open a share (which signs in to its host); a share the reader names
    # still opens. The strict share is the oracle: no drive letter leads to it.
    $checks = New-Object System.Collections.Generic.List[object]
    try {
    $app = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @((Join-Path $DocRoot 'links.md')); workingDirectory = $DocRoot }
    $window = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^links\.md'; timeoutSeconds = 120 }
    # The title is set before the page has rendered; wait for its last link to be on screen.
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-wait -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; name = '^Local link$'; index = 0 }; timeoutSeconds = 60 }
    $since = Get-Date
    foreach ($name in @('Share link', 'Slash share link', 'Mapped drive link')) {
        $click = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; name = "^$([regex]::Escape($name))$"; index = 0 }; action = 'click'; settleMilliseconds = 700 }
        # The refusal note is transient (6 s): read the status line itself, by its automation id, at once,
        # rather than searching the whole tree, which the page's own UIA tree makes slower than the note.
        $statusText = ''
        try { $statusText = [string] (Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-find -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; automationId = 'StatusText'; index = 0 } }).element.name } catch { $statusText = '' }
        $explained = $statusText -match 'leads to a network location'
        $titles = @(Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command list-windows -Parameters @{ processId = $app.processId } | ForEach-Object { $_.title })
        $stayed = @($titles | Where-Object { $_ -match '^links\.md' }).Count -eq 1
        $checks.Add((New-Check "A $($name.ToLowerInvariant()) is not followed" ('links.' + ($name.ToLowerInvariant() -replace ' ', '-')) ([bool] $click.targetHit -and $stayed -and $explained) "Click reached the link: $($click.targetHit); windows: $($titles -join ' | '); status: '$statusText'."))
    }
    $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name 'viewer-share-links.png' -Destination $Artifacts -Hwnd ([int64] $window.hwnd)
    Start-Sleep -Seconds 3
    $touched = @(Get-DocumentShareAccess -Since $since)
    $checks.Add((New-Check 'No linked share document is opened' 'links.no-share-access' ($touched.Count -eq 0) "Share accesses since the clicks: $(Format-ShareAccess -Since $since)."))
    $local = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; name = '^Local link$'; index = 0 }; action = 'click'; settleMilliseconds = 1500 }
    $followed = $null
    try { $followed = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^local-target\.md'; timeoutSeconds = 30 } } catch { $followed = $null }
    $checks.Add((New-Check 'A local link is still followed' 'links.local-control' ([bool] $local.targetHit -and $null -ne $followed) "Click reached the link: $($local.targetHit); local-target.md shown: $($null -ne $followed)."))
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command stop-process -Parameters @{ processId = $app.processId }

    # A relative link inside a document opened from the share leads to the share too.
    $app = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @('\\127.0.0.1\tmvprobe\on-share.md'); workingDirectory = $DocRoot }
    $window = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^on-share\.md'; timeoutSeconds = 120 }
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-wait -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; name = '^Next on share$'; index = 0 }; timeoutSeconds = 60 }
    Start-Sleep -Seconds 3
    $since = Get-Date
    $click = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; name = '^Next on share$'; index = 0 }; action = 'click'; settleMilliseconds = 2500 }
    Start-Sleep -Seconds 3
    $touched = @(Get-ShareAccess -Since $since)
    $titles = @(Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command list-windows -Parameters @{ processId = $app.processId } | ForEach-Object { $_.title })
    $checks.Add((New-Check 'A relative link in a document on a share is not followed' 'links.relative-on-share' ([bool] $click.targetHit -and ($touched -notcontains 'next-on-share.md') -and @($titles | Where-Object { $_ -match '^on-share\.md' }).Count -eq 1) "Click reached the link: $($click.targetHit); share files asked for since: $(Join-Names $touched); windows: $($titles -join ' | ')."))
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command stop-process -Parameters @{ processId = $app.processId }

    # The reader may still name a share document themselves: the command line is an explicit open.
    $since = Get-Date
    $app = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @('\\127.0.0.1\tmvprobe\linked.md'); workingDirectory = $DocRoot }
    $opened = $null
    try { $opened = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^linked\.md'; timeoutSeconds = 120 } } catch { $opened = $null }
    $read = Wait-ShareAccess -Since $since -Name 'linked.md' -TimeoutSeconds 30
    $checks.Add((New-Check 'A share document the reader opens still opens' 'links.explicit-share-open' ($null -ne $opened -and $read) "linked.md shown: $($null -ne $opened); read from the share: $read."))
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command stop-process -Parameters @{ processId = $app.processId }
    }
    catch { $checks.Add((New-Check 'Phase completed' 'viewer-share-links.error' $false $_.Exception.Message)) }
    Add-Phase -Name 'viewer-share-links' -Checks $checks

    # --- remote images turned off ----------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    try {
    Set-UserSettings -Values @{ loadRemoteImages = $false }
    $mark = @(Get-Requests).Count
    $app = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @($hostile); workingDirectory = $DocRoot }
    $window = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^hostile\.md'; timeoutSeconds = 120 }
    Start-Sleep -Seconds 15
    $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name 'viewer-remote-off.png' -Destination $Artifacts -Hwnd ([int64] $window.hwnd)
    $web = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -like '/img/*' })
    $localSize = Get-ImageSize -Hwnd ([int64] $window.hwnd) -Name 'Local image'
    $checks.Add((New-Check 'With remote images off the viewer requests no web image' 'remote-off.viewer' ($web.Count -eq 0) "Web image requests: $(Format-Paths $web)."))
    $checks.Add((New-Check 'Local images still render with remote images off' 'remote-off.local-image' $localSize.rendered "'Local image' is laid out at $($localSize.description)."))

    $offPdf = Join-Path $DocRoot 'hostile-remote-off.pdf'
    $export = Invoke-GuiExport -Window $window -ProcessId $app.processId -PdfPath $offPdf
    Start-Sleep -Seconds 2
    $web = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -like '/img/*' })
    $offImages = Get-ImageObjectCount -PdfPath $offPdf
    $checks.Add((New-Check 'GUI export follows the setting' 'remote-off.gui-export' ($export.exported -and $web.Count -eq 0 -and $offImages -ge 1 -and $offImages -lt $hostileImages) "Save dialog: $($export.dialog); written: $($export.exported); web image requests: $(Format-Paths $web); image objects: $offImages (remote images on, tiger-mark: $hostileImages)."))
    if (Test-Path -LiteralPath $offPdf) { Copy-Item -LiteralPath $offPdf -Destination $Artifacts }

    # Back on through View > Rendering > Load Remote Images: the page re-renders and fetches them.
    $mark = @(Get-Requests).Count
    $menuFailure = ''
    try { Invoke-MenuPath -Window $window -ProcessId $app.processId -Path @(@{ automationId = 'ViewMenu' }, @{ automationId = 'RenderingMenu' }, @{ automationId = 'LoadRemoteImagesItem' }) }
    catch { $menuFailure = $_.Exception.Message }
    $refetched = Wait-PassiveImages -Mark $mark -TimeoutSeconds 60
    $saved = Get-UserSettings
    $savedOn = $null -ne $saved -and $null -ne $saved.PSObject.Properties['loadRemoteImages'] -and [bool] $saved.loadRemoteImages
    $checks.Add((New-Check 'Turning remote images back on from the menu loads them and is saved' 'remote-off.menu-on' ($refetched -and $savedOn) "Menu: $(if ($menuFailure) { $menuFailure } else { 'clicked' }); passive images requested again: $refetched; saved loadRemoteImages: $savedOn."))
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command stop-process -Parameters @{ processId = $app.processId }
    }
    catch { $checks.Add((New-Check 'Phase completed' 'remote-images-off.error' $false $_.Exception.Message)) }
    Add-Phase -Name 'remote-images-off' -Checks $checks

    # --- an authenticating proxy is never signed in to ------------------------------------------
    # The interactive user's own proxy setting points at the logger, which answers every proxied
    # request with an NTLM challenge and records whether a Proxy-Authorization header ever arrives.
    $checks = New-Object System.Collections.Generic.List[object]
    try {
    $internet = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $proxyOn = Invoke-UserScript -Script ("Set-ItemProperty '$internet' -Name ProxyEnable -Value 1 -Type DWord; Set-ItemProperty '$internet' -Name ProxyServer -Value '127.0.0.1:$Port'")
    $mark = @(Get-Requests).Count
    $control = Invoke-UserScript -Script ("try { Invoke-WebRequest -Uri 'http://tmv-proxy.invalid/img/control.png' -Proxy 'http://127.0.0.1:$Port' -ProxyUseDefaultCredentials -UseBasicParsing -TimeoutSec 20 | Out-Null } catch { }")
    Start-Sleep -Seconds 2
    $offered = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -eq '/proxy-auth-response' }).Count
    $checks.Add((New-Check 'A client that opts in offers the proxy Windows credentials' 'proxy.control' ($proxyOn.exitCode -eq 0 -and $offered -gt 0) "Proxy set: exit $($proxyOn.exitCode); Invoke-WebRequest -ProxyUseDefaultCredentials offered credentials $offered time(s) (exit $($control.exitCode))."))

    $mark = @(Get-Requests).Count
    $app = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @((Join-Path $DocRoot 'proxy.md')); workingDirectory = $DocRoot }
    $window = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^proxy\.md'; timeoutSeconds = 120 }
    $proxied = Wait-Request -Mark $mark -Path 'http://tmv-proxy.invalid/img/proxied.png' -TimeoutSeconds 60
    Start-Sleep -Seconds 5
    $offered = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -eq '/proxy-auth-response' }).Count
    $localSize = Get-ImageSize -Hwnd ([int64] $window.hwnd) -Name 'Local image'
    $checks.Add((New-Check 'The viewer never signs in to the proxy' 'proxy.viewer' ($proxied -and $offered -eq 0 -and $localSize.rendered) "Image asked of the proxy: $proxied; credentials offered: $offered; local image $($localSize.description)."))
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command stop-process -Parameters @{ processId = $app.processId }

    $mark = @(Get-Requests).Count
    $proxyPdf = Join-Path $DocRoot 'proxy.pdf'
    $run = Invoke-Cli -Arguments @((Join-Path $DocRoot 'proxy.md'), '-o', $proxyPdf)
    $proxied = Wait-Request -Mark $mark -Path 'http://tmv-proxy.invalid/img/proxied.png' -TimeoutSeconds 10
    $offered = @(Get-RequestsSince -Mark $mark | Where-Object { $_.path -eq '/proxy-auth-response' }).Count
    $checks.Add((New-Check 'tiger-mark never signs in to the proxy' 'proxy.cli' ((Test-CliCreated -Run $run -Pdf $proxyPdf) -and $proxied -and $offered -eq 0) "Exit $($run.exitCode); image asked of the proxy: $proxied; credentials offered: $offered."))
    $proxyOff = Invoke-UserScript -Script ("Set-ItemProperty '$internet' -Name ProxyEnable -Value 0 -Type DWord; Remove-ItemProperty '$internet' -Name ProxyServer -ErrorAction SilentlyContinue")
    $checks.Add((New-Check 'Proxy setting restored' 'proxy.restored' ($proxyOff.exitCode -eq 0) "exit $($proxyOff.exitCode)"))
    }
    catch { $checks.Add((New-Check 'Phase completed' 'proxy-credentials.error' $false $_.Exception.Message)) }
    Add-Phase -Name 'proxy-credentials' -Checks $checks

    # --- several windows, one settings file -----------------------------------------------------
    # Two viewer processes with their own copies of the settings. Each changes something through its
    # own UI; nothing either remembers from its start may overwrite what the other saved.
    $checks = New-Object System.Collections.Generic.List[object]
    try {
    $seed1 = Join-Path $DocRoot 'seed-1.md'
    $seed2 = Join-Path $DocRoot 'seed-2.md'
    $docA = Join-Path $DocRoot 'mw-a.md'
    $docB = Join-Path $DocRoot 'mw-b.md'
    Set-UserSettings -Replace -Values @{ theme = 'Light'; editorType = 'Notepad3'; pdfPaperSize = 'Letter'; syntaxHighlighting = $true; toolbarExportPdfVisible = $true; loadRemoteImages = $true; recentFiles = @($seed1, $seed2) }

    $appB = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @($docB); workingDirectory = $DocRoot }
    $windowB = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $appB.processId; titlePattern = '^mw-b\.md'; timeoutSeconds = 120 }
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do { $saved = Get-UserSettings; Start-Sleep -Milliseconds 500 } while ([DateTime]::UtcNow -lt $deadline -and -not ($null -ne $saved -and @($saved.recentFiles | Where-Object { Test-SameFile $_ $docB }).Count -eq 1))
    $appA = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = $viewerExe; arguments = @($docA); workingDirectory = $DocRoot }
    $windowA = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $appA.processId; titlePattern = '^mw-a\.md'; timeoutSeconds = 120 }
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do { $saved = Get-UserSettings; Start-Sleep -Milliseconds 500 } while ([DateTime]::UtcNow -lt $deadline -and -not ($null -ne $saved -and @($saved.recentFiles | Where-Object { Test-SameFile $_ $docA }).Count -eq 1))

    # Window B, started before A opened mw-a.md, reopens seed-2.md from its own Open Recent.
    $menuFailure = ''
    try { Invoke-MenuPath -Window $windowB -ProcessId $appB.processId -Path @(@{ automationId = 'FileMenu' }, @{ automationId = 'OpenRecentMenuItem' }, @{ name = '^seed-2\.md$' }) }
    catch { $menuFailure = $_.Exception.Message }
    $reopened = $null
    try { $reopened = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $appB.processId; titlePattern = '^seed-2\.md'; timeoutSeconds = 30 } } catch { $reopened = $null }
    if ($null -ne $reopened) { $windowB = $reopened }
    Start-Sleep -Seconds 2
    $saved = Get-UserSettings
    $recent = @(if ($null -ne $saved) { @($saved.recentFiles) })
    $merged = $recent.Count -ge 3 -and (Test-SameFile $recent[0] $seed2) -and @($recent | Where-Object { Test-SameFile $_ $docA }).Count -eq 1 -and @($recent | Where-Object { Test-SameFile $_ $docB }).Count -eq 1
    $checks.Add((New-Check 'Recent files opened in two windows are all kept' 'multi-window.recent-merged' $merged "Menu: $(if ($menuFailure) { $menuFailure } else { 'clicked' }); B reopened seed-2.md: $($null -ne $reopened); saved list: $($recent -join ' | ')."))

    # Window A clears Open Recent; window B, which still remembers the list, then changes its theme.
    $menuFailure = ''
    try { Invoke-MenuPath -Window $windowA -ProcessId $appA.processId -Path @(@{ automationId = 'FileMenu' }, @{ automationId = 'OpenRecentMenuItem' }, @{ automationId = 'ClearRecentFilesMenuItem' }) }
    catch { $menuFailure = $_.Exception.Message }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do { $saved = Get-UserSettings; Start-Sleep -Milliseconds 500 } while ([DateTime]::UtcNow -lt $deadline -and -not ($null -ne $saved -and @($saved.recentFiles).Count -eq 0))
    $checks.Add((New-Check 'Clear Recent Files in window A is saved at once' 'multi-window.cleared' ($null -ne $saved -and @($saved.recentFiles).Count -eq 0) "Menu: $(if ($menuFailure) { $menuFailure } else { 'clicked' }); saved entries: $(if ($saved) { @($saved.recentFiles).Count })."))
    $menuFailure = ''
    try { Invoke-MenuPath -Window $windowB -ProcessId $appB.processId -Path @(@{ automationId = 'ViewMenu' }, @{ automationId = 'ThemeMenu' }, @{ automationId = 'DarkThemeItem' }) }
    catch { $menuFailure = $_.Exception.Message }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do { $saved = Get-UserSettings; Start-Sleep -Milliseconds 500 } while ([DateTime]::UtcNow -lt $deadline -and -not ($null -ne $saved -and [string] $saved.theme -eq 'Dark'))
    $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name 'multi-window.png' -Destination $Artifacts
    $checks.Add((New-Check 'A later theme change in window B keeps the list cleared' 'multi-window.theme-after-clear' ($null -ne $saved -and [string] $saved.theme -eq 'Dark' -and @($saved.recentFiles).Count -eq 0) "Menu: $(if ($menuFailure) { $menuFailure } else { 'clicked' }); theme: $(if ($saved) { $saved.theme }); entries: $(if ($saved) { @($saved.recentFiles).Count })."))

    # Both windows close normally, B first, each writing its placement.
    $closedB = Close-Viewer -Window $windowB -ProcessId $appB.processId
    $closedA = Close-Viewer -Window $windowA -ProcessId $appA.processId
    $saved = Get-UserSettings
    $kept = $null -ne $saved -and @($saved.recentFiles).Count -eq 0 -and [string] $saved.theme -eq 'Dark' -and [string] $saved.editorType -eq 'Notepad3' -and
        [string] $saved.pdfPaperSize -eq 'Letter' -and [bool] $saved.syntaxHighlighting -and [bool] $saved.toolbarExportPdfVisible -and [bool] $saved.loadRemoteImages
    $description = 'no settings file'
    if ($null -ne $saved) { $description = "entries $(@($saved.recentFiles).Count), theme $($saved.theme), editor $($saved.editorType), paper $($saved.pdfPaperSize), highlighting $($saved.syntaxHighlighting), export button $($saved.toolbarExportPdfVisible), remote images $($saved.loadRemoteImages)" }
    $checks.Add((New-Check 'Closing both windows keeps every setting either changed and every unrelated one' 'multi-window.closed' ($closedA -and $closedB -and $kept) "Closed normally: A $closedA, B $closedB; saved: $description."))
    }
    catch { $checks.Add((New-Check 'Phase completed' 'multi-window-settings.error' $false $_.Exception.Message)) }
    Add-Phase -Name 'multi-window-settings' -Checks $checks

    # --- no browsing history on disk -------------------------------------------------------------
    # Every viewer and export in this run has ended, several by being killed. A persistent engine profile
    # would now hold the generated pages' addresses and the documents' titles; InPrivate holds nothing.
    $checks = New-Object System.Collections.Generic.List[object]
    try {
    Start-Sleep -Seconds 5
    $markers = @('TigerMarkView/preview-', 'TigerMarkView\preview-', 'TigerMarkView/pdf/export-', 'TigerMarkView\pdf\export-', 'TMV-LEGACY-HISTORY',
        'hostile.md', 'shares.md', 'code.md', 'links.md', 'local-target.md', 'proxy.md', 'mw-a.md', 'seed-2.md', 'on-share.md')
    $scan = Find-EngineMarkers -Markers $markers
    $checks.Add((New-Check 'No browsing record of any viewed or exported document' 'history.none' ($scan.files -gt 0 -and @($scan.hits).Count -eq 0 -and @($scan.unreadable).Count -eq 0) "$($scan.files) file(s) under $($scan.root), $(@($scan.unreadable).Count) unreadable $(@($scan.unreadable) -join '; '); History files: $(@($scan.history) -join '; '); hits: $(if (@($scan.hits).Count) { @($scan.hits) -join '; ' } else { '(none)' })."))
    $state = Invoke-UserScript -Script '$w = Join-Path $env:LOCALAPPDATA ''TigerMarkView\WebView2''; foreach ($f in ''Viewer'', ''Export'') { $f + ''='' + (Test-Path (Join-Path $w ($f + ''\TigerMarkView.InPrivate''))) + '','' + (Test-Path (Join-Path $w ($f + ''\EBWebView\Default\History''))) }'
    $lines = @($state.stdout | Where-Object { $_ })
    # Chromium may create an empty History of its own for the parent profile; what matters is that the
    # earlier version's file, with its marker, is gone and the removal recorded.
    $legacyHits = @(@($scan.hits) | Where-Object { $_ -like '*TMV-LEGACY-HISTORY' })
    $migrated = @($lines | Where-Object { $_ -match '=True,' }).Count -eq 2 -and $legacyHits.Count -eq 0
    $checks.Add((New-Check "An earlier version's engine history is removed" 'history.legacy-removed' $migrated "Removal marker written, a History file present, per folder: $($lines -join '; '); legacy marker found: $($legacyHits.Count)."))

    # The control: an ordinary Chromium profile does record such a visit where the scan looks.
    $controlFolder = Join-Path $DocRoot 'TigerMarkView'
    $null = New-Item -ItemType Directory -Path $controlFolder -Force
    $controlPage = Join-Path $controlFolder 'preview-control.html'
    Set-Content -LiteralPath $controlPage -Encoding ASCII -Value '<!doctype html><html><head><title>history control</title></head><body>control</body></html>'
    $controlProfile = Join-Path $DocRoot 'history-control-profile'
    # The documents folder already grants Users modify, inherited by this new folder; a recursive grant
    # here would walk into the symbolic links to the shares.
    # A WebView2 engine with an ordinary persistent profile, as earlier versions ran one (headless Edge
    # keeps no history, so it cannot serve as this control).
    $controlRun = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = (Join-Path $AppRoot 'ActiveContentProbe.exe'); arguments = @($DocRoot, '--history-control', $controlProfile, $controlPage); workingDirectory = $DocRoot; timeoutSeconds = 120 }
    # The engine's browser process outlives the host by a moment; give it time to let go of its files.
    $controlScan = $null
    for ($attempt = 0; $attempt -lt 7; $attempt++) {
        Start-Sleep -Seconds 5
        $controlScan = Find-EngineMarkers -Markers @('TigerMarkView/preview-control') -Root $controlProfile
        if (@($controlScan.hits).Count -gt 0) { break }
    }
    $checks.Add((New-Check 'The scan finds an ordinary profile''s record of a visit' 'history.control' ($controlRun.exitCode -eq 0 -and @($controlScan.hits).Count -gt 0) "Persistent-profile WebView2: exit $($controlRun.exitCode); $($controlScan.files) file(s), $(@($controlScan.unreadable).Count) unreadable $(@($controlScan.unreadable) -join '; '); History files: $(@($controlScan.history) -join '; '); hits: $(@($controlScan.hits) -join '; ')."))
    }
    catch { $checks.Add((New-Check 'Phase completed' 'browsing-history.error' $false $_.Exception.Message)) }
    Add-Phase -Name 'browsing-history' -Checks $checks
}
catch {
    Add-Phase -Name 'error' -Checks @(New-Check 'Payload completed' 'payload.error' $false $_.Exception.Message)
}
finally {
    if ($null -ne $listener) {
        Stop-Job -Job $listener -ErrorAction SilentlyContinue
        Remove-Job -Job $listener -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $RequestLog) { Copy-Item -LiteralPath $RequestLog -Destination $Artifacts }
}

$overall = 'PASS'
if (@($phases | Where-Object { $_.status -ne 'PASS' }).Count -gt 0) { $overall = 'FAIL' }
# ToArray rather than @(): Windows PowerShell 5.1 cannot build this object from a List inside @().
[pscustomobject][ordered]@{ status = $overall; phases = $phases.ToArray() } |
    ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $env:TIGERWINLAB_JOB_RESULT -Encoding UTF8

if ($overall -ne 'PASS') { exit 1 }
exit 0
