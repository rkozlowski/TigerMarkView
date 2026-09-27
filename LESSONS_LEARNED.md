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
