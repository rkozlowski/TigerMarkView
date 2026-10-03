<#
    .SYNOPSIS
    TigerWinLab guest payload: proves the TigerMarkView installer and its shell integration on a real
    Windows desktop.

    .DESCRIPTION
    Runs inside a TigerWinLab -Desktop job (Windows PowerShell 5.1, session 0, as LabAdmin); the
    interactive standard user is reached through $TigerWinLabDesktop. run.json names the candidate
    installer, the published Inno Setup installer it migrates from, a later installer it is upgraded
    to in place, the .NET runtime to provision, and the theme of the run. In order:

      fresh-install      per user, no prerequisite prompt, registration, PATH, Start Menu, the
                         Markdown handler offered by Open with, no default written (what a double-click
                         then does is recorded); then uninstall, which removes the local data too
      upgrade            the published Inno Setup installation, per user, replaced in place: legacy
                         registration and uninstaller gone, settings kept, one PATH entry, no default
                         written
      shell-open         Open with -> TigerMarkView on a path with spaces and Unicode, the exact
                         command line, Open Recent, the theme on screen
      navigation         a followed link stays out of Open Recent
      picker-open        File > Open adds to Open Recent
      drag-drop          a file dragged from Explorer onto the document area opens and enters Open Recent
      upgrade-in-place   the candidate upgraded to the later installer: the data removal does not run,
                         settings, Open Recent and the WebView2 profile are kept
      clear-recent       File > Open Recent > Clear Recent Files, by real pointer input: the saved list is
                         empty, everything else in the settings and the documents themselves are kept
      uninstall          files, registration, PATH, handler and capability gone; the local data
                         removed, neighbouring data sharing its names' prefix and the documents kept,
                         and Markdown resolving exactly as before the first install
      machine-scope      an all-users Inno Setup installation replaced by an all-users install, and
                         removed again

    Writes the phase/check result to TIGERWINLAB_JOB_RESULT and exits 0 only when every check passes.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = 'C:\TigerMarkViewAcceptance'
$AppRoot = Join-Path $Root 'app'
$IoRoot = Join-Path $Root 'io'
# Spaces, Polish letters, an en dash and a diaeresis: what a shell launch has to carry intact.
$DocRoot = Join-Path $Root 'Dokumenty – zażółć gęślą'
$Artifacts = $env:TIGERWINLAB_JOB_ARTIFACTS
$ProgId = 'TigerMarkView.Markdown'
$LegacyKey = '{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}_is1'
$Config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$Candidate = Join-Path $AppRoot ([string] $Config.candidate)
$Legacy = Join-Path $AppRoot ([string] $Config.legacy)
$Next = Join-Path $AppRoot ([string] $Config.next)

$phases = New-Object System.Collections.Generic.List[object]

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

function ConvertTo-Argument([string] $Value) {
    # The desktop agent's Start-Process joins arguments with spaces and quotes nothing.
    if ($Value -match '\s' -and $Value -notmatch '^".*"$') { return '"' + $Value + '"' }
    $Value
}

function Invoke-AsUser {
    <# Runs a program as the interactive standard user and waits for it. #>
    param([string] $FilePath, [string[]] $Arguments = @(), [int] $TimeoutSeconds = 600)
    Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command run -Parameters @{
        filePath = $FilePath; arguments = @($Arguments | ForEach-Object { ConvertTo-Argument $_ }); timeoutSeconds = $TimeoutSeconds }
}

function Invoke-UserScript([string] $Script) {
    Invoke-AsUser -FilePath 'powershell.exe' -Arguments @('-NoProfile', '-NonInteractive', '-EncodedCommand',
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))) -TimeoutSeconds 120
}

function Invoke-Shell {
    <# shell.ps1 as the interactive user; returns its JSON result. #>
    param([string] $Mode, [hashtable] $Request = @{}, [string] $Name)
    $requestPath = Join-Path $IoRoot "$Name.request.json"
    $resultPath = Join-Path $IoRoot "$Name.json"
    [IO.File]::WriteAllText($requestPath, ($Request | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    $run = Invoke-AsUser -FilePath 'powershell.exe' -Arguments @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $Root 'shell.ps1'), $Mode, $requestPath, $resultPath) -TimeoutSeconds 180
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "shell.ps1 $Mode wrote no result (exit $($run.exitCode)): $(@($run.stderr) -join ' ')"
    }
    Copy-Item -LiteralPath $resultPath -Destination $Artifacts -Force
    Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Invoke-Setup {
    <# A TigerSetup installer or uninstaller, quiet, with its log and outcome kept as evidence. #>
    param([string] $FilePath, [string[]] $Arguments, [string] $Name, [switch] $AsAdministrator)
    $log = Join-Path $IoRoot "$Name.log"
    $all = @($Arguments) + @('--quiet', '--json', '--log', $log)
    if ($AsAdministrator) {
        $out = Join-Path $IoRoot "$Name.stdout.txt"
        $process = Start-Process -FilePath $FilePath -ArgumentList ($all | ForEach-Object { ConvertTo-Argument $_ }) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out
        $result = [pscustomobject]@{ exitCode = $process.ExitCode; stdout = @(Get-Content -LiteralPath $out -ErrorAction SilentlyContinue); stderr = @() }
    }
    else {
        $result = Invoke-AsUser -FilePath $FilePath -Arguments $all
    }
    if (Test-Path -LiteralPath $log) { Copy-Item -LiteralPath $log -Destination $Artifacts -Force }
    [IO.File]::WriteAllText((Join-Path $Artifacts "$Name.outcome.json"), (@($result.stdout) -join "`n"), (New-Object Text.UTF8Encoding $false))
    $result
}

function Split-Command([string] $Text) {
    <# A registered uninstall command: its quoted or unquoted program, and its arguments. #>
    $Text = $Text.Trim()
    if ($Text.StartsWith('"')) {
        $end = $Text.IndexOf('"', 1)
        return [pscustomobject]@{ program = $Text.Substring(1, $end - 1); arguments = @($Text.Substring($end + 1).Trim() -split '\s+' | Where-Object { $_ }) }
    }
    $parts = @($Text -split '\s+')
    [pscustomobject]@{ program = $parts[0]; arguments = @($parts | Select-Object -Skip 1) }
}

function Get-PathEntries([string] $Value) { @(([string] $Value) -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }) }

