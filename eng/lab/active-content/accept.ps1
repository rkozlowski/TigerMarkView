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
# Every file shares.md names on \\127.0.0.1\tmvprobe; none of them may ever be asked for.
$ShareImages = @(
    'html-backslash.png', 'html-slash.png', 'html-file.png', 'html-file-four.png', 'html-encoded.png',
    'markdown-slash.png', 'markdown-backslash.png', 'css-background.png'
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

function Get-ShareAccess {
    # Detailed File Share auditing (event 5145) records every file an SMB client asked the probe share
    # for; the relative target name is the file. Returns the names requested since $Since.
    param([DateTime] $Since)
    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 5145; StartTime = $Since } -ErrorAction Stop) } catch { $events = @() }
    @($events | ForEach-Object {
            $data = @{}
            foreach ($node in ([xml] $_.ToXml()).Event.EventData.Data) { $data[$node.Name] = [string] $node.'#text' }
            if ($data['ShareName'] -like '*tmvprobe') { $data['RelativeTargetName'] }
        } | Where-Object { $_ })
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

    # The network share: \\127.0.0.1\tmvprobe in this guest, holding a file for every name a document
    # aims at it, with Detailed File Share auditing so each file an SMB client asks for is recorded.
    $null = New-Item -ItemType Directory -Path $ShareRoot -Force
    Set-Content -LiteralPath (Join-Path $ShareRoot 'control.txt') -Value 'control' -Encoding ASCII
    foreach ($name in $ShareImages + @('on-share.png', 'edge-control.png')) {
        Copy-Item -LiteralPath (Join-Path $DocRoot 'local.png') -Destination (Join-Path $ShareRoot $name)
    }
    Set-Content -LiteralPath (Join-Path $ShareRoot 'on-share.md') -Encoding UTF8 -Value (
        "# On a share`r`n`r`n![Share web image](http://127.0.0.1:$Port/img/on-share-web.png)`r`n`r`n![Relative share image](on-share.png)`r`n")
    $null = & icacls.exe $ShareRoot '/grant' 'Users:(OI)(CI)RX' '/T' '/Q' 2>&1
    Start-Service -Name LanmanServer
    $null = New-SmbShare -Name 'tmvprobe' -Path $ShareRoot -ReadAccess 'Everyone'
    # Detailed File Share, by GUID so the subcategory name's language does not matter.
    $null = & auditpol.exe /set '/subcategory:{0CCE9244-69AE-11D9-BED3-505054503030}' /success:enable /failure:enable 2>&1
    $auditOn = $LASTEXITCODE -eq 0
    $checks.Add((New-Check 'Audited probe share' 'stage.share' ($auditOn -and $null -ne (Get-SmbShare -Name 'tmvprobe' -ErrorAction SilentlyContinue)) "\\127.0.0.1\tmvprobe serves $ShareRoot with Detailed File Share auditing on."))

    # The viewer runs with Syntax Highlighting on and the Export to PDF toolbar button shown, written
    # as the interactive user into that user's own settings file.
    $seed = '$d = Join-Path $env:LOCALAPPDATA ''TigerMarkView''; $null = New-Item -ItemType Directory -Force $d; ' +
        '[IO.File]::WriteAllText((Join-Path $d ''settings.json''), ''{ "syntaxHighlighting": true, "toolbarExportPdfVisible": true }'')'
    $seeded = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{ filePath = 'powershell.exe'; arguments = @('-NoProfile', '-NonInteractive', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($seed))); timeoutSeconds = 60 }
    $checks.Add((New-Check 'Viewer settings seeded' 'stage.settings' ($seeded.exitCode -eq 0) "Syntax Highlighting and the Export to PDF toolbar button are on for the interactive user (exit $($seeded.exitCode); $(@($seeded.stderr) -join ' '))."))
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
    $viewerExfil = @($viewerRequests | Where-Object { $_.path -like '/exfil/*' })
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

    $touched = @(Get-ShareAccess -Since $since)
    $checks.Add((New-Check 'No share image is requested by the viewer' 'viewer.no-share-access' ($touched.Count -eq 0) "Share files asked for: $(Join-Names $touched). The document names $($ShareImages.Count) images on \\127.0.0.1\tmvprobe in every spelling it has."))
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
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-invoke -Parameters @{ selector = @{ hwnd = [int64] $window.hwnd; scope = 'descendants'; automationId = 'ExportPdfToolbarButton'; index = 0 }; pattern = 'invoke'; settleMilliseconds = 500 }
    $dialog = $null
    try { $dialog = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ processId = $app.processId; titlePattern = '^Export to PDF$'; timeoutSeconds = 30 } } catch { $dialog = $null }
    if ($null -ne $dialog) {
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $dialog.hwnd; action = 'activate'; settleMilliseconds = 500 }
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command keyboard -Parameters @{ action = 'sequence'; sequence = @(@{ action = 'down'; key = 'ControlKey' }, @{ action = 'down'; key = 'A' }, @{ action = 'up'; key = 'A' }, @{ action = 'up'; key = 'ControlKey' }) }
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command keyboard -Parameters @{ action = 'text'; text = $guiPdf; settleMilliseconds = 500 }
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command keyboard -Parameters @{ action = 'keys'; keys = @('Enter') }
    }
    $exported = Wait-File -Path $guiPdf -TimeoutSeconds 90
    $guiKeyword = Test-PdfHasColour -PdfPath $guiPdf -R $PrintKeyword[0] -G $PrintKeyword[1] -B $PrintKeyword[2]
    $guiComment = Test-PdfHasColour -PdfPath $guiPdf -R $PrintComment[0] -G $PrintComment[1] -B $PrintComment[2]
    $checks.Add((New-Check 'Syntax highlighting reaches the exported PDF' 'pdf.gui-highlighting' ($exported -and $guiKeyword -and $guiComment) "Save dialog found: $($null -ne $dialog); code-gui.pdf written: $exported; print keyword colour: $guiKeyword; print comment colour: $guiComment."))

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

    $pdfExfil = @($pdfRequests | Where-Object { $_.path -like '/exfil/*' })
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
    $touched = @(Get-ShareAccess -Since $since)
    $checks.Add((New-Check 'No share image is requested by PDF conversion' 'pdf.no-share-access' ($touched.Count -eq 0) "Share files asked for: $(Join-Names $touched)."))

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
