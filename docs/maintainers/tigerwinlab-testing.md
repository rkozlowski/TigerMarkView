# TigerMarkView release testing in TigerWinLab

Automated UI and destructive Windows integration tests use TigerWinLab so they cannot move the
maintainer's pointer, steal focus, close a live application, or mutate the workstation's installer,
PATH, ARP, WinGet, or prerequisite state. TigerHyperLab remains the registered-VM, lifecycle,
checkpoint, and lease substrate; TigerMarkView scripts call TigerWinLab's public commands only.

## Discovering the lab

TigerMarkView does not know where TigerWinLab lives. The machine declares it once, in the TigerAiCore
TOML file named by the `TigerAiCoreConfig` environment variable:

```toml
[labs.TigerWinLab]
type = "WindowsLab"
path = "<the TigerWinLab working copy>"
```

`eng/TigerAiCore.ps1` is the only discovery route this repository has. It resolves the entry named
above, checks the registered `type`, and checks that the scenario commands a script depends on exist.
There is no sibling-checkout guess, no `TIGERWINLAB_ROOT`, and no hardcoded path: when the lab is not
registered, the script says why and the lab check does not run. A guessed lab that happened to exist
would produce a `PASS` nobody could trace to a declared resource, which is worse than a missing one.

A maintainer may still pass `-TigerWinLabRoot` to point at a specific working copy. That is an
explicit decision rather than a guess, and it is verified the same way.

`eng/tests/TigerAiCore.Tests.ps1` covers this, including the refusal to find a checkout sitting exactly
where the old fallback used to look.

## Lab interface used by this repository

TigerWinLab provides the supported lifecycle and workload boundary:

- `Test-TigerWinLab.ps1` reports readiness;
- `Invoke-TigerWinLabJob.ps1` leases a clean baseline, copies a payload, runs PowerShell through
  PowerShell Direct, gives a `-Desktop` payload the interactive standard user's desktop (UI
  Automation, real pointer and keyboard input, window placement, captures), selects the run's
  `-Theme` and `-NetworkState`, and collects structured results and evidence;
- `Invoke-TigerWinLabDesktopScenario.ps1` runs the generic desktop composition: UI Automation
  exposure, semantic and physical input, modal and occlusion probes, and captures; and
- `Invoke-TigerWinLabWinGetScenario.ps1` validates manifests, dependencies, local-manifest install,
  hash refusal, PATH/command behavior, uninstall, and cleanup.

Each state-changing operation holds the lab's lease on one baseline VM, starts from and returns to
`BASE-CLEAN`, and writes a JSON result plus evidence. TigerMarkView invokes these entry points as
child processes with its own result path and never calls Hyper-V or TigerHyperLab directly.

## Repeatable release run

Build the candidate installer, then run the acceptance against it:

```powershell
pwsh installer/Build-Installer.ps1                       # or -Version <next> for an upgrade candidate
pwsh eng/lab/Test-TigerMarkViewRelease.ps1               # add -Version <next> to match
```

The wrapper checks the installer statically first (`eng/release-automation/Assert-Installer.ps1`),
then runs two lab phases on `TigerWinLab-Win11-Clean`.

**Installer acceptance** - `eng/lab/installer/accept.ps1` as one `-Desktop` job per Windows theme
(`-Theme light|dark|both`, both by default), offline, with the viewer's own theme set to match. The
host stages the candidate, the published installer it upgrades from, and the .NET 10 Desktop Runtime
installer (Microsoft-signed; Windows 11 already carries WebView2), and a later installer the candidate is
upgraded to in place (by default a fast local build of the next patch version). Every assertion is this
repository's; `eng/lab/installer/shell.ps1` reads the interactive user's own hive and shell as that
user. In order:

