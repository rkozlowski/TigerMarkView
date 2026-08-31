# Preparing the TigerMarkView WinGet package

The community package identifier is `ItTiger.TigerMarkView`. The fork is
`https://github.com/rkozlowski/winget-pkgs`, the upstream repository is
`https://github.com/microsoft/winget-pkgs`, and TigerMarkView uses the dedicated clone
`C:\Projects\winget-pkgs-TigerMarkView\`.

Do not advertise `winget install ItTiger.TigerMarkView` as live until the first pull request is
accepted and the community source returns the package.

This document is the contract, and the automation it describes is implemented. After the human
publishes the GitHub Release, one command does everything that remains except opening the pull
request:

```powershell
.\eng\winget\Prepare-TigerMarkViewWinGetSubmission.ps1 -Version <version>
```

## The authoritative artifact

The WinGet chain is:

```text
release commit -> successful CI -> release workflow -> authoritative CI-built installer
  -> generated + winget-validated + sealed manifests
  -> TigerMarkView-WinGet-<version>-<commit> workflow artifact
  -> draft release -> human publication -> public-byte verification
  -> exact sealed manifests copied to winget-pkgs
```

The files submitted to `winget-pkgs` must be byte-for-byte identical to the three files that the
release workflow generated and validated. Nothing downstream regenerates or edits them.

| Item | Authority and purpose |
| --- | --- |
| `Prepare-TigerMarkViewWinGet.ps1` and `artifacts\winget\` | Local/pre-release generation. It hashes a local installer and is never a release submission set. |
| `TigerMarkView-WinGet-<version>-<commit>` | The authoritative submission artifact. The release workflow generates it from the exact installer it publishes, validates it, seals it, and records its digest. |
| `WinGetReleaseValidation.ps1`, `Test-TigerMarkViewWinGet.ps1`, and `artifacts\winget-release\<version>\` | Post-release retrieval and verification. It must obtain the sealed artifact and never fall back to local generation. The library holds the gate; the script is the command around it. |
| `Prepare-TigerMarkViewWinGetSubmission.ps1` and `WinGetPkgsSubmission.ps1` | End-to-end post-release verification and safe preparation of the pushed fork branch. |

The release workflow's artifact root is the submission directory itself: exactly the version,
default-locale, and installer YAML files. `Assert-TigerMarkViewWinGetSubmission.ps1` proves the file
set, encoding, identity, version, immutable asset URL, installer hash, and combined submission
digest. The publication job downloads and rechecks that sealed set; it does not regenerate it.

Post-release regeneration is verification-only. It writes to throwaway storage, compares all files
byte-for-byte with the sealed set, and can never replace the sealed files. An Inno rebuild is not
expected to be byte-identical to the CI installer.

## The one-command contract

Run it from an elevated PowerShell 7 session at the TigerMarkView repository root, after the release
is published:

```powershell
gh auth status
.\eng\winget\Prepare-TigerMarkViewWinGetSubmission.ps1 -Version <version>
```

When the command ends in `PASS`, the **only** remaining maintainer action is to create and review the
pull request to `microsoft/winget-pkgs`. There is no manual file copy, hash lookup, fork
synchronization, branch creation, `git add`, commit, or push.

`-PlanOnly` runs the read-only gates and prepares nothing; it can report `BLOCKED` or `FAIL` but never
a submission `PASS`. `-ClonePath` overrides only the clone location. `-Refresh` re-downloads the
sealed artifact. `-Json` emits the machine-readable report. There is deliberately no skip switch that
could still produce a `PASS`.

The command orders its work from cheap and fundamental checks to expensive ones and defers mutation
until all practical preflight checks pass:

1. required tools;
2. GitHub CLI authentication and account suitability;
3. TigerMarkView source-repository identity and state;
4. expected release version and commit;
5. successful `CI` run for that exact commit;
6. successful **Release TigerMarkView** run for that version and commit;
7. published, non-draft, publicly accessible release state;
8. sealed artifact availability and GitHub-recorded digest integrity;
9. manifest seal, public installer/hash, byte-for-byte reproduction, and `winget validate`;
10. TigerWinLab install, smoke, wrong-hash rejection, and uninstall validation;
11. dedicated clone, fork, remotes, branch, worktree, operation-state, and previous-PR safety checks;
12. fork synchronization;
13. exact sealed-manifest copy and submission mutation;
14. final diff/status validation, commit, and push; and
15. an explicit human handoff.

Every stage after a human checkpoint verifies that checkpoint. A missing publication, green run for
the wrong commit, expired artifact, wrong account, or unexpected repository is `BLOCKED` or `FAIL`,
not a prompt to guess. Fail before mutation and print what was observed, what the human must do, and
the exact rerun command when useful.

## GitHub authentication and public-release checks

GitHub CLI is a required maintainer tool. The orchestrator must locate `gh`, run `gh auth status`,
identify the authenticated account, and verify it can read the TigerMarkView Actions run and operate
on the expected fork. Use `gh auth login` to establish or repair the session.

No command here requires a maintainer to paste or export a personal access token. None accepts a token
in a command-line argument, logs a token, reads an arbitrary credential store, or falls back to
unrelated credentials; the token-parameter routes that once existed have been removed. Every GitHub
read goes through the shared `gh` adapter in `eng/release-automation/ReleaseAutomation.ps1`, including
the artifact download, which uses `gh api` with the response body written straight to a file. GitHub
Actions uses its scoped `GITHUB_TOKEN`; local orchestration uses the verified GitHub CLI session.

Publication verification must prove all of the following before any `winget-pkgs` mutation:

- `v<version>` resolves to the expected release commit, dereferencing the annotated tag;
- the expected release workflow run for that version and commit concluded `success`;
- the GitHub Release exists and `isDraft` is false;
- its expected installer, `SHA256SUMS.txt`, and `release-artifacts.json` assets exist with no
  unexpected package assets; and
- the release page and immutable installer URL are publicly accessible without authenticated API
  headers.

The downloaded installer must match the hashes and lengths in both verification records and the
sealed manifests. The workflow artifact archive must match the digest GitHub recorded, and the
extracted three-file set must reproduce its recorded seal.

## Dedicated clone lifecycle

The clone path is fixed and project-specific:

```text
C:\Projects\winget-pkgs-TigerMarkView\
```

The general pattern for future Tiger projects is
`C:\Projects\winget-pkgs-<TigerProjectName>\`. A shared or heuristically discovered clone is not an
acceptable substitute.

The path, the fork and upstream slugs, the default branch, and the submission branch prefix are read
from `eng/winget/winget-pkgs.clone.json`. A maintainer may override only the path, with an explicit
`-ClonePath`, because that is a decision rather than a guess; it is still validated identically. The
clone is neither a Lab nor a registered TigerAiCore tool, so it is a configured value here rather
than a discovered one.

If the TigerMarkView path does not exist, the command clones the expected fork into exactly that
path, configures `upstream`, and verifies the resulting repository identity before continuing. An
existing directory is never adopted, emptied, or reconfigured: absence is the only state that is
created.

If it exists, all checks occur before synchronization or other destructive work. The command proves:

- the path is a Git worktree for the expected `winget-pkgs` repository;
- `origin` resolves to `rkozlowski/winget-pkgs` and `upstream` resolves to
  `microsoft/winget-pkgs`, allowing only canonical URL-form differences;
- HEAD is on `master`, or on this version's submission branch, which a previous successful run
  deliberately leaves checked out so its diff can be read;
- the worktree and index are clean, with no untracked submission files that would be overwritten.
  The one exception is this version's own manifest directory: an interrupted run can leave exactly
  those three files behind, and the rerun re-copies and rehashes them before committing anything;
- no merge, rebase, cherry-pick, revert, bisect, or other interrupted Git operation is active; and
- current local and remote branch state is understood before any branch or push operation.

Identity is judged on the URL each remote *declares*, read with `git config --get remote.<name>.url`.
`git remote get-url` returns that value after `url.<base>.insteadOf` rewriting, so both are read and
any difference between them is reported as its own check with the address git would really contact.

Never reuse an ambiguous directory or silently rewrite unexpected remotes. Existing correct state is
reusable; conflicting state is a clear stop.

## Previous-PR safety gate

When the dedicated clone already exists, the latest TigerMarkView WinGet pull request, if any, is a
hard gate before fetch/synchronization or submission mutation. The lookup must be project-specific,
not merely the latest PR opened by the maintainer. Match at least:

- base repository `microsoft/winget-pkgs`;
- fork owner `rkozlowski`;
- head branch prefix `ItTiger-TigerMarkView-`; and
- the most recent pull request matching that identity.

If the latest matching PR is not closed, stop. Open and draft PRs block. Merged PRs are acceptable
because they are closed, and manually closed PRs are also acceptable. The `BLOCKED` result must show
the PR number, URL, state, draft status, and head branch, state that no sync/branch/copy/commit/push
occurred, and tell the human to close or complete that PR before rerunning.

## Fork synchronization and submission mutation

After every preflight and the previous-PR gate passes, fetch both remotes. Synchronization must be
guarded by the identity and clean-state proofs above:

1. verify `upstream/master` and `origin/master` after fetch;
2. fast-forward the fork's `master` to `upstream/master` when safe;
3. stop on unexpected fork-only or divergent commits instead of silently discarding them;
4. push the synchronized `master` to the fork and verify the remote result; and
5. create `ItTiger-TigerMarkView-<version>` from the current `upstream/master`.

The branch name is project-specific. An existing local branch is reused only when it contains current
`upstream/master` and carries at most one commit of its own; anything else is a conflict that stops
the run, and no branch is ever deleted or reset. A remote branch already at the submission commit is
the resumed case and is reported `PASS` without a push; a remote branch at any other commit stops the
run, because overwriting it would need a force push, which this design does not authorize.

Copy the three sealed files unchanged to:

```text
manifests\i\ItTiger\TigerMarkView\<version>\
```

Before commit, rehash the destination files against the sealed source and require the final
`winget-pkgs` diff to contain only the expected package-version directory and exactly the three
manifest files. Re-run manifest validation against the destination, commit with a deterministic
subject such as `New version: ItTiger.TigerMarkView version <version>`, push the release branch, and
verify the remote branch points to the new commit.

The command does **not** create the pull request. It ends loudly:

```text
PASS

