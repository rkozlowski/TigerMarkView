# Releasing TigerMarkView

This is the human-facing lifecycle for the Windows GUI and `tiger-mark`. TigerMarkView is the
reference release model for future Tiger application projects. The human decides when a release
moves forward; automation performs repeatable preparation, verification, packaging, and submission
work.

> **Transition status:** the authoritative installer and sealed WinGet artifact, the release
> workflow's exact-commit CI-success gate, the checked-in version-specific release notes, and the
> deterministic preparation/readiness helpers now exist. Still to be built: the one-command
> `winget-pkgs` fork/branch/commit/push orchestrator (`Prepare-TigerMarkViewWinGetSubmission.ps1`)
> and the migration of `Test-TigerMarkViewWinGet.ps1` off its raw-token client. Until then, use the
> [current transition procedure](#current-transition-procedure) for the post-release WinGet steps and
> do not treat that proposed command as available. Remaining work is tracked in
> [the release automation plan](release-automation-implementation-plan.md).

TigerMarkView publishes one installer containing the GUI and CLI, plus `SHA256SUMS.txt` and
`release-artifacts.json`. It does not publish NuGet packages, a portable archive, or a separate CLI
installer. `Version.props` remains the only product-version and shared-metadata source.

## Maintainer tools and authentication

The finished workflow requires:

- `git`, PowerShell 7 (`pwsh`), the .NET 10 SDK, and `winget`;
- GitHub CLI (`gh`), authenticated to an account allowed to operate on
  `rkozlowski/TigerMarkView` and the `rkozlowski/winget-pkgs` fork;
- Inno Setup 6 or 7 and the Edge WebView2 Runtime for local release preparation; and
- a provisioned TigerWinLab, registered as `[labs.TigerWinLab]` in the TigerAiCore configuration named
  by `TigerAiCoreConfig`, for installer, desktop, and WinGet scenarios.

Authenticate locally with GitHub CLI and verify the active account before release work:

```powershell
gh auth login
gh auth status
```

Maintainers must not routinely paste or export personal access tokens. Never put a token in a
repository file or command-line argument, log a token, inspect arbitrary Git credential stores, or
fall back to unrelated credentials. GitHub Actions must use the provided `GITHUB_TOKEN`, with
permissions declared per job and limited to the operations that job performs. Publishing the draft
release and creating the final `microsoft/winget-pkgs` pull request remain human actions.

TigerMarkView releases are currently unsigned. Do not add signing switches unless a real signing
identity and secret-delivery design has been approved. Certificate paths, PFX files, and passwords do
not belong in this repository.

## Release chain and decision points

The authoritative chain is:

```text
release commit
  -> successful CI for that exact commit
  -> manually dispatched release workflow for that exact commit
  -> one authoritative CI-built installer
  -> generated, validated, and sealed WinGet manifests from that installer
  -> draft GitHub Release
  -> human publication
  -> verification of the public release
  -> prepared and pushed winget-pkgs submission branch
  -> human-created microsoft/winget-pkgs pull request
```

Local installers and locally generated manifests are preparation aids only. They are never
authoritative release or WinGet submission artifacts.

### Required verification after human actions

Every automated stage that follows a required human action must prove the action occurred before it
mutates anything. It must never infer success from elapsed time or nearby state. In particular:

- after commit and push, resolve the intended release commit and prove it is reachable from the
  expected `origin/main`;
- before dispatch or release mutation, prove CI succeeded for that exact commit;
- after the release workflow, prove the expected workflow run for that version and commit completed
  successfully;
- after publication, prove the release exists, is not a draft, has the expected tag and assets, and
  is publicly accessible without maintainer credentials; and
- before GitHub or `winget-pkgs` operations, prove tool availability, `gh auth status`, account and
  repository identity, remotes, worktree safety, and previous-PR state.

If a prerequisite is absent or ambiguous, stop before mutation. Print `BLOCKED` or `FAIL`, describe
the observed state, state the exact human action required, and include the command to rerun where it
helps.

All scripts, workflows, and agent tasks must use a consistent vocabulary: `PASS`, `WARN`, `BLOCKED`,
`FAIL`, and `READY FOR HUMAN ACTION`. A stage that intentionally stops for a human decision must end
with an unmistakable handoff, for example:

```text
READY FOR HUMAN ACTION

Required action:
1. Review the prepared release changes.
2. Commit them and push main.

Then:
Wait for CI on <commit> to pass, then manually run Release TigerMarkView for <version>.
```

`WARN` identifies a condition the human must read but which does not invalidate the result.
`BLOCKED` means a required external or human checkpoint is incomplete. `FAIL` means a check ran and
found invalid state.

## Target maintainer workflow

### 1. Ask an agent to prepare the release

A normal request is intentionally short:

```text
Prepare release 0.9.0 of TigerMarkView
```

Following this document, the agent runs the deterministic helper, writes the judgment-based content,
runs the gates, and leaves only intentional reviewable changes. It does not commit, push, dispatch a
workflow, tag, or publish.

```powershell
# 1. Deterministic: Version.props + the release-workflow dispatch default only.
pwsh eng/release-automation/Set-TigerMarkViewReleaseVersion.ps1 -Version <version>

# 2. Judgment: write .github/release-notes/<version>.md from TEMPLATE.md, and update any
#    changed public documentation (README.md, docs/HELP.md).

# 3. Read-only readiness report, ending in the review/commit/push handoff.
#    Add -Full (or -IncludeBuild/-IncludeInstaller/-IncludeLab) to run the expensive gates.
pwsh eng/release-automation/Test-TigerMarkViewReleaseReadiness.ps1 -Version <version> -Full
```

`Set-TigerMarkViewReleaseVersion.ps1` refuses if a shipped `src/` or `installer/` file hardcodes the
version, and supports `-WhatIf`. `Test-TigerMarkViewReleaseReadiness.ps1` verifies tools,
source-repository identity and branch, the `Version.props` / workflow-default / no-hardcoded-version
invariants, the release-notes source, and the diff shape; the expensive build, installer, and
TigerWinLab gates are opt-in and reported `NOT RUN` when skipped. It never commits or pushes.

The preparation stage ends with `READY FOR HUMAN ACTION`, a change summary, test results, and exact
review/commit/push instructions.

### 2. Review, commit, and push

The human reviews the diff, commits the complete release preparation, and pushes it to `main`. This
is a decision checkpoint, not work the preparation agent silently performs.

CI starts on the push. Any later helper must verify both that the expected commit is on
`origin/main` and that the `CI` workflow for that commit concluded `success`. A run for a different
commit, a merely completed run, or a green pull-request run is not sufficient.

### 3. Manually dispatch the release workflow

After CI is green, the human manually starts **Release TigerMarkView** on `main`, using the exact
version in `Version.props`. Before building or creating GitHub state, the workflow must verify:

- its dispatched SHA is the expected release commit on `origin/main`;
- the version input exactly matches `Version.props`;
- the required `CI` run for that SHA succeeded;
- the release tag is available; and
- its checkout and tracked release inputs are clean and complete.

The release workflow then builds once and uses those exact outputs throughout. It:

1. restores, builds with warnings as errors, and tests;
2. publishes GUI and CLI without rebuilding;
3. builds and validates the authoritative installer;
4. writes and verifies its hash, length, version, and commit records;
5. generates WinGet manifests from that exact installer and immutable release URL;
6. runs `winget validate` and seals the exact three-file submission set;
7. uploads `TigerMarkView-WinGet-<version>-<commit>` and records its digest;
8. transfers and reverifies the release and WinGet artifacts without rebuilding or regenerating;
9. creates annotated tag `v<version>` at the validated commit; and
10. creates a draft GitHub Release with the installer, verification records, and useful prepared
    release notes.

The workflow must end with `READY FOR HUMAN ACTION`, identify the draft URL, version, tag, commit,
artifact and digests, and list the exact publication review. It never publishes the release and
never creates the final WinGet pull request.

### 4. Review and publish the draft

The human verifies the tag and commit, the three expected assets, the recorded hashes, and the
release notes, then explicitly publishes the draft. The release notes must be a useful user-facing
summary. GitHub `--generate-notes` produced only a **Full Changelog** link for 0.8.1, so generic
generated notes alone are not an acceptable finished implementation. Until signing is introduced,
the notes must also state the runtime prerequisites and current unsigned status.

### 5. Prepare the WinGet submission branch

After publication, the human runs one command from an elevated PowerShell 7 session at the
TigerMarkView repository root. The provisional interface is:

```powershell
.\eng\winget\Prepare-TigerMarkViewWinGetSubmission.ps1 -Version <version>
```

The command first verifies that the expected release workflow completed successfully and that the
release is public, non-draft, and byte-consistent. It retrieves and verifies the sealed workflow
artifact, performs throwaway byte-for-byte regeneration, runs `winget validate` and TigerWinLab,
manages the dedicated `C:\Projects\winget-pkgs-TigerMarkView\` clone, enforces the previous-PR safety
gate, synchronizes the fork, creates the release branch, copies the exact sealed manifests, validates
the final diff, commits, and pushes.

When it ends in `PASS`, its final handoff must say that the **only** remaining action is to create and
review the `microsoft/winget-pkgs` pull request, and provide the branch and suggested PR command or
URL. See [Preparing the TigerMarkView WinGet package](winget-tigermarkview.md) for the authoritative
artifact and clone rules.

## Current transition procedure

Preparation, the CI-success gate, and the release notes are automated (see
[step 1](#1-ask-an-agent-to-prepare-the-release)). Only the post-release WinGet submission still has
manual steps, below. These are current-state instructions, not the target human experience.

1. Prepare with the helpers, write `.github/release-notes/<version>.md`, and run readiness:

   ```powershell
   pwsh eng/release-automation/Set-TigerMarkViewReleaseVersion.ps1 -Version <version>
   # write .github/release-notes/<version>.md, update README.md / docs/HELP.md as needed
   pwsh eng/release-automation/Test-TigerMarkViewReleaseReadiness.ps1 -Version <version> -Full
   ```

2. Review, commit, and push. The release workflow's `prerequisites` job now proves the pushed commit
   is on `origin/main` and that its exact `CI` push run concluded `success` before it builds or tags
   anything, so wait for that `CI` run, then manually dispatch **Release TigerMarkView** from `main`.
3. Review the workflow result and draft. The draft notes come from the checked-in
   `.github/release-notes/<version>.md`; edit on GitHub if needed, then publish manually.
4. Run the existing post-release gate:

   ```powershell
   .\eng\winget\Test-TigerMarkViewWinGet.ps1 -Version <version>
   ```

   Prefer `gh auth login`; existing compatibility token parameters do not define the finished
   authentication contract. A `PASS` currently validates and retains the sealed manifests but does
   not manage the fork, branch, commit, or push. Follow the interim submission instructions in the
   WinGet maintainer document with exceptional care.

For an upgrade release, also run the lab gate with `-UpgradeFromInstallerPath` and
`-UpgradeFromVersion` as documented in [TigerWinLab testing](tigerwinlab-testing.md).

## Recovery principles

- Reruns must recognize already-correct state and continue safely where possible.
- Conflicting tags, releases, assets, branches, files, remotes, or commits cause a clear stop; never
  overwrite or silently repair ambiguous state.
- Before a tag exists, fix the cause in a new release commit, push it, wait for that commit's CI, and
  dispatch that commit. Never reuse validation artifacts from another commit.
- Never move an existing release tag. If it identifies different bytes or a different commit,
  resolve the release identity explicitly and use a new version when necessary.
- Recovery after partial draft creation must use the retained validated artifact and the compatible
  draft-only behavior of `eng/release-automation/Publish-GitHubDraftRelease.ps1`; it must not rebuild.
  First inspect the plan against the retained artifact, version, and validated SHA:

  ```powershell
  pwsh eng/release-automation/Publish-GitHubDraftRelease.ps1 `
    -ArtifactDirectory <retained-artifact-directory> `
    -Version <version> `
    -CommitSha <validated-sha> `
    -PlanOnly
  ```

  If the plan proves the existing tag/draft/assets are compatible, rerun without `-PlanOnly`. Use
  `-AllowDifferentHeadForRecovery` only when a necessary helper fix is on a later checkout; the
  retained manifest and tag must still identify the original validated SHA.
- Never replace a public release asset merely to make a manifest pass.
- Workflow artifacts currently expire after 30 days. Preserve the validated release artifact,
  sealed WinGet artifact, digests, and run logs immediately when recovery is needed.
