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

try {
    # --- staging ---------------------------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]

    if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $AppRoot, $DocRoot -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $PSScriptRoot 'app.zip'), $AppRoot)
    $viewerExe = Join-Path $AppRoot 'TigerMarkView.exe'
    $cliExe = Join-Path $AppRoot 'tiger-mark.exe'

    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'hostile.md') -Destination $DocRoot
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
    Add-Phase -Name 'staging' -Checks $checks
    if (-not $ready) { throw 'The request logger did not start.' }

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
