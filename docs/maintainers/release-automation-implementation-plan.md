# TigerMarkView release automation implementation plan

## Objective

Build the minimum-intervention release and WinGet publication workflow described in
[Releasing TigerMarkView](releasing-tigermarkview.md) and
[Preparing the TigerMarkView WinGet package](winget-tigermarkview.md). A maintainer makes the release
decisions; automation performs deterministic preparation, verification, artifact handling, and Git
work. The completed TigerMarkView implementation becomes the reference for future Tiger projects.

This is a current implementation plan. Remove or substantially reduce it when the work is complete;
the durable contracts belong in the two maintainer guides and `AGENTS.md`.

## Implementation status (updated 2026-08-30)

Landed: phases 1-4 and the read-only half of phase 6.

- `eng/release-automation/ReleaseAutomation.ps1` - shared `PASS`/`WARN`/`BLOCKED`/`FAIL`/
  `READY FOR HUMAN ACTION` result objects, one renderer for text/Markdown/JSON, the fixed
  repository/workflow/asset constants, an injectable `gh`-only CLI adapter (no token inputs), the
  `gh` session preflight, exact-SHA workflow-run selection, annotated-tag dereference, and published
  release-state inspection. Tests: `eng/release-automation/tests/ReleaseAutomation.Tests.ps1`.
- `.github/workflows/release.yml` gained a first `prerequisites` job (`actions: read` + `contents:
  read` only) running `eng/release-automation/Assert-ReleaseCommitReady.ps1`, which proves the
  dispatched commit is on `origin/main` and its exact `CI` push run concluded `success`, that the
  dispatched version matches `Version.props`, and that the notes source is ready. `validate` now
  `needs: prerequisites`. A final `always()` step writes the `READY FOR HUMAN ACTION` publication
  checklist to the workflow summary.
- Checked-in release notes: `.github/release-notes/<version>.md` (`TEMPLATE.md`, `README.md`, and a
  backfilled `0.8.1.md`). `eng/release-automation/Assert-ReleaseNotes.ps1` +
  `Test-TigerMarkViewReleaseNotes` reject a missing file, placeholder text, a bare Full-Changelog
  link, or a leaked secret/local path. `Publish-GitHubDraftRelease.ps1` now takes `-NotesFile` and
  uses `gh release create --notes-file`; the workflow passes
  `.github/release-notes/<version>.md`.
- Preparation helpers: `eng/release-automation/Set-TigerMarkViewReleaseVersion.ps1` (updates only
  `Version.props` and the workflow dispatch default, `-WhatIf` aware, refuses when a shipped
  `src/`/`installer/` file hardcodes the version) and
  `eng/release-automation/Test-TigerMarkViewReleaseReadiness.ps1` (read-only report; expensive
  build/installer/lab gates are opt-in and reported `NOT RUN` when skipped). Tests:
  `eng/release-automation/tests/ReleasePreparation.Tests.ps1`.
- Read-only winget-pkgs clone safety: `eng/winget/winget-pkgs.clone.json` (narrowly scoped config)
  and `eng/winget/WinGetPkgsClone.ps1` - config load/validation, canonical GitHub-slug comparison,
  interrupted-operation detection, full clone-identity checks, and the project-specific previous-PR
  gate. Tests: `eng/winget/tests/WinGetPkgsClone.Tests.ps1` (local bare repos + fake `gh`).

Still to do: phase 5 (refactor `Test-TigerMarkViewWinGet.ps1` onto the shared `gh` adapter and
provenance-bound caching; remove the raw-token compatibility routes), phase 7 (the guarded
`Prepare-TigerMarkViewWinGetSubmission.ps1` mutation orchestrator: fork sync, branch/copy/diff/commit/
push, remote verification), and phase 8 (end-to-end interruption/rerun hardening and the final
documentation pass).

## Current behavior

- Release preparation now has deterministic helpers and a readiness report, but the maintainer still
  performs the judgment-based notes/documentation edits and the commit/push.
- The release workflow verifies its dispatched commit is on `origin/main` and that the exact `CI`
  push run for that commit succeeded before it builds or tags anything.
- `.github/workflows/release.yml` builds once, validates the installer, hashes the closed release
  set, generates and validates manifests from that exact installer, seals and uploads the WinGet
  set, reverifies transferred bytes, tags the commit, and creates a draft release with the
  checked-in version-specific notes.
- `Test-TigerMarkViewWinGet.ps1` verifies the published release, retrieves the commit-bound sealed
  artifact, checks GitHub's artifact digest, performs throwaway regeneration, runs `winget validate`,
  and invokes TigerWinLab. It still carries its own REST/token client rather than the shared `gh`
  adapter (phase 5).