| Phase | Proves |
|---|---|
| `fresh-install` | a quiet per-user install: files, Add/Remove Programs, one user PATH entry, the Start Menu shortcut, the `TigerMarkView.Markdown` ProgID with the exact `"<exe>" "%1"` command, `OpenWithProgids` for `.md` and `.markdown`, the Default apps capability, TigerMarkView in the list `SHAssocEnumHandlers` gives Open with, no extension default or `UserChoice` written (what a ShellExecute of a `.md` file - a double-click's path - then opens is recorded), `tiger-mark` runs; then the registered quiet uninstall removes all of it, the user's `%LOCALAPPDATA%\TigerMarkView` and `%TEMP%\TigerMarkView` included, with `remove-local-data` reported `completed` |
| `upgrade` | the published Inno Setup release installed per user with its PATH task; the candidate replaces it in place: Inno registration and `unins000.exe` gone, one PATH entry, settings byte-identical, and no default written |
| `shell-open` | `IAssocHandler::Invoke` - Explorer's Open with - on a document whose folder and name carry spaces, Polish letters, an en dash and a diaeresis: the viewer shows it, the process command line is exactly the registered one, the file enters Open Recent, and the document area is dark or light as the theme asks |
| `navigation` | a real click on a local link opens the target, which does not enter Open Recent |
| `picker-open` | File > Open through the real dialog enters Open Recent |
| `drag-drop` | Explorer beside the viewer; a real pointer drag of a file onto the rendered document, the hit test proving the drop point is the WebView; the file opens and enters Open Recent |
| `upgrade-in-place` | the viewer closed and the candidate upgraded to the later installer: the later version installed, `remove-local-data` not run, settings byte-identical with the three opened documents still in Open Recent, and the WebView2 viewer profile kept |
| `clear-recent` | the upgraded viewer opened on a document; **File > Open Recent > Clear Recent Files** reached by real pointer input (the menu captured in the run's theme); the saved list empty at once and still empty after the viewer closes, the theme setting kept, and the documents untouched |
| `uninstall` | the upgraded installation removed: files, registration, PATH, handler and capability gone; the user's local data removed with `remove-local-data` reported `completed`; the documents untouched; `.md` resolving exactly as before the first install |
| `machine-scope` | the published release installed for all users is replaced by `--scope machine` (HKLM registration, machine PATH, HKLM handler) and removed cleanly |

The published installer is the last Inno Setup release published on GitHub, 0.8.1
(`-UpgradeFromVersion`), downloaded from GitHub and refused unless it matches the digest GitHub
recorded. A release whose asset is no longer served is passed
explicitly with `-UpgradeFromInstallerPath` - a retained copy of the published bytes, recorded by its
SHA-256.

**Desktop scenario** - the generic composition on a self-contained build: UI Automation exposure,
semantic commands, physical menu input, modal handling, occlusion, captures, and F1 Help.
`-SkipDesktopScenario` omits it.

Evidence lands under `artifacts\lab\<version>\`: each job's `job.json`, `result.json`, the installer
logs and `--json` outcomes, every probe's JSON, the drag hit test, the settings file after the opens,
and the captures.
## Release-workflow provisioning rehearsal

The release workflow installs the pinned TigerSetup release on a hosted runner with
`eng/release-automation/Install-TigerSetup.ps1`, under the runner's elevated administrator token - a
state no developer shell reproduces. `pwsh eng/lab/Test-TigerSetupProvisioning.ps1` runs that exact
script, with the same `installer/tigersetup.json`, as the elevated lab administrator in a clean
online guest, then has the provisioned builder build and verify a small package. Run it when the pin
or the script changes; it is not a release stage.

## Active-content acceptance

The acceptance also publishes the consumer-owned `eng/lab/active-content/probe` executable. It runs
only in the guest and loads sanitizer output without CSP, then deliberately unsanitized content with
CSP, then raw pages with the request boundary alone. It checks Chromium reparsing, literal hostile
fences, passive markup, data/SVG isolation, blocked script/style/fetch requests, allowed CSS images,
HTTP redirects, redirects to shares, and a mapped network drive with a successful read control.
The loopback request log and SMB audit are checked independently of the probe's DOM assertions.
Local and network symbolic links and SUBST drives have separate controls: inspecting a link must not open its network
target. Storage decisions and decoded image dimensions are both asserted. The `lifecycle` probe links the production `DocumentWebView` source and exercises actual
Avalonia adapter destruction/recreation, held navigation, message-source checks, and an injected
unsupported platform handle, including retry after failure. Both probes run only inside TigerWinLab.

Two audited shares separate what a document can cause from what the guest does on its own.
`\\127.0.0.1\tmvprobe` never gets a drive letter and is the strict oracle: any access to it inside a
measured window fails the check. `\\127.0.0.1\tmvmapped` is what the mapped drive `Z:` and the SUBST
alias `Y:` (built on a local symbolic link to that share) reach. The shell inspects a drive letter it
has just been shown on its own, opening the root and its `AutoRun.inf`/`Desktop.ini`, and event 5145
names the account but never the process, so those opens cannot be attributed; on that share only file
opens count. An environment control after the mapping records this activity and requires the strict
share to stay untouched, and every check message lists each access with its time and access mask. A
raw SUBST-alias page that bypasses the sanitizer is measured the same way. An NTLM challenge logs only
the presence of Authorization, never its value. That header must be absent for the independent probe,
viewer and PDF paths; web images are fetched through the shared credentialless HTTP client.

The host stages guest text as UTF-8 with BOM and checks the script with Windows PowerShell 5.1 before
launching the VM. The probes reuse the application's Windows manifest and dependencies.

Unit tests prove what the renderer emits: the sanitized HTML, the page's Content Security Policy, and
the request policy's decisions. Whether the real WebView2 engine then refuses what it should, inside
the real Avalonia viewer and the real `tiger-mark`, is proven in the lab:

```powershell
pwsh eng/lab/Test-TigerMarkViewActiveContent.ps1
```

The wrapper publishes the GUI and CLI self-contained into one tree and runs
`eng/lab/active-content/accept.ps1` as an `Invoke-TigerWinLabJob.ps1 -Desktop` job on
`TigerWinLab-Win11-Clean`, with the guest's network adapter disconnected. The guest starts a loopback
request logger and uses `eng/lab/active-content/hostile.md`, which aims every active construct at
`/exfil/<vector>` and its passive remote images at `/img/`, so the logger is the oracle. The payload
opens the document in the viewer and converts it with `tiger-mark`, then asserts that:

- both remote images are requested and no `/exfil/` request ever arrives, on either path, and that
  both paths make the same set of requests;
- the unsized relative local image is laid out at its real 48 px size in the viewer, and a PDF of a
  local-image-only document embeds an image while an image-free control embeds none;
- the document's own attempt to post `tigermarkview:help` opens nothing, and a real click on the former
  `javascript:` link changes nothing; and
- F1, pressed with focus inside the page, still opens Help — the proof that the shell's hash-admitted
  script runs under the policy.

Network shares are proven against `\\127.0.0.1\tmvprobe`, a share the payload creates in the guest with
Detailed File Share auditing (event 5145) on, so every file an SMB client asks for is recorded. Two
controls come first: a plain SMB read must appear in the audit, and headless Edge on a local page
naming an image on the share must fetch it — so the vector is real and the oracle sees it. Then
`eng/lab/active-content/shares.md`, which names the shares in every spelling (`\\`, `//`, `file://`,
four slashes, percent-encoded, a CSS background, the mapped drive, the SUBST alias in its browser
spellings, and a relative path through a symbolic link), is opened in the viewer and converted by
`tiger-mark`: no share file may be requested, while its relative and absolute local images and its web
image still load. A document opened from the share itself must be read, but its relative image must
not be — the case only the request boundary can stop.

`eng/lab/active-content/code.md` covers syntax highlighting and hostile code. The payload seeds the
interactive user's settings with Syntax Highlighting and the Export to PDF toolbar button on, opens the
document, counts keyword-coloured pixels in the viewer, drives GUI export through its Save dialog, and
checks the exported PDF's content streams for the print palette's keyword and comment colours; the
`tiger-mark` PDF of the same document, rendered without highlighting, is the control that must lack
them. The hostile blocks name `/exfil/` images, so any source that escaped into markup would show up in
the request log.

Evidence (the request log, captures, and the PDFs) lands under `artifacts\lab\active-content\job\`.

## Current concrete lab gaps

The TigerSetup wizard's interactive pages are not driven here; its quiet mode is. The wizard, its
light and dark themes, DPI scaling and the elevation hand-off are TigerSetup's own acceptance, proven
by its lab rows on every TigerSetup release. A user's existing `UserChoice` for `.md` is not exercised:
only Windows can write one, and its Pick an app flyout does not render for the lab's desktop agent;
Windows gives `UserChoice` precedence over every offered handler by design. The upgrade rows cover an Inno Setup installation in the
same scope as the new install; an all-users earlier installation next to a per-user new one is not
merged, because TigerSetup migrates only the scope it installs.

The desktop scenario requires a self-contained directory supplied by the host and does not attach to
an installed application, so installed-GUI behaviour is proven by the installer acceptance and the
generic desktop checks by the desktop scenario. Its fixed interaction sequence opens Help but cannot
navigate the multi-step About links or complete the Save dialog used by GUI PDF export; the
active-content acceptance drives GUI PDF export, and CLI/PDF unit and application tests remain the
automated PDF gate.

These are explicit gaps, not permission to fall back to invasive host-desktop automation. Record the
missing phase in release evidence and use a manual check inside the VM when it is release-critical.