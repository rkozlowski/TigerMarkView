# Lessons Learned

## Read guest JSON arrays before adding individual checks

**Area:** TigerWinLab acceptance payloads (Windows PowerShell 5.1)
**Status:** Active

`@(Get-Content ... | ConvertFrom-Json)` can contain one nested array in the guest even when it
enumerates individual objects under PowerShell 7. Adding that value to the phase's check list produces
an array where a check object belongs: every individual probe can pass while aggregation fails.

Assign the deserialized JSON to a variable, then iterate that variable when adding checks. Validate
guest-side collection handling with Windows PowerShell 5.1 before paying for another VM run.
The active-content acceptance's probe aggregation follows this pattern.

**Generalization candidate:** none; the consuming payload owns its result composition.

## Stage guest scripts with an explicit encoding

**Area:** TigerWinLab acceptance payloads (Windows PowerShell 5.1)
**Status:** Active

Windows PowerShell 5.1 reads BOM-less UTF-8 scripts as the system ANSI code page. Unicode punctuation
inside a string can become a quote and cause a misleading parser error hundreds of lines later.
Editors and patch tools can remove a source file's BOM. The active-content wrapper therefore writes
guest payload text as UTF-8 with BOM and parses the staged script with Windows PowerShell 5.1 before
launching the VM. Preserve this staging check when changing the payload.

**Generalization candidate:** none; the consuming payload owns its encoding and syntax checks.

## Detachment is a security boundary even without an adapter event

**Area:** Avalonia WebView lifecycle
**Status:** Active

With Avalonia.Controls.WebView 12.0.1, removing the control from the visual tree can destroy its native
host without raising `AdapterDestroyed`; the adapter getter can still return the old adapter. Waiting
longer does not supply the missing event. The document navigation gate therefore closes on visual
detachment too, clears queued navigation, and rechecks the current adapter after children attach.
Retained adapters are identified without installing duplicate handlers. The TigerWinLab lifecycle
probe checks held navigation and a protected replacement engine against the production host class.

**Generalization candidate:** none; document navigation safety belongs to this viewer.

## Classifying a filesystem path must not open its remote target

**Area:** Windows image-resource policy
**Status:** Active

`DriveInfo.DriveType` can access an SMB root through a SUBST drive targeting a local symbolic link to
a share: classifying the path opens what the classification was meant to avoid. A lexical
drive-letter test cannot tell such a drive from local storage at all.

`LocalImageStorage` queries the DOS-device mapping without opening its target, then inspects each
immediate reparse target before following it. The sanitizer applies that check before giving absolute
file URLs to Chromium, and the request boundary repeats it at request time. The lab checks local and
remote aliases and links with separate controls.

**Generalization candidate:** none; this is the viewer's resource-loading contract.

## A share reached through a drive letter is a noisy SMB oracle

**Area:** TigerWinLab active-content acceptance
**Status:** Active

Detailed File Share auditing (event 5145) names the file and the account, never the process. Once a
share is mapped to a drive letter or aliased with `subst` in the interactive session, the shell opens
that drive's root, `AutoRun.inf` and `Desktop.ini` on its own: seconds after the mapping, and again at
unpredictable moments later. Several runs reported a root open inside a viewer or `tiger-mark` window
and it was read as a product leak; an isolation run then showed the same root open with a viewer on a
plain document and none with the full share document, and a no-op process reproduced it too.

Keep the strict oracle share free of drive letters, give the mapped-drive fixtures a second share on
which only file opens count, and record time and access mask for every audited access. Do not explain
a root open on a mapped share by a browser mechanism without process-level evidence.

**Generalization candidate:** TigerWinLab, if a generic SMB-access oracle is ever offered.

## Generated HTML has two navigation identities in WebView2

**Area:** Fail-closed viewer notice
**Status:** Active

`NavigateToString` commits an `about:blank` page, but its navigation-start event can carry
`data:text/html;charset=utf-8;base64,...` containing the HTML. Allowing only `about:blank` at that
event cancels the failure notice and can leave the previous document visible.

The unavailable-state exception compares the decoded data URL with the exact host-generated HTML.
Both window navigation handlers use that same check; arbitrary data HTML remains refused. The lab
injects an unsupported adapter and checks the visible notice, refused documents and closed retries.

**Generalization candidate:** none; the exception belongs to the viewer's generated notice.

## A default file association cannot be seeded through the registry

**Area:** TigerWinLab installer acceptance (shell integration)
**Status:** Active

Setting `HKCU\Software\Classes\.md` to another ProgID looks like giving the user a default app, and a
"no takeover" check built on it passed its registry comparison while measuring nothing: Windows 10/11
resolved `.md` to the Open with prompt both before and after, so the seeded value was never an
effective default. A real per-user default is the hash-protected `UserChoice` key, which only
Windows writes.