- The post-release process has read-only clone identity and previous-PR gates but still stops before
  fork synchronization, exact manifest copy, final diff checks, commit, and push (phase 7).
- Existing lower-level WinGet acquisition still accepts raw-token compatibility inputs. The new
  maintainer-facing contract must use a verified GitHub CLI session and must not expose tokens; the
  new `eng/release-automation` and `eng/winget/WinGetPkgsClone.ps1` code already does.

## Target workflow and ownership

| Stage | Automation responsibility | Human responsibility |
| --- | --- | --- |
| Prepare | Update deterministic version locations, verify prerequisites and repository state, guide release-note/document updates, run local gates, report exact diff/results | Request a version, review judgment-based content and all changes |
| Commit/push | No implicit mutation; later stages verify the expected commit is on `origin/main` | Commit and push intentionally |
| CI | Run automatically for the pushed commit | Wait; decide whether failures are release blockers |
| Release dispatch | Verify pushed commit and successful CI before mutation | Manually dispatch the release workflow |
| Build/draft | Build authoritative bytes once, generate/seal manifests, tag, create draft with useful notes, report hashes and review checklist | Review draft, notes, tag, and assets; publish explicitly |
| Post-release | Verify publication and provenance, validate sealed files and public installer, test in TigerWinLab, prepare/commit/push fork branch | Run one command after publication |
| WinGet PR | Provide exact pushed branch and PR command/URL | Create and review the `microsoft/winget-pkgs` PR |

No automated stage may cross either publication decision: publishing the GitHub Release and creating
the final WinGet PR remain human-only.

## Verification and handoff model

Implement shared result semantics for scripts and workflow summaries:

- `PASS`: a check or stage completed and its invariant is proven;
- `WARN`: notable, non-blocking state that must be shown in the final summary;
- `BLOCKED`: a required human/external checkpoint is incomplete or state is unsafe to mutate;
- `FAIL`: a completed check found invalid data or an operation failed; and
- `READY FOR HUMAN ACTION`: automation intentionally stopped at a decision boundary.

Each result should include a stable check ID, observed state, expected state, evidence/provenance, and
remediation. Script exit codes should distinguish success from blocked/failed if practical; define
the mapping once and test it. Human-readable output and machine-readable JSON must be derived from the
same result objects.

Before every post-human mutation, verify the prior action explicitly:

1. Resolve local `HEAD`, `origin/main`, the requested version, and expected release commit.
2. Query the `CI` workflow by exact SHA and require `status=completed` and `conclusion=success` for
   the push on `main`.
3. Query **Release TigerMarkView** by exact SHA/version and require success before consuming its
   artifacts.
4. Query the release and require the expected tag, commit, `isDraft=false`, assets, and public URLs.
5. Verify `gh auth status`, authenticated identity/capability, clone identity, remotes, operation
   state, cleanliness, branch state, and previous PR before fork mutation.

On `BLOCKED` or `FAIL`, stop before mutation and end with the exact corrective action and rerun
command. On a decision boundary, print numbered required actions and the exact next command or GitHub
UI action. Do not end with a bare “ready”.

## Tooling and authentication

Required local tools are `git`, `gh`, `pwsh`, `winget`, `dotnet`, TigerWinLab, and Inno Setup where
local installer preparation needs it. Continue to require WebView2 for local PDF/installer checks.

TigerWinLab and any other shared Tiger resource are resolved through `eng/TigerAiCore.ps1` from the
TigerAiCore configuration named by `TigerAiCoreConfig`. New scripts must use it rather than adding a
second discovery route, must report the resolved path and its source in structured results, and must
report an unregistered resource as `NOT RUN` with the reason instead of guessing a location.

The maintainer-facing scripts must:

- resolve each required executable and report its path/version where useful;
- run `gh auth status`, resolve the viewer identity, and prove the account can read Actions and push
  `rkozlowski/winget-pkgs` before mutation;
- direct authentication repair to `gh auth login`;
- never accept a token parameter, place tokens on command lines, log tokens, inspect generic Git
  credential stores, or search fallback credentials; and
- use `gh api`/other `gh` commands through the authenticated session for GitHub operations.

Tests should inject a fake `gh` executable or command adapter; they must not need live credentials.
Lower-level raw-token compatibility can be removed or made internal after callers and tests migrate.

In Actions, use `${{ github.token }}` only through environment delivery. Add `actions: read` to the
release validation job for CI-run verification and retain `contents: read`; keep `contents: write`
only on the draft-publication job. Do not give workflow-wide write permissions.

## Authoritative artifacts and release notes