function Get-Settings([string] $LocalAppData) {
    $path = Join-Path $LocalAppData 'TigerMarkView\settings.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-Recent([object] $Settings, [string] $Path) {
    if ($null -eq $Settings -or $null -eq $Settings.PSObject.Properties['recentFiles']) { return $false }
    @($Settings.recentFiles | Where-Object { [string]::Equals([string] $_, $Path, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
}

function Test-RecentEmpty([object] $Settings) {
    $null -ne $Settings -and $null -ne $Settings.PSObject.Properties['recentFiles'] -and @($Settings.recentFiles).Count -eq 0
}

function Get-OutcomeAction {
    <# What a run's --json outcome says about one custom action: parsed, and the action or $null. #>
    param([object] $Run, [string] $Name)
    $outcome = $null
    try { $outcome = (@($Run.stdout) -join "`n") | ConvertFrom-Json } catch { $outcome = $null }
    if ($null -eq $outcome) { return [pscustomobject]@{ parsed = $false; action = $null; text = 'no readable outcome' } }
    $action = $null
    if ($null -ne $outcome.PSObject.Properties['actions']) {
        $action = @($outcome.actions | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
    }
    $text = 'not run'
    if ($null -ne $action) { $text = "status $($action.status), exit $($action.exit_code)" }
    [pscustomobject]@{ parsed = $true; action = $action; text = $text }
}

function Test-DataRemoved {
    <# The uninstall's own data removal: both folders gone, and the action reported it completed. #>
    param([object] $Probe, [object] $Removal, [string] $Code)
    $data = Join-Path $Probe.localAppData 'TigerMarkView'
    $pages = Join-Path $Probe.temp 'TigerMarkView'
    $ran = Get-OutcomeAction -Run $Removal -Name 'remove-local-data'
    $gone = -not (Test-Path -LiteralPath $data) -and -not (Test-Path -LiteralPath $pages)
    $completed = $null -ne $ran.action -and [string] $ran.action.status -eq 'completed'
    New-Check 'Local data removed by the uninstall' $Code ($gone -and $completed) "$data exists: $(Test-Path -LiteralPath $data); $pages exists: $(Test-Path -LiteralPath $pages); remove-local-data: $($ran.text)."
}

function Wait-Viewer([string] $DocumentName, [int] $TimeoutSeconds = 90) {
    <# The viewer window showing a document; its title is "<file name> — TigerMarkView". #>
    try {
        Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{
            titlePattern = '^' + [regex]::Escape($DocumentName) + ' . TigerMarkView$'; timeoutSeconds = $TimeoutSeconds }
    }
    catch { $null }
}

function Wait-Condition([scriptblock] $Condition, [int] $TimeoutSeconds = 20) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    $false
}

function Get-MeanLuminance([string] $PngPath, [double] $Top, [double] $Bottom) {
    <# Mean luminance, 0-255, of the middle band of a capture: the document area. #>
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap $PngPath
    try {
        $sum = 0.0; $count = 0
        $y0 = [int] ($bitmap.Height * $Top); $y1 = [int] ($bitmap.Height * $Bottom)
        for ($y = $y0; $y -lt $y1; $y += 4) {
            for ($x = [int] ($bitmap.Width * 0.1); $x -lt [int] ($bitmap.Width * 0.9); $x += 4) {
                $c = $bitmap.GetPixel($x, $y)
                $sum += 0.2126 * $c.R + 0.7152 * $c.G + 0.0722 * $c.B; $count++
            }
        }
        $sum / [math]::Max(1, $count)
    }
    finally { $bitmap.Dispose() }
}

function Find-Window([scriptblock] $Match, [int] $TimeoutSeconds = 30) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $found = @(Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command list-windows -Parameters @{} | Where-Object $Match)
        if ($found.Count -gt 0) { return $found[0] }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    $null
}

function Close-Windows([string] $ProcessName) {
    foreach ($window in @(Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command list-windows -Parameters @{} | Where-Object { $_.processName -eq $ProcessName })) {
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $window.hwnd; action = 'close' }
    }
    $null = Wait-Condition { @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue).Count -eq 0 } -TimeoutSeconds 20
}

function Invoke-DoubleClick([string] $Path, [string] $Name) {
    <# What opening a file the way a double-click does (ShellExecute, default verb) shows. #>
    $existing = @(Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command list-windows -Parameters @{} | ForEach-Object { [int64] $_.hwnd })
    # cmd's start is ShellExecute with the default verb: what a double-click in Explorer does.
    $started = Invoke-AsUser -FilePath 'cmd.exe' -Arguments @('/c', 'start', '""', $Path) -TimeoutSeconds 60
    $launch = "start exit $($started.exitCode)"
    # Whatever window the shell brings up next: the app it chose, or its prompt to choose one.
    $window = Find-Window { $existing -notcontains [int64] $_.hwnd -and $_.title } -TimeoutSeconds 45
    $shown = "no new window ($launch)"
    if ($null -ne $window) {
        $shown = "$($window.processName): $($window.title)"
        $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name "$Name.png" -Destination $Artifacts
    }
    if ($null -ne $window) { $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $window.hwnd; action = 'close'; settleMilliseconds = 1000 } }
    foreach ($process in 'TigerMarkView', 'OpenWith', 'Notepad') { Close-Windows $process }
    $shown
}