READY FOR HUMAN ACTION

Required action:
1. Create and review the microsoft/winget-pkgs pull request from
   rkozlowski:ItTiger-TigerMarkView-<version>.

Then:
<suggested gh pr create command or compare URL>
```

## Idempotency and recovery

The command is safe to rerun after any interruption. A second complete run makes no new commit and no
new push, and ends at the same pull-request handoff:

- retained downloads and extracted artifacts are reused only after their digests are reverified;
- an already-correct clone, remote, synchronized `master`, branch, manifest set, commit, or push is
  recognized and reported as `PASS`;
- a partially prepared branch resumes only when every existing change is exactly what the requested
  version implies;
- conflicting files, commits, branches, remotes, release identities, or repository state cause
  `BLOCKED` or `FAIL` before overwrite; and
- cleanup and repair are explicit and narrowly targeted. The command never silently repairs ambiguous
  state.

The retained sealed set is reused only while its `submission.json` record still binds it to what
GitHub says now: version, tag, release commit, artifact name and id, GitHub's recorded artifact
digest, the retained archive's hash, and the extracted set's submission digest. A rerun after a
re-run release workflow, a moved tag, or an edited manifest therefore fetches the sealed bytes again
rather than trusting the directory. `-Refresh` always re-downloads.

`eng\winget\tests\WinGetPkgsSubmission.Tests.ps1` exercises this against local bare repositories: a
run interrupted after branch creation, after the copy, and after the commit each resume to exactly one
commit and one pushed branch, and a second complete run changes nothing.

## Validating without submitting

The submission command runs the whole post-release gate itself. To run only that gate - to re-check a
published release without touching the clone - use:

```powershell
gh auth status
.\eng\winget\Test-TigerMarkViewWinGet.ps1 -Version <version>
```

The gate downloads `TigerMarkView-WinGet-<version>-<commit>`, verifies the GitHub-recorded artifact
digest, extracts it below `artifacts\winget-release\<version>\submission\`, verifies the published
installer and release records, regenerates into throwaway storage for byte comparison, runs
`winget validate`, and runs TigerWinLab. `-SkipLab` is useful for diagnosis but can never produce a
submission-ready `PASS`.

Both commands run the same function, `Invoke-TigerMarkViewWinGetReleaseValidation` in
`eng\winget\WinGetReleaseValidation.ps1`, and write the same retained result. The submission command
calls it in-process and requires its full result, lab included, before it touches the clone.

TigerWinLab is resolved from the TigerAiCore configuration named by `TigerAiCoreConfig`, or from an
explicit `-TigerWinLabRoot`. A lab that is not registered fails the `lab/location` check with the
reason; the gate never guesses a location, because a `PASS` produced by an unchosen lab would be
worthless. See [release testing in TigerWinLab](tigerwinlab-testing.md).

For artifact-acquisition diagnosis without the public-release and lab gates, the existing lower-level
command is:

```powershell
.\eng\winget\Get-TigerMarkViewWinGetReleaseSubmission.ps1 -Version <version>
```

It does not make a submission ready and must not be used to bypass the complete gate.

All of these use the `gh auth login` session; none takes a token. `-ArchivePath` remains for a machine
that cannot reach the artifact endpoint, and it is verified against the same GitHub-recorded digest,
so it is a different route to the sealed bytes rather than a weaker check.

The retained result includes:

| Path | Purpose |
| --- | --- |
| `submission\` | The authoritative extracted three-file set; never edit it. |
| `submission.json` | Release, commit, workflow artifact, GitHub digest, and submission provenance. |
| `artifact\` | The retained workflow artifact archive. |
| `validation\result.json` and `summary.txt` | Machine-readable and human-readable verdicts. |
| `validation\published\` | Public installer and verification records. |
| `validation\regenerated\` | Throwaway comparison output; never submit it. |
| `validation\tigerwinlab-*` | Lab specification, result, and evidence. |

A `PASS` from `Test-TigerMarkViewWinGet.ps1` proves the sealed files are suitable to submit; it does
not manage the dedicated clone or fork. `Prepare-TigerMarkViewWinGetSubmission.ps1` does that, and it
re-runs this gate rather than trusting an earlier result.

## Manifest shape and validation scope

TigerMarkView uses the WinGet multi-file format at schema 1.12: version, default-locale, and installer
manifests. The Inno installer has user- and machine-scope entries over the same verified x64 asset.
They declare silent switches, install-style upgrade behavior, the stable Inno product code, ARP
identity, the `tiger-mark` command, and dependencies on .NET Desktop Runtime 10 and Microsoft Edge
WebView2 Runtime.

TigerWinLab receives the sealed manifests and downloaded public installer. It validates dependency
setup, local-manifest installation with hash enforcement, installed files, ARP registration, machine
`PATH`, CLI smoke behavior, deliberate wrong-hash refusal, WinGet uninstall, and cleanup in a reset
Windows guest. Nothing is installed on the maintainer host.

Failures involving a missing public release, wrong commit, unsuccessful workflow, expired or
digest-mismatched artifact, release/hash disagreement, non-reproducible manifests, `winget validate`,
or TigerWinLab are blockers. Never rebuild the installer, regenerate the submission set, edit sealed
manifests, or substitute `artifacts\winget\` to make a post-release gate pass.

Tests are isolated: fake GitHub responses and local bare Git repositories, never the real fork,
upstream, releases, credentials, or lab VM. Run them all with one command:

```powershell
pwsh eng/tests/Invoke-EngineeringTests.ps1
```

| Suite | Scope | Covers |
| --- | --- | --- |
| `eng\release-automation\tests\ReleaseAutomation.Tests.ps1` | Repository | Result vocabulary, `gh` preflight, the artifact download route, workflow-run selection, tag dereference, release state, the closed release artifact set, and the scripts the workflows call. |
| `eng\winget\tests\TigerMarkViewWinGet.Tests.ps1` | Repository | Generation, sealing, upload shape, artifact selection by version and commit, digest checking, public-release checks, reproducibility, provenance-bound reuse, and refusal to use stale local output. |
| `eng\winget\tests\WinGetPkgsClone.Tests.ps1` | Maintainer | Clone configuration, slug normalization, interrupted operations, clone identity, and the previous-PR gate. |
| `eng\winget\tests\WinGetPkgsSubmission.Tests.ps1` | Maintainer | Clone creation, fork synchronization, branch create/resume/refuse, exact copy, final diff, commit, push, every interruption boundary, and an idempotent second run. |

The two `Maintainer` suites build real Git repositories and run the submission gates against the
developer's own Git configuration. They belong on the machine that performs a submission, so normal
CI runs only the `Repository` scope and never simulates the local submission state machine.

Authoritative WinGet references are the community repository's
[manifest documentation](https://github.com/microsoft/winget-pkgs/tree/master/doc/manifest),
[schema 1.12 guide](https://github.com/microsoft/winget-pkgs/tree/master/doc/manifest/schema/1.12.0),
and [first contribution checklist](https://github.com/microsoft/winget-pkgs/blob/master/doc/FirstContribution.md).