Preserve the existing build-once chain. The release commit and successful CI select the release
workflow run; that run creates one installer and one sealed manifest set. Record and carry version,
commit, run ID/attempt, release artifact-manifest digest, installer digest/length, WinGet artifact ID
and GitHub digest, and submission digest through every stage.

Post-release retrieval must select the artifact by version **and** tag commit, not by recency. Public
installer verification must be unauthenticated. Regeneration goes to a fresh throwaway directory and
is comparison-only. No recovery path may replace the sealed set with regenerated files.

Replace generic-only release notes with a deliberate, checked-in notes source. Proposed design:

- release preparation creates `.github/release-notes/<version>.md`;
- define a short template: user-visible changes, fixes, prerequisites/known limitations, and optional
  contributor/change links;
- readiness validation requires the exact version file, meaningful non-placeholder content, and no
  secrets or local paths;
- the workflow carries that file from the validated release commit and
  `Publish-GitHubDraftRelease.ps1` uses `gh release create --notes-file` instead of relying solely on
  `--generate-notes`; and
- the draft remains editable and human publication remains mandatory.

Confirm the final notes path and template during implementation. The acceptance requirement is useful
version-specific content; a Full Changelog link alone is insufficient.

## Proposed scripts and interfaces

Prefer small assertion/planning helpers plus one orchestrator per human-facing phase. Reuse and
extend existing `eng/release-automation` and `eng/winget` functions instead of creating a second
artifact or manifest model.

### Release preparation

- `eng/release-automation/Set-TigerMarkViewReleaseVersion.ps1 -Version <version>`: update only
  `Version.props` and the manual workflow input default; reject any unexpected extra literal-version
  location.
- `eng/release-automation/Test-TigerMarkViewReleaseReadiness.ps1 -Version <version> [-Json]`: verify
  tools, source repository/remotes/branch, intended diff, release-note source, build/test/installer
  checks, local WinGet preparation, and TigerWinLab result. It must never commit or push.
- Agent instructions in the maintainer guide: perform judgment-based documentation/release-note
  edits, call deterministic helpers, and emit the standard review/commit/push handoff.

Whether the two helpers become one script is an implementation detail; keep mutation narrow and
make `-WhatIf`/plan output available for any file update.

### Shared GitHub state

- Add shared functions under `eng/release-automation` (or extend the existing WinGet helper without
  creating circular ownership) for `gh` preflight, exact-SHA workflow selection, tag dereference,
  draft/public release inspection, asset shape, and public accessibility.
- Return structured objects. Do not scrape colorized human output when `gh --json` or `gh api` can
  return stable fields.
- Define repository constants once: `rkozlowski/TigerMarkView`, workflow files/names, expected
  branch, and release asset names.

### Post-release WinGet

- `eng/winget/Prepare-TigerMarkViewWinGetSubmission.ps1 -Version <version> [-Json]`: the only
  maintainer-facing command. It orchestrates all checks, TigerWinLab, clone/fork work, commit, push,
  and the final handoff. Do not expose skip switches that could still produce `PASS`.
- Keep `Test-TigerMarkViewWinGet.ps1` as the artifact/public/lab validator, but make its structured
  result callable without terminating the parent process. The orchestrator must require the full lab
  result.
- Add isolated clone helpers for repository identity, interrupted-operation detection, previous-PR
  lookup, safe synchronization, branch/resume analysis, exact copy, final diff, deterministic commit,
  push, and remote verification.

The orchestrator may offer `-PlanOnly` for read-only diagnosis, but `PlanOnly` cannot claim
submission `PASS` or `READY FOR HUMAN ACTION` to open the PR.

## winget-pkgs clone, PR gate, and synchronization