function Test-Installed {
    <# The per-user installation as the probe sees it, as checks. #>
    param([object] $Probe, [string] $Version, [string] $Prefix)
    $root = Join-Path $Probe.localAppData 'Programs\TigerMarkView'
    $link = Join-Path $Probe.appData 'Microsoft\Windows\Start Menu\Programs\TigerMarkView.lnk'
    $entries = @(Get-PathEntries $Probe.userPath | Where-Object { $_ -ieq $root })
    $command = '"' + (Join-Path $root 'TigerMarkView.exe') + '" "%1"'
    $md = $Probe.extensions.'.md'
    $markdown = $Probe.extensions.'.markdown'
    $handler = @($md.handlers | Where-Object { ([string] $_.name) -like '*\TigerMarkView.exe' })
    @(
        (New-Check 'Files installed per user' "$Prefix.files" ((Test-Path (Join-Path $root 'TigerMarkView.exe')) -and (Test-Path (Join-Path $root 'tiger-mark.exe')) -and (Test-Path (Join-Path $root 'Docs\HELP.md')) -and -not (Test-Path (Join-Path $root 'unins000.exe'))) "Install root $root.")
        (New-Check 'Add/Remove Programs entry' "$Prefix.registration" ($Probe.registration.exists -and $Probe.registration.displayName -eq 'TigerMarkView' -and $Probe.registration.displayVersion -eq $Version -and $Probe.registration.publisher -eq 'IT Tiger' -and -not $Probe.legacyRegistration) "ItTiger.TigerMarkView: '$($Probe.registration.displayName)' $($Probe.registration.displayVersion) by $($Probe.registration.publisher); Inno entry present: $($Probe.legacyRegistration).")
        (New-Check 'One user PATH entry' "$Prefix.path" ($entries.Count -eq 1) "Entries for $root in the user PATH: $($entries.Count).")
        (New-Check 'Start Menu shortcut' "$Prefix.shortcut" (Test-Path -LiteralPath $link) $link)
        (New-Check 'Markdown handler class' "$Prefix.progid" ($Probe.progIdExists -and $Probe.progIdCommand -eq $command) "HKCU $ProgId opens with: $($Probe.progIdCommand)")
        (New-Check 'Offered for .md and .markdown' "$Prefix.open-with-progids" ((@($md.openWithProgids) -contains $ProgId) -and (@($markdown.openWithProgids) -contains $ProgId)) ".md: $(@($md.openWithProgids) -join ', '); .markdown: $(@($markdown.openWithProgids) -join ', ').")
        (New-Check 'Listed by Open with' "$Prefix.open-with" ($handler.Count -eq 1 -and $handler[0].recommended) "SHAssocEnumHandlers(.md): $(@($md.handlers | ForEach-Object { '{0} [{1}]' -f $_.uiName, $_.recommended }) -join '; ').")
        (New-Check 'Default apps capability' "$Prefix.capability" ($Probe.capabilitiesExists -and $Probe.registeredApplication -eq 'Software\IT Tiger\TigerMarkView\Capabilities' -and $md.capability -eq $ProgId -and $markdown.capability -eq $ProgId) "RegisteredApplications: $($Probe.registeredApplication).")
    )
}

function Test-Removed {
    param([object] $Probe, [string] $Prefix)
    $root = Join-Path $Probe.localAppData 'Programs\TigerMarkView'
    $link = Join-Path $Probe.appData 'Microsoft\Windows\Start Menu\Programs\TigerMarkView.lnk'
    $state = Join-Path $Probe.localAppData 'TigerSetup\ItTiger.TigerMarkView'
    $entries = @(Get-PathEntries $Probe.userPath | Where-Object { $_ -ieq $root })
    $md = $Probe.extensions.'.md'
    $markdown = $Probe.extensions.'.markdown'
    @(
        (New-Check 'Files removed' "$Prefix.files" (-not (Test-Path -LiteralPath $root)) "Install root $root exists: $(Test-Path -LiteralPath $root).")
        (New-Check 'Registration removed' "$Prefix.registration" (-not $Probe.registration.exists -and -not $Probe.legacyRegistration) "ItTiger.TigerMarkView: $($Probe.registration.exists); Inno entry: $($Probe.legacyRegistration).")
        (New-Check 'PATH entry removed' "$Prefix.path" ($entries.Count -eq 0) "Entries left: $($entries.Count).")
        (New-Check 'Shortcut removed' "$Prefix.shortcut" (-not (Test-Path -LiteralPath $link)) $link)
        (New-Check 'Handler and capability removed' "$Prefix.handler" (-not $Probe.progIdExists -and -not $Probe.capabilitiesExists -and -not $Probe.registeredApplication -and (@($md.openWithProgids) -notcontains $ProgId) -and (@($markdown.openWithProgids) -notcontains $ProgId) -and @($md.handlers | Where-Object { ([string] $_.name) -like '*\TigerMarkView.exe' }).Count -eq 0) "ProgID: $($Probe.progIdExists); capability: $($Probe.capabilitiesExists); RegisteredApplications: '$($Probe.registeredApplication)'; .md OpenWithProgids: $(@($md.openWithProgids) -join ', ').")
        (New-Check 'Installer state removed' "$Prefix.state" (-not (Test-Path -LiteralPath $state)) $state)
    )
}

