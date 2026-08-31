# TigerMarkView release automation: completion record

The minimum-intervention release and WinGet publication workflow this plan scoped is implemented.
Nothing here is outstanding work.

The durable contracts live where they belong:

- the human-facing lifecycle in [Releasing TigerMarkView](releasing-tigermarkview.md);
- the artifact, clone, and submission rules in
  [Preparing the TigerMarkView WinGet package](winget-tigermarkview.md); and
- the engineering constraints in `AGENTS.md`.

This file remains only as the record of what was built and why a few decisions went the way they did.
It is not a source of requirements: if it ever disagrees with the two guides or `AGENTS.md`, they win.

## What was built

| Area | Implementation | Tests |
| --- | --- | --- |
| Result vocabulary and GitHub queries | `eng/release-automation/ReleaseAutomation.ps1` - `PASS`/`WARN`/`BLOCKED`/`FAIL`/`READY FOR HUMAN ACTION` objects with one text/Markdown/JSON renderer, fixed repository constants, an injectable `gh`-only adapter (reads and binary downloads), session preflight, exact-SHA run selection, annotated-tag dereference, release-state inspection | `eng/release-automation/tests/ReleaseAutomation.Tests.ps1` |
| Release workflow prerequisite gate | `Assert-ReleaseCommitReady.ps1` and the `prerequisites` job (`actions: read` + `contents: read`), which `validate` needs | workflow static assertions |
| Version-specific release notes | `.github/release-notes/`, `Assert-ReleaseNotes.ps1`, `Publish-GitHubDraftRelease.ps1 -NotesFile`, and the `always()` publication checklist | `ReleaseAutomation.Tests.ps1` |
| Release preparation | `Set-TigerMarkViewReleaseVersion.ps1`, `Test-TigerMarkViewReleaseReadiness.ps1` | `eng/release-automation/tests/ReleasePreparation.Tests.ps1` |
| Post-release validation | `eng/winget/WinGetReleaseValidation.ps1` (the gate as a callable function), `Test-TigerMarkViewWinGet.ps1` (the command around it), provenance-bound reuse of a retained sealed set | `eng/winget/tests/TigerMarkViewWinGet.Tests.ps1` |
| Read-only fork safety | `eng/winget/winget-pkgs.clone.json`, `eng/winget/WinGetPkgsClone.ps1` | `eng/winget/tests/WinGetPkgsClone.Tests.ps1` |
| Guarded submission mutation | `eng/winget/WinGetPkgsSubmission.ps1`, `eng/winget/Prepare-TigerMarkViewWinGetSubmission.ps1` | `eng/winget/tests/WinGetPkgsSubmission.Tests.ps1` |

The two human decisions the plan protected are still human: publishing the GitHub Release, and
creating the `microsoft/winget-pkgs` pull request.

## Decisions worth keeping

**The gate is a function, not a script exit code.** `Invoke-TigerMarkViewWinGetReleaseValidation`
returns a structured result and never exits. The submission orchestrator requires that full result -
lab included - in-process, so a `PASS` it acts on is the same object a maintainer reads.

**Downloads needed their own route through `gh`.** A workflow artifact is a zip, and piping a native
command's output through PowerShell decodes it as text. `New-TigerMarkViewGitHubCli` therefore has
`downloadApi`, which copies the process's stdout stream straight to a file. It is injectable, so tests
exercise it without a network, and it keeps the single no-token authentication contract.

**Reuse is bound to provenance, not to a directory's existence.** A retained sealed set is reused only
while version, tag, release commit, artifact name and id, GitHub's recorded artifact digest, the
archive's hash, and the extracted submission digest all still agree. A re-run release workflow or an
edited manifest is a cache miss, not a shortcut.

**Clone identity is judged on the declared remote URL.** `git remote get-url` returns the URL *after*
`url.<base>.insteadOf` rewriting, so reading only it would let a machine-level redirect masquerade as
the real fork - and reading only `git config --get remote.<name>.url` would hide where git actually
goes. Both are read: identity is judged on the declared value, and any difference is its own check
naming the address git would contact.

**Only the version directory may be dirty.** An interrupted run leaves exactly the three manifests in
the worktree, and the rerun re-copies and rehashes them before committing, so tolerating them is what
makes resumption possible. Everything outside that directory must still be clean, and the standalone
read-only gate tolerates nothing.

**No force operation was ever needed.** Fork-only commits, a branch based on something other than
current `upstream/master`, and a remote branch at a different commit each stop the run with evidence.
The plan said a force operation would need its own design and additional guards; none was required, so
none exists.

## Open architect question

Whether the dedicated `winget-pkgs` clone should become a registered TigerAiCore resource is still
undecided. Until it is, its location stays an explicit configured value in
`eng/winget/winget-pkgs.clone.json`, overridable only with `-ClonePath`, never discovered.