Take the project-specific clone destination from a narrowly scoped configuration value, currently
documented as `C:\Projects\winget-pkgs-TigerMarkView\`. The clone is neither a Lab nor a registered
shared tool, so TigerAiCore discovery does not yet cover it; whether it becomes a registered resource
is an open Architect decision. Until it is decided, the destination must be an explicit configured
value rather than a discovered one. If absent, clone only
`rkozlowski/winget-pkgs`, add/verify `microsoft/winget-pkgs` as `upstream`, and verify repository
identity. If present, reject non-Git, wrong origin/upstream, non-`master` default, dirty/unsafe, or
interrupted-operation state.

Before changing an existing clone, query pull requests in `microsoft/winget-pkgs` and select the most
recent one whose head owner is `rkozlowski` and head branch starts
`ItTiger-TigerMarkView-`. Open or draft blocks; merged or manually closed passes. Include number, URL,
state, draft flag, and branch in evidence. Do not use “latest PR by user”.

After all practical checks and expensive validation pass:

1. fetch `upstream` and `origin`;
2. verify fetched repository/branch identities;
3. fast-forward local/fork `master` to `upstream/master` and verify the pushed fork state;
4. block on fork-only/divergent commits rather than forcing ambiguous history;
5. create `ItTiger-TigerMarkView-<version>` from current `upstream/master`;
6. copy only the exact sealed files into
   `manifests/i/ItTiger/TigerMarkView/<version>/`;
7. verify destination hashes, exact three-file shape, `winget validate`, and a path-limited diff;
8. commit `New version: ItTiger.TigerMarkView version <version>`;
9. push and verify the remote branch SHA; and
10. print the PR handoff without opening the PR.

Never reset, force-push, delete, overwrite, or rewrite a remote until the exact repository and target
are proven. Prefer fast-forward operations. If a force operation is ever found necessary, it needs a
separate explicit design and additional guards; it is not authorized by this plan.

## Idempotency and recovery

Model each operation as `absent`, `already correct`, or `conflicting`:

- `absent`: create after prerequisites pass;
- `already correct`: verify and reuse, reporting `PASS`; and
- `conflicting`: stop with evidence and explicit recovery, never silently repair.

Persist a post-release result record binding version, release/tag commit, CI run, release run,
artifact IDs/digests, installer digest, submission digest, validation tool versions, and TigerWinLab
result. Reuse expensive work only when all bindings still match. Use temporary directories followed
by verified atomic promotion for downloads/extraction where feasible.

Test reruns at boundaries: after download, extraction, validation, clone, fork sync, branch creation,
copy, commit, and push. A second complete invocation must perform no new commit/push and must still
end with the correct human handoff. A mismatch at any boundary must stop without destroying evidence.

## GitHub Actions changes

1. Add a first release-validation step/job that verifies the dispatched SHA is on `origin/main` and
   its exact `CI` push run concluded `success`. Give only that job `actions: read` and `contents: read`.
2. Preserve current build-once, transfer-digest, sealed-manifest, annotated-tag, draft-only, and
   minimal-permission behavior.
3. Add and validate the checked-in version-specific release-notes source; carry it with the
   authoritative release inputs and pass it to draft creation.
4. Extend the workflow summary with `PASS` checks and `READY FOR HUMAN ACTION`, including draft URL,
   tag/commit, asset names/digests, WinGet artifact ID/name/digest, and publication checklist.
5. Ensure failed prerequisites report `BLOCKED`/`FAIL` before tag or release mutation. Account for a
   rerun/partial-draft recovery path without moving a tag or overwriting different assets.
6. Keep artifact retention explicit. Decide during implementation whether 30 days is sufficient for
   the expected human publication/WinGet window; if retained, handoffs must state the expiry risk.

## Tests required

Use fake GitHub responses and temporary local/bare Git repositories. No test should access the real
fork, upstream, releases, credentials, or TigerWinLab VM.

- Version preparation: valid/invalid versions, only approved files changed, workflow default matches,
  idempotent rerun, and unexpected literal-version detection.
- `gh` preflight: missing CLI, unauthenticated, wrong/insufficient account, expected authenticated
  account, and no token output.
- Workflow gates: no run, queued/in-progress, failed/cancelled, wrong event/branch/SHA, duplicate runs,
  rerun attempts, and exact successful push/release run selection.
- Release state: missing, draft, published, wrong tag/commit, missing/unexpected asset, private-only
  accessibility, public success, and verification-record mismatch.
- Release notes: missing, placeholder/Full-Changelog-only, valid useful notes, and exact file passed to
  draft creation.
- Artifact chain: missing/expired, wrong commit, wrong GitHub digest, unsafe archive paths, wrong
  three-file shape, seal mismatch, public installer mismatch, and throwaway reproduction mismatch.
- Clone identity: absent clone, wrong directory content, wrong origin/upstream/default branch, URL
  normalization, dirty/untracked state, and every interrupted Git operation.
- Previous PR: none; latest matching merged, manually closed, open, and draft; unrelated newer Tiger
  project PR; wrong owner/prefix/base; and clear blocking evidence.
- Synchronization: fast-forward, already synchronized, fork ahead/diverged, fetch/push failure, and
  remote verification mismatch.
- Submission: absent/already-identical/conflicting branch and files, exact destination/hash/diff,
  deterministic commit, interrupted commit/push, already-pushed resume, and refusal to touch unrelated
  changes.
- End-to-end fake run: every interruption boundary and a fully idempotent second invocation whose only
  remaining action is PR creation.
- Workflow/static tests: minimal permissions, CI gate precedes mutation, release notes source, exact
  sealed directory upload, no regeneration after seal, draft-only behavior, and explicit handoff.

Keep the existing WinGet tests passing and extend their fake-GitHub model rather than introducing
live network dependence.

## Implementation phases

1. **Result and GitHub-query foundation** - *done.* `ReleaseAutomation.ps1` + tests.
2. **Release workflow prerequisite gate** - *done.* `Assert-ReleaseCommitReady.ps1`, the
   `prerequisites` job with `actions: read` + `contents: read`, `validate` `needs: prerequisites`.
3. **Release notes and workflow handoff** - *done.* `.github/release-notes/`,
   `Assert-ReleaseNotes.ps1`, `Publish-GitHubDraftRelease.ps1 -NotesFile`, and the `always()`
   publication-checklist summary step.
4. **Release preparation helpers** - *done.* `Set-TigerMarkViewReleaseVersion.ps1`,
   `Test-TigerMarkViewReleaseReadiness.ps1`, + tests. Agent guidance still to be folded into the
   maintainer guide.
5. **Refactor post-release validation** - *pending.* Move `Test-TigerMarkViewWinGet.ps1` onto the
   shared `gh` adapter and the `PASS`/`WARN`/`BLOCKED`/`FAIL` result objects, add provenance-bound
   caching, and remove the raw-token compatibility routes once callers and tests migrate.
6. **Read-only fork safety** - *done.* `eng/winget/winget-pkgs.clone.json`,
   `eng/winget/WinGetPkgsClone.ps1` (config, slug comparison, interrupted-operation detection,
   clone identity, previous-PR gate), + tests. The `-PlanOnly` orchestrator entry point that ties
   these together with the artifact/lab validation is part of phase 7.
7. **Guarded submission mutation** - *pending.* `Prepare-TigerMarkViewWinGetSubmission.ps1`: fold in
   the phase-6 gates and the full lab result, then safe fork synchronization, resumable
   branch/copy/diff/commit/push, remote verification, and the final PR-only handoff.
8. **End-to-end recovery hardening** - *pending.* Interruption/rerun tests across every boundary,
   maintainer-guide rewrite from transition to implemented commands, and removal of the unsafe
   public token paths.

Do not combine the final mutation phase with foundational query work. Land and test read-only safety
gates before enabling fork writes. Phases 1-4 and 6 are landed and independently tested; 5, 7, and 8
remain.

## Acceptance criteria

- A short “Prepare release `<version>`” request leaves an intentional, validated, uncommitted release
  diff and an explicit review/commit/push handoff.
- Release automation refuses to mutate unless the exact release commit is on `origin/main` and its
  exact CI push run succeeded.
- One release workflow run builds the only authoritative installer, generates/validates/seals the
  only authoritative WinGet set, creates an annotated tag at that commit, and creates a draft with
  useful notes.
- The release is never auto-published and the final WinGet PR is never auto-created.
- The post-release command refuses a draft or non-public release and proves commit/run/artifact/asset
  provenance and hashes before fork mutation.
- Local/pre-release manifests can never be selected or submitted; regeneration is throwaway and
  byte-for-byte comparison only.
- The dedicated clone and remotes are exact, the latest project-specific PR gate blocks open/draft
  work, fork `master` is safely synchronized, and the release branch starts at current
  `upstream/master`.
- A `PASS` post-release run has copied only the sealed manifests, validated the exact destination,
  committed and pushed the expected branch, and leaves only PR creation/review to the human.
- Reruns recognize correct state, resume safely, and stop without overwrite on conflicts.
- Output consistently uses `PASS`, `WARN`, `BLOCKED`, `FAIL`, and `READY FOR HUMAN ACTION`, with
  evidence and exact next actions.
- No routine PAT handling, token arguments/logging, credential-store scanning, broad Actions
  permissions, manual hashes/copies/branches/commits/pushes, or unrelated credential fallback remains
  in the finished human workflow.

## Non-goals

- Implementing any automation in this documentation task.
- Automatically committing or pushing the TigerMarkView release-preparation changes.
- Automatically dispatching the release workflow after CI.
- Automatically publishing the GitHub draft release.
- Automatically creating, approving, merging, or monitoring the final `microsoft/winget-pkgs` PR.
- Modifying the real fork, dedicated clone, upstream repository, release, tags, or Actions runs while
  developing tests.
- Rebuilding or replacing published installer bytes, regenerating the authoritative manifests after
  release, code signing without a separately approved design, or adding new package formats.
- Generalizing into a cross-project framework before TigerMarkView's concrete workflow is complete
  and proven. Future Tiger projects should copy the finished model, not drive premature abstraction.