Creating one the way a person does was tried and does not work from the lab's desktop agent:
`OpenWith.exe` started with `CreateProcess` shows only its interim window ("Open With Dummy Window
Class For Interim Dialog") and the Pick an app flyout never renders there. `AssocQueryString` is not
the double-click answer either: with no `UserChoice` it resolved `.md` to the newly registered handler
while Windows' own resolution still asked. The acceptance therefore asserts what the installer
controls - no extension default and no `UserChoice` written, and uninstall restoring the original
resolution - and records what the user sees: a ShellExecute of a `.md` file (`cmd /c start`, a
double-click's path). For a user who never chose a Markdown app, Windows opens the only recommended
(`OpenWithProgids`) handler directly, so that is TigerMarkView once it is installed. A pre-existing
`UserChoice` wins by Windows' design and is not exercised in the lab.

**Generalization candidate:** TigerWinLab, if a generic "choose a default app" desktop operation is
ever offered.

## An Inno Setup key disappearing is not the end of its uninstall

**Area:** Installer migration from Inno Setup (TigerSetup `[legacy]`)
**Status:** Fixed in TigerSetup 0.13.0; kept for diagnosis

Inno's uninstaller removes its Add/Remove Programs key first and goes on deleting files from a copy of
itself in `%TEMP%`, after the process TigerSetup started has exited. Up to TigerSetup 0.12.0 the
migration waited only for the key, so the old install root still existed when TigerSetup planned the
new installation; TigerSetup then did not own it and left it standing on a later uninstall. The
per-user row failed in five of six runs and the all-users row always failed.

TigerSetup 0.13.0 waits for the legacy uninstaller's whole process tree. An upgrade's install log now
shows `legacy_uninstalled ... processes=2 root_exit_ms=<n> ended_ms=<m>`, with the tree ending about a
second after its root, and the later uninstall log shows `directories_removed=10`. If the acceptance
ever again finds an install root left after uninstall on a migration row, read those two lines before
looking anywhere else; the fix belongs in TigerSetup's migration, not in a TigerMarkView custom action.

**Generalization candidate:** none; TigerSetup owns and has fixed it.

## The Inno Setup migration source is the published 0.8.1, not the local copy

**Area:** TigerWinLab installer acceptance (Inno Setup migration row)
**Status:** Active; prevented by `Test-TigerMarkViewRelease.ps1`

The v0.8.x GitHub Releases no longer serve any asset; they were withdrawn on purpose and are not
restored. Two different files named `TigerMarkView-0.8.1-win-x64-setup.exe` sit under `artifacts\`:
`CDD8978F...` in `artifacts\installer\` is a local build made before publication, and `B81118C9...` is
the published asset, as `artifacts\winget-release\0.8.1\validation\result.json` records from its
download on 2026-08-28. Migrating from the local build would prove an upgrade nobody ever installed.

The script never downloads the migration source. It reads the retained copy at
`artifacts\lab\retained\TigerMarkView-0.8.1-win-x64-setup.exe` (or `-UpgradeFromInstallerPath`) and
refuses any file that does not hash to the recorded
`B81118C96655A7E6E28642A22AE5FC14CBD4EF47F2FA5928A35408833EE4BE9F`. `artifacts\` is ignored, so a new
machine has to be given that copy; any of the `payload\` copies above with that hash will do.

**Generalization candidate:** none; the migration source is this product's history.

## A UNC path in a Markdown link destination loses a backslash

**Area:** TigerWinLab acceptance fixtures (network-share links)
**Status:** Active

In CommonMark `\\` is an escape for one backslash, so `[x](\\server\share\a.md)` links to `\server\share\a.md`, a
root-relative path on the document's own drive, not to the share. A share-link fixture written that way tests a local link
and cost a whole VM run before the cause was seen. Write share links in fixtures as raw HTML anchors
(`<a href="\\server\share\a.md">`), as `shares.md` already does for images, or as `file://server/share/...`, and wait
for the link element to exist before clicking: a window's title is set before its page has rendered.
Read a transient status note (6 s) from `StatusText` by its automation id right after the click: a
search of the whole window by text walks the page's UIA tree too and can finish after the note expired,
which reported a correct refusal as a failure.

**Generalization candidate:** none; fixture spelling is this payload's concern.

## A guest scan that skips what it cannot read proves nothing

**Area:** TigerWinLab active-content acceptance (browsing-history oracle)
**Status:** Active; prevented by the oracle's unreadable count

In Windows PowerShell the comma binds tighter than `-bor`: `New-Object IO.FileStream($path, $mode, $access, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)`
passes a malformed argument list, and every open throws. The history scan caught that per file and moved on, so it reported
no history record because it had read no file at all, and its positive control failed for no visible reason.

Parenthesize the flag expression, and never let a scan oracle skip silently: `Find-EngineMarkers` counts unreadable files,
the product check requires none, and the control must find its record. Prove a guest scan under Windows PowerShell 5.1
against a local folder that does contain the marker before paying for a VM run.

**Generalization candidate:** none; the oracle is this payload's.