try {
    # --- staging ---------------------------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $AppRoot, $IoRoot, $DocRoot -Force
    foreach ($file in @($Config.candidate, $Config.legacy, $Config.next, $Config.runtime)) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $AppRoot }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'shell.ps1') -Destination $Root

    $unicodeDoc = Join-Path $DocRoot 'Notatki – zażółć gęślą.md'
    $linkedDoc = Join-Path $DocRoot 'linked doc.md'
    $pickedDoc = Join-Path $DocRoot 'picked file ü.md'
    $droppedDoc = Join-Path $DocRoot 'dropped – ü.md'
    $utf8 = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($unicodeDoc, "# Zażółć gęślą jaźń`r`n`r`nOpened from the shell.`r`n`r`n[Linked document](linked%20doc.md)`r`n", $utf8)
    [IO.File]::WriteAllText($linkedDoc, "# Linked document`r`n`r`nReached by following a link.`r`n", $utf8)
    [IO.File]::WriteAllText($pickedDoc, "# Picked file`r`n`r`nOpened with File > Open.`r`n", $utf8)
    [IO.File]::WriteAllText($droppedDoc, "# Dropped file`r`n`r`nDragged from Explorer onto the document.`r`n", $utf8)

    $null = & icacls.exe $Root '/grant' 'Users:(OI)(CI)M' '/T' '/Q' 2>&1
    $checks.Add((New-Check 'Payload staged' 'stage.files' ((Test-Path $Candidate) -and (Test-Path $Legacy) -and (Test-Path $Next) -and $LASTEXITCODE -eq 0) "Candidate $($Config.candidate) $($Config.version), legacy $($Config.legacy), later $($Config.next) $($Config.nextVersion), documents under $DocRoot."))

    # The two runtimes the product declares. .NET is installed from the staged offline installer;
    # the Evergreen WebView2 Runtime is part of Windows 11.
    $runtime = Start-Process -FilePath (Join-Path $AppRoot $Config.runtime) -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
    $dotnet = @(Get-ChildItem -LiteralPath "$env:ProgramFiles\dotnet\shared\Microsoft.WindowsDesktop.App" -Directory -Filter '10.*' -ErrorAction SilentlyContinue)
    $checks.Add((New-Check '.NET 10 Desktop Runtime' 'stage.dotnet' ($runtime.ExitCode -in 0, 3010 -and $dotnet.Count -gt 0) "Installer exit $($runtime.ExitCode); versions: $(@($dotnet | ForEach-Object Name) -join ', ')."))
    $webView = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue
    $checks.Add((New-Check 'WebView2 Runtime' 'stage.webview2' ($null -ne $webView -and $webView.pv -and $webView.pv -ne '0.0.0.0') "Version: $(if ($webView) { $webView.pv })."))

    $theme = [string] $Config.appTheme
    $seed = '$d = Join-Path $env:LOCALAPPDATA ''TigerMarkView''; $null = New-Item -ItemType Directory -Force $d; ' +
        "[IO.File]::WriteAllText((Join-Path `$d 'settings.json'), '{ ""theme"": ""$theme"" }')"
    $seeded = Invoke-UserScript $seed
    $checks.Add((New-Check 'Viewer theme seeded' 'stage.settings' ($seeded.exitCode -eq 0) "The interactive user's TigerMarkView theme is $theme; Windows theme is $($Config.windowsTheme)."))
    Add-Phase -Name 'staging' -Checks $checks

    # --- fresh install, per user -----------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $before = Invoke-Shell -Mode probe -Name 'fresh-before'
    $plainDoc = Join-Path $Root 'plain.md'
    [IO.File]::WriteAllText($plainDoc, "# Plain`r`n", (New-Object Text.UTF8Encoding $false))
    $doubleClickBefore = Invoke-DoubleClick -Path $plainDoc -Name 'fresh-double-click-before'
    $install = Invoke-Setup -FilePath $Candidate -Arguments @('install') -Name 'fresh-install'
    $checks.Add((New-Check 'Quiet per-user install' 'fresh.install' ($install.exitCode -eq 0) "Exit $($install.exitCode)."))
    $after = Invoke-Shell -Mode probe -Name 'fresh-after'
    foreach ($check in @(Test-Installed -Probe $after -Version $Config.version -Prefix 'fresh')) { $checks.Add($check) }
    $mdBefore = $before.extensions.'.md'; $mdAfter = $after.extensions.'.md'
    # The installer writes no default. What a double-click then does for a user who never chose a
    # Markdown app is Windows' own resolution among the offered handlers; it is recorded as evidence.
    $doubleClickAfter = Invoke-DoubleClick -Path $plainDoc -Name 'fresh-double-click-after'
    $checks.Add((New-Check 'No default written' 'fresh.no-default' (-not $mdAfter.classDefault -and -not $mdAfter.userChoice -and $mdBefore.userChoice -eq $mdAfter.userChoice) ".md class default '$($mdAfter.classDefault)', UserChoice '$($mdAfter.userChoice)'; AssocQueryString resolved '$($mdBefore.openCommand)' before and '$($mdAfter.openCommand)' after. With no app chosen, a double-click showed before install: $doubleClickBefore; after: $doubleClickAfter."))
    $cli = Invoke-AsUser -FilePath (Join-Path $after.localAppData 'Programs\TigerMarkView\tiger-mark.exe') -Arguments @('--version') -TimeoutSeconds 60
    $checks.Add((New-Check 'tiger-mark runs' 'fresh.cli' ($cli.exitCode -eq 0 -and (@($cli.stdout) -join ' ') -match [regex]::Escape($Config.version)) "tiger-mark --version: $(@($cli.stdout) -join ' ')"))

    $uninstallCommand = Split-Command ([string] $after.registration.quietUninstall)
    $removal = Invoke-Setup -FilePath $uninstallCommand.program -Arguments @($uninstallCommand.arguments | Where-Object { $_ -notin '--quiet' }) -Name 'fresh-uninstall'
    $checks.Add((New-Check 'Registered quiet uninstall' 'fresh.uninstall' ($removal.exitCode -eq 0) "$($after.registration.quietUninstall) -> exit $($removal.exitCode)."))
    $removed = Invoke-Shell -Mode probe -Name 'fresh-removed'
    foreach ($check in @(Test-Removed -Probe $removed -Prefix 'fresh-cleanup')) { $checks.Add($check) }
    # The staged settings file is TigerMarkView's data like any other, so the uninstall removes it.
    $checks.Add((Test-DataRemoved -Probe $removed -Removal $removal -Code 'fresh-cleanup.data'))
    $reseeded = Invoke-UserScript $seed
    $checks.Add((New-Check 'Viewer theme seeded again' 'fresh-cleanup.reseed' ($reseeded.exitCode -eq 0) "The later phases show the viewer in the $theme theme."))
    Add-Phase -Name 'fresh-install' -Checks $checks

    # --- upgrade from the published Inno Setup installation, per user -----------------------------
    $checks = New-Object System.Collections.Generic.List[object]

    $legacyRun = Invoke-AsUser -FilePath $Legacy -Arguments @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/CURRENTUSER', '/TASKS=addtopath')
    $legacyProbe = Invoke-Shell -Mode probe -Name 'upgrade-legacy'
    $legacyRoot = Join-Path $legacyProbe.localAppData 'Programs\TigerMarkView'
    $checks.Add((New-Check 'Published version installed per user' 'upgrade.legacy' ($legacyRun.exitCode -eq 0 -and $legacyProbe.legacyRegistration -and (Test-Path (Join-Path $legacyRoot 'unins000.exe'))) "$($Config.legacy) exit $($legacyRun.exitCode); Inno registration: $($legacyProbe.legacyRegistration)."))
    $settingsPath = Join-Path $legacyProbe.localAppData 'TigerMarkView\settings.json'
    $settingsBefore = [IO.File]::ReadAllBytes($settingsPath)

    $upgrade = Invoke-Setup -FilePath $Candidate -Arguments @('install') -Name 'upgrade-install'
    $outcome = (@($upgrade.stdout) -join ' ') -replace '\s+', ' '
    $checks.Add((New-Check 'Quiet per-user upgrade' 'upgrade.install' ($upgrade.exitCode -eq 0) ("Exit $($upgrade.exitCode); outcome: " + $outcome.Substring(0, [math]::Min(600, $outcome.Length)))))
    $upgraded = Invoke-Shell -Mode probe -Name 'upgrade-after'
    foreach ($check in @(Test-Installed -Probe $upgraded -Version $Config.version -Prefix 'upgrade')) { $checks.Add($check) }
    $checks.Add((New-Check 'Legacy uninstaller gone' 'upgrade.legacy-removed' (-not (Test-Path (Join-Path $legacyRoot 'unins000.exe')) -and -not $upgraded.legacyRegistration) "unins000.exe present: $(Test-Path (Join-Path $legacyRoot 'unins000.exe'))."))
    $settingsAfter = [IO.File]::ReadAllBytes($settingsPath)
    $checks.Add((New-Check 'Settings kept' 'upgrade.settings' ([Convert]::ToBase64String($settingsBefore) -eq [Convert]::ToBase64String($settingsAfter)) $settingsPath))
    $mdLegacy = $legacyProbe.extensions.'.md'; $mdUpgraded = $upgraded.extensions.'.md'
    $upgradeDoubleClick = Invoke-DoubleClick -Path $plainDoc -Name 'upgrade-double-click'
    $checks.Add((New-Check 'No default written by the upgrade' 'upgrade.no-takeover' (-not $mdUpgraded.classDefault -and $mdUpgraded.userChoice -eq $mdLegacy.userChoice) "Class default '$($mdUpgraded.classDefault)', UserChoice '$($mdUpgraded.userChoice)' (was '$($mdLegacy.userChoice)'); with no app chosen, a double-click showed: $upgradeDoubleClick."))
    Add-Phase -Name 'upgrade' -Checks $checks
    $installRoot = Join-Path $upgraded.localAppData 'Programs\TigerMarkView'

    # --- Open with, on a path with spaces and Unicode ---------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $opened = Invoke-Shell -Mode open -Name 'shell-open' -Request @{ path = $unicodeDoc; handler = '\TigerMarkView.exe' }
    $viewer = Wait-Viewer -DocumentName (Split-Path -Leaf $unicodeDoc)
    $checks.Add((New-Check 'Open with starts TigerMarkView on the document' 'shell.open' ($opened.invoked -and $null -ne $viewer) "Invoked: $($opened.invoked) $($opened.failure); window: $(if ($viewer) { $viewer.title })."))
    $process = @(Get-CimInstance Win32_Process -Filter "Name='TigerMarkView.exe'")
    $expectedCommand = '"' + (Join-Path $installRoot 'TigerMarkView.exe') + '" "' + $unicodeDoc + '"'
    $checks.Add((New-Check 'The exact command line' 'shell.command-line' ($process.Count -eq 1 -and $process[0].CommandLine -eq $expectedCommand) "Started: $(@($process | ForEach-Object CommandLine) -join ' | ')"))
    $checks.Add((New-Check 'Shell open enters Open Recent' 'shell.recent' (Wait-Condition { Test-Recent (Get-Settings $upgraded.localAppData) $unicodeDoc }) $unicodeDoc))
    if ($null -ne $viewer) {
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $viewer.hwnd; action = 'bounds'; x = 700; y = 40; width = 900; height = 700 }
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $viewer.hwnd; action = 'activate'; settleMilliseconds = 1500 }
        $capture = Save-DesktopCapture -Session $TigerWinLabDesktop -Name "shell-open-$($Config.windowsTheme).png" -Destination $Artifacts -Hwnd ([int64] $viewer.hwnd)
        $luminance = Get-MeanLuminance -PngPath (Join-Path $Artifacts "shell-open-$($Config.windowsTheme).png") -Top 0.35 -Bottom 0.85
        $themed = if ($theme -eq 'Dark') { $luminance -lt 90 } else { $luminance -gt 165 }
        $checks.Add((New-Check "The document is shown in the $theme theme" 'shell.theme' $themed ("Mean luminance of the document area: {0:N0}." -f $luminance)))
    }
    Add-Phase -Name 'shell-open' -Checks $checks

    # --- a followed link stays out of Open Recent -----------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $linked = $null
    if ($null -ne $viewer) {
        $click = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = @{ hwnd = [int64] $viewer.hwnd; scope = 'descendants'; name = '^Linked document$'; index = 0 }; action = 'click'; settleMilliseconds = 1500 }
        $linked = Wait-Viewer -DocumentName 'linked doc.md' -TimeoutSeconds 30
    }
    $checks.Add((New-Check 'The link opens its document' 'navigation.follow' ($null -ne $linked) "Window: $(if ($linked) { $linked.title })."))
    Start-Sleep -Seconds 2
    $checks.Add((New-Check 'A followed link is not an Open Recent entry' 'navigation.not-recent' (-not (Test-Recent (Get-Settings $upgraded.localAppData) $linkedDoc)) $linkedDoc))
    Add-Phase -Name 'navigation' -Checks $checks

    # --- File > Open -----------------------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $picked = $null
    if ($null -ne $viewer) {
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-invoke -Parameters @{ selector = @{ hwnd = [int64] $viewer.hwnd; scope = 'descendants'; automationId = 'OpenToolbarButton'; index = 0 }; pattern = 'invoke'; settleMilliseconds = 500 }
        $dialog = $null
        try { $dialog = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ titlePattern = '^Open Markdown File$'; timeoutSeconds = 30 } } catch { $dialog = $null }
        if ($null -ne $dialog) {
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $dialog.hwnd; action = 'activate'; settleMilliseconds = 1000 }
            $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name "open-dialog-$($Config.windowsTheme).png" -Destination $Artifacts -Hwnd ([int64] $dialog.hwnd)
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command keyboard -Parameters @{ action = 'text'; text = $pickedDoc; settleMilliseconds = 500 }
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command keyboard -Parameters @{ action = 'keys'; keys = @('Enter') }
        }
        $picked = Wait-Viewer -DocumentName (Split-Path -Leaf $pickedDoc) -TimeoutSeconds 30
    }
    $checks.Add((New-Check 'File > Open opens the chosen file' 'picker.open' ($null -ne $picked) "Window: $(if ($picked) { $picked.title })."))
    $checks.Add((New-Check 'File > Open enters Open Recent' 'picker.recent' (Wait-Condition { Test-Recent (Get-Settings $upgraded.localAppData) $pickedDoc }) $pickedDoc))
    Add-Phase -Name 'picker-open' -Checks $checks

    # --- drag and drop from Explorer onto the document area --------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $dropped = $null
    $hit = $null
    if ($null -ne $picked) {
        $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = 'explorer.exe'; arguments = @(ConvertTo-Argument $DocRoot) }
        $explorer = $null
        try { $explorer = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command wait-window -Parameters @{ classPattern = '^CabinetWClass$'; titlePattern = 'Dokumenty'; timeoutSeconds = 45 } } catch { $explorer = $null }
        if ($null -ne $explorer) {
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $explorer.hwnd; action = 'bounds'; x = 20; y = 40; width = 660; height = 700 }
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $picked.hwnd; action = 'bounds'; x = 700; y = 40; width = 900; height = 700 }
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $picked.hwnd; action = 'activate'; settleMilliseconds = 500 }
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $explorer.hwnd; action = 'activate'; settleMilliseconds = 1500 }
            $item = $null
            try { $item = (Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-wait -Parameters @{ selector = @{ hwnd = [int64] $explorer.hwnd; scope = 'descendants'; controlType = 'ListItem'; name = '^dropped – ü(\.md)?$'; index = 0 }; timeoutSeconds = 30 }).element } catch { $item = $null }
            $viewerBounds = (Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $picked.hwnd; action = 'bounds'; x = 700; y = 40; width = 900; height = 700 }).bounds
            # The middle of the rendered page: the WebView, not the menu, toolbar or status bar.
            $targetX = [int] ($viewerBounds.x + $viewerBounds.width / 2)
            $targetY = [int] ($viewerBounds.y + $viewerBounds.height * 0.6)
            $hit = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command hit-test -Parameters @{ x = $targetX; y = $targetY }
            $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name "drag-before-$($Config.windowsTheme).png" -Destination $Artifacts
            if ($null -ne $item -and $null -ne $item.bounds) {
                $startX = [int] $item.bounds.centerX; $startY = [int] $item.bounds.centerY
                $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ x = $startX; y = $startY; action = 'down'; settleMilliseconds = 300 }
                for ($step = 1; $step -le 12; $step++) {
                    $x = [int] ($startX + ($targetX - $startX) * $step / 12); $y = [int] ($startY + ($targetY - $startY) * $step / 12)
                    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ x = $x; y = $y; action = 'move'; settleMilliseconds = 120 }
                }
                $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ x = $targetX; y = $targetY; action = 'move'; settleMilliseconds = 800 }
                $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ x = $targetX; y = $targetY; action = 'up'; settleMilliseconds = 1000 }
            }
            $dropped = Wait-Viewer -DocumentName (Split-Path -Leaf $droppedDoc) -TimeoutSeconds 30
            $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name "drag-after-$($Config.windowsTheme).png" -Destination $Artifacts
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $explorer.hwnd; action = 'close' }
        }
        $checks.Add((New-Check 'Explorer shows the file to drag' 'drag.source' ($null -ne $explorer -and $null -ne $item) "Explorer: $(if ($explorer) { $explorer.title }); item: $(if ($item) { $item.name })."))
    }
    $hitText = if ($null -ne $hit) { $hit | ConvertTo-Json -Depth 4 -Compress } else { 'none' }
    [IO.File]::WriteAllText((Join-Path $Artifacts 'drag-hit-test.json'), $hitText, (New-Object Text.UTF8Encoding $false))
    $checks.Add((New-Check 'The drop lands on the document area' 'drag.target' ($hitText -match 'Chrome_|msedgewebview2|WebView') "Hit test at the drop point: $($hitText.Substring(0, [math]::Min(400, $hitText.Length)))"))
    $checks.Add((New-Check 'The dropped file opens' 'drag.open' ($null -ne $dropped) "Window: $(if ($dropped) { $dropped.title })."))
    $checks.Add((New-Check 'The dropped file enters Open Recent' 'drag.recent' (Wait-Condition { Test-Recent (Get-Settings $upgraded.localAppData) $droppedDoc }) $droppedDoc))
    $settings = Get-Settings $upgraded.localAppData
    [IO.File]::WriteAllText((Join-Path $Artifacts 'settings-after-opens.json'), ($settings | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
    Add-Phase -Name 'drag-drop' -Checks $checks

    # --- an upgrade keeps the local data ---------------------------------------------------------
    # The installed candidate carries the uninstall-only data removal; an upgrade must not run it.
    $checks = New-Object System.Collections.Generic.List[object]
    Close-Windows 'TigerMarkView'
    $settingsBeforeUpgrade = [IO.File]::ReadAllBytes($settingsPath)
    $viewerProfile = Join-Path $upgraded.localAppData 'TigerMarkView\WebView2\Viewer'
    $profileBeforeUpgrade = Test-Path -LiteralPath $viewerProfile
    $inPlace = Invoke-Setup -FilePath $Next -Arguments @('install') -Name 'in-place-upgrade'
    $checks.Add((New-Check 'Quiet upgrade to a later version' 'in-place.install' ($inPlace.exitCode -eq 0) "$($Config.next) exit $($inPlace.exitCode)."))
    $inPlaceProbe = Invoke-Shell -Mode probe -Name 'in-place-after'
    foreach ($check in @(Test-Installed -Probe $inPlaceProbe -Version $Config.nextVersion -Prefix 'in-place')) { $checks.Add($check) }
    $ranOnUpgrade = Get-OutcomeAction -Run $inPlace -Name 'remove-local-data'
    $checks.Add((New-Check 'The data removal does not run on an upgrade' 'in-place.no-removal' ($ranOnUpgrade.parsed -and $null -eq $ranOnUpgrade.action) "remove-local-data during the upgrade: $($ranOnUpgrade.text)."))
    $afterUpgrade = Get-Settings $upgraded.localAppData
    $keptRecent = (Test-Recent $afterUpgrade $unicodeDoc) -and (Test-Recent $afterUpgrade $pickedDoc) -and (Test-Recent $afterUpgrade $droppedDoc)
    $checks.Add((New-Check 'Settings and Open Recent kept by the upgrade' 'in-place.settings' ((Test-Path -LiteralPath $settingsPath) -and $keptRecent -and [Convert]::ToBase64String($settingsBeforeUpgrade) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath))) "$settingsPath unchanged; the three opened documents still listed: $keptRecent."))
    $checks.Add((New-Check 'WebView2 profile kept by the upgrade' 'in-place.profile' ($profileBeforeUpgrade -and (Test-Path -LiteralPath $viewerProfile)) "$viewerProfile before: $profileBeforeUpgrade; after: $(Test-Path -LiteralPath $viewerProfile)."))
    Add-Phase -Name 'upgrade-in-place' -Checks $checks
    $installRoot = Join-Path $inPlaceProbe.localAppData 'Programs\TigerMarkView'

    # --- File > Open Recent > Clear Recent Files --------------------------------------------------
    # Avalonia's File menu exposes no UIA invoke or expand pattern, so the menu is driven by real
    # pointer input; its submenus are popup windows of the viewer's process.
    $checks = New-Object System.Collections.Generic.List[object]
    $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command start-process -Parameters @{ filePath = (Join-Path $installRoot 'TigerMarkView.exe'); arguments = @(ConvertTo-Argument $pickedDoc) }
    $reopened = Wait-Viewer -DocumentName (Split-Path -Leaf $pickedDoc)
    $checks.Add((New-Check 'The upgraded viewer opens a document' 'clear.open' ($null -ne $reopened) "Window: $(if ($reopened) { $reopened.title })."))
    $menuShown = $false
    $menuFailure = ''
    if ($null -ne $reopened) {
        try {
            $viewerProcess = [int] @(Get-Process -Name 'TigerMarkView' -ErrorAction Stop)[0].Id
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $reopened.hwnd; action = 'activate'; settleMilliseconds = 1000 }
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = @{ hwnd = [int64] $reopened.hwnd; scope = 'descendants'; automationId = 'FileMenu'; index = 0 }; action = 'click'; settleMilliseconds = 800 }
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-wait -Parameters @{ selector = @{ processId = $viewerProcess; automationId = 'OpenRecentMenuItem'; index = 0 }; timeoutSeconds = 15 }
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = @{ processId = $viewerProcess; automationId = 'OpenRecentMenuItem'; index = 0 }; action = 'click'; settleMilliseconds = 800 }
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command ui-wait -Parameters @{ selector = @{ processId = $viewerProcess; automationId = 'ClearRecentFilesMenuItem'; index = 0 }; timeoutSeconds = 15 }
            $menuShown = $true
            $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name "clear-recent-menu-$($Config.windowsTheme).png" -Destination $Artifacts
            $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command mouse -Parameters @{ selector = @{ processId = $viewerProcess; automationId = 'ClearRecentFilesMenuItem'; index = 0 }; action = 'click'; settleMilliseconds = 1000 }
        }
        catch { $menuFailure = $_.Exception.Message }
    }
    $checks.Add((New-Check 'Open Recent ends with Clear Recent Files' 'clear.menu' $menuShown "File > Open Recent > Clear Recent Files reached by pointer: $menuShown. $menuFailure"))
    $checks.Add((New-Check 'The cleared list is saved at once' 'clear.saved' (Wait-Condition { Test-RecentEmpty (Get-Settings $upgraded.localAppData) }) $settingsPath))
    $null = Save-DesktopCapture -Session $TigerWinLabDesktop -Name "clear-recent-after-$($Config.windowsTheme).png" -Destination $Artifacts
    Close-Windows 'TigerMarkView'
    $afterClear = Get-Settings $upgraded.localAppData
    $checks.Add((New-Check 'The list stays empty after the viewer closes, and the other settings are kept' 'clear.persisted' ((Test-RecentEmpty $afterClear) -and [string] $afterClear.theme -eq $theme) "recentFiles: $(@($afterClear.recentFiles).Count) entries; theme: $($afterClear.theme)."))
    $checks.Add((New-Check 'The documents themselves are untouched' 'clear.documents' ((Test-Path -LiteralPath $unicodeDoc) -and (Test-Path -LiteralPath $pickedDoc) -and (Test-Path -LiteralPath $droppedDoc) -and (Test-Path -LiteralPath $linkedDoc)) $DocRoot))
    Add-Phase -Name 'clear-recent' -Checks $checks

    # --- uninstall after the upgrade ---------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($window in @(Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command list-windows -Parameters @{})) {
        if ($window.processName -eq 'TigerMarkView') { $null = Invoke-DesktopCommand -Session $TigerWinLabDesktop -Command window -Parameters @{ hwnd = [int64] $window.hwnd; action = 'close' } }
    }
    $closed = Wait-Condition { @(Get-Process -Name 'TigerMarkView' -ErrorAction SilentlyContinue).Count -eq 0 } -TimeoutSeconds 30
    $checks.Add((New-Check 'The viewer closes' 'uninstall.viewer-closed' $closed 'Every TigerMarkView window was asked to close.'))
    $settingsBeforeRemoval = [IO.File]::ReadAllBytes($settingsPath)
    $installed = Invoke-Shell -Mode probe -Name 'uninstall-before'
    # Another application's data whose names share the prefix of the two data folders and of the
    # install root. The uninstall removes exactly its own folders, so every one of these is kept.
    $neighbours = @(
        (Join-Path $installed.localAppData 'TigerMarkView.Neighbour\keep.txt'),
        (Join-Path $installed.localAppData 'TigerMarkView-keep.txt'),
        (Join-Path $installed.localAppData 'Programs\TigerMarkView.Neighbour\keep.txt'),
        (Join-Path $installed.temp 'TigerMarkView.Neighbour\keep.txt'),
        (Join-Path $installed.temp 'TigerMarkView-keep.txt'))
    foreach ($neighbour in $neighbours) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $neighbour) -Force | Out-Null
        [IO.File]::WriteAllText($neighbour, 'another application', (New-Object Text.UTF8Encoding $false))
    }
    # The privacy statement discloses the browser engine's own history of the pages it showed; it lives
    # in the profile the uninstall removes.
    $engineHistory = Join-Path $installed.localAppData 'TigerMarkView\WebView2\Viewer\EBWebView\Default\History'
    $checks.Add((New-Check 'Browser engine history is in the removed profile' 'uninstall.engine-history' (Test-Path -LiteralPath $engineHistory -PathType Leaf) "$engineHistory exists before the uninstall: $(Test-Path -LiteralPath $engineHistory -PathType Leaf)."))
    $uninstallCommand = Split-Command ([string] $installed.registration.quietUninstall)
    $removal = Invoke-Setup -FilePath $uninstallCommand.program -Arguments @($uninstallCommand.arguments | Where-Object { $_ -notin '--quiet' }) -Name 'upgrade-uninstall'
    # The statement says the uninstaller's log (here written to an explicit --log path; by default to
    # %TEMP%\TigerSetup) names none of the reader's documents, though it removes data that did.
    $uninstallLog = Join-Path $IoRoot 'upgrade-uninstall.log'
    $logText = if (Test-Path -LiteralPath $uninstallLog) { [IO.File]::ReadAllText($uninstallLog) } else { '' }
    $logNamesDocument = $logText.Contains($DocRoot) -or $logText.Contains('picked file') -or $logText.Contains('dropped') -or $logText.Contains('linked doc')
    $checks.Add((New-Check 'The uninstall log names no document' 'uninstall.setup-log' ($logText.Length -gt 0 -and -not $logNamesDocument) "$uninstallLog ($($logText.Length) characters) names a document: $logNamesDocument."))
    $checks.Add((New-Check 'Registered quiet uninstall' 'uninstall.run' ($removal.exitCode -eq 0) "$($installed.registration.quietUninstall) -> exit $($removal.exitCode)."))
    $removed = Invoke-Shell -Mode probe -Name 'uninstall-after'
    foreach ($check in @(Test-Removed -Probe $removed -Prefix 'uninstall')) { $checks.Add($check) }
    $checks.Add((Test-DataRemoved -Probe $removed -Removal $removal -Code 'uninstall.data'))
    $keptNeighbours = @($neighbours | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    $checks.Add((New-Check 'Neighbouring data is kept' 'uninstall.neighbours' ($keptNeighbours.Count -eq $neighbours.Count) "$($keptNeighbours.Count) of $($neighbours.Count) kept: $($neighbours -join '; ')."))
    $checks.Add((New-Check 'The documents themselves are untouched' 'uninstall.documents' ((Test-Path -LiteralPath $unicodeDoc) -and (Test-Path -LiteralPath $pickedDoc) -and (Test-Path -LiteralPath $droppedDoc) -and $settingsBeforeRemoval.Length -gt 0) $DocRoot))
    $checks.Add((New-Check 'Markdown resolves as before the installer' 'uninstall.association-restored' (-not $removed.extensions.'.md'.classDefault -and $removed.extensions.'.md'.userChoice -eq $mdBefore.userChoice -and $removed.extensions.'.md'.openCommand -eq $mdBefore.openCommand) "Opening a .md file resolves to '$($removed.extensions.'.md'.openCommand)' (before any install: '$($mdBefore.openCommand)')."))
    Add-Phase -Name 'uninstall' -Checks $checks

    # --- all users ---------------------------------------------------------------------------------
    $checks = New-Object System.Collections.Generic.List[object]
    $machineRoot = Join-Path $env:ProgramFiles 'TigerMarkView'
    $hklmUninstall = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $machinePathKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $legacyMachine = Start-Process -FilePath $Legacy -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/ALLUSERS', '/TASKS=addtopath' -Wait -PassThru
    $checks.Add((New-Check 'Published version installed for all users' 'machine.legacy' ($legacyMachine.ExitCode -eq 0 -and (Test-Path "$hklmUninstall\$LegacyKey") -and (Test-Path (Join-Path $machineRoot 'unins000.exe'))) "Exit $($legacyMachine.ExitCode)."))
    $machineInstall = Invoke-Setup -FilePath $Candidate -Arguments @('install', '--scope', 'machine') -Name 'machine-install' -AsAdministrator
    # Evidence for the migration: what the Inno Setup uninstaller had left of its directory when
    # TigerSetup installed, and later what is left after the removal.
    $leftovers = { param($Label) "${Label}: " + ((@(Get-ChildItem -LiteralPath $machineRoot -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($machineRoot.Length) }) | Select-Object -First 20) -join ', ') }
    $machineEntries = @(Get-PathEntries (Get-ItemProperty -LiteralPath $machinePathKey).Path | Where-Object { $_ -ieq $machineRoot })
    $machineCommand = [string] (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Classes\$ProgId\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
    $machineOpenWith = @((Get-Item -LiteralPath 'HKLM:\SOFTWARE\Classes\.md\OpenWithProgids' -ErrorAction SilentlyContinue).GetValueNames())
    $checks.Add((New-Check 'All-users upgrade' 'machine.install' ($machineInstall.exitCode -eq 0 -and (Test-Path "$hklmUninstall\ItTiger.TigerMarkView") -and -not (Test-Path "$hklmUninstall\$LegacyKey") -and -not (Test-Path (Join-Path $machineRoot 'unins000.exe')) -and (Test-Path (Join-Path $machineRoot 'TigerMarkView.exe'))) "Exit $($machineInstall.exitCode)."))
    $checks.Add((New-Check 'One machine PATH entry' 'machine.path' ($machineEntries.Count -eq 1) "Entries for $($machineRoot): $($machineEntries.Count)."))
    $checks.Add((New-Check 'All-users Markdown handler' 'machine.handler' ($machineCommand -eq ('"' + (Join-Path $machineRoot 'TigerMarkView.exe') + '" "%1"') -and $machineOpenWith -contains $ProgId) "HKLM $ProgId opens with: $machineCommand"))
    $quiet = Split-Command ([string] (Get-ItemProperty -LiteralPath "$hklmUninstall\ItTiger.TigerMarkView" -ErrorAction SilentlyContinue).QuietUninstallString)
    $machineRemoval = Invoke-Setup -FilePath $quiet.program -Arguments @($quiet.arguments | Where-Object { $_ -notin '--quiet' }) -Name 'machine-uninstall' -AsAdministrator
    $machineLeft = @(Get-PathEntries (Get-ItemProperty -LiteralPath $machinePathKey).Path | Where-Object { $_ -ieq $machineRoot })
    [IO.File]::WriteAllText((Join-Path $Artifacts 'machine-root-after-uninstall.txt'), (& $leftovers 'after uninstall'), (New-Object Text.UTF8Encoding $false))
    $checks.Add((New-Check 'All-users removal' 'machine.uninstall' ($machineRemoval.exitCode -eq 0 -and -not (Test-Path $machineRoot) -and -not (Test-Path "$hklmUninstall\ItTiger.TigerMarkView") -and -not (Test-Path "HKLM:\SOFTWARE\Classes\$ProgId") -and $machineLeft.Count -eq 0) "Exit $($machineRemoval.exitCode); install root left: $(Test-Path $machineRoot) ($(& $leftovers 'contents')); PATH entries left: $($machineLeft.Count)."))
    Add-Phase -Name 'machine-scope' -Checks $checks
}
catch {
    Add-Phase -Name 'error' -Checks @(New-Check 'Payload completed' 'payload.error' $false ($_.Exception.Message + ' at ' + $_.InvocationInfo.PositionMessage))
}
finally {
    if (Test-Path -LiteralPath $IoRoot) { Copy-Item -Path (Join-Path $IoRoot '*') -Destination $Artifacts -Force -ErrorAction SilentlyContinue }
}

$overall = 'PASS'
if (@($phases | Where-Object { $_.status -ne 'PASS' }).Count -gt 0) { $overall = 'FAIL' }
# ToArray rather than @(): Windows PowerShell 5.1 cannot build this object from a List inside @().
[pscustomobject][ordered]@{ status = $overall; phases = $phases.ToArray() } |
    ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $env:TIGERWINLAB_JOB_RESULT -Encoding UTF8

if ($overall -ne 'PASS') { exit 1 }
exit 0
