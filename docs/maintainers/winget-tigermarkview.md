# Preparing the TigerMarkView WinGet package

The community identifier is `ItTiger.TigerMarkView`, following the established `ItTiger.TigerSqlCmd`
publisher spelling. Do not advertise the install command as live until the first `winget-pkgs` pull
request has been accepted and the community source returns the package.

## The flow

```text
release workflow: build installer -> generate manifests -> winget validate -> seal
                  -> upload TigerMarkView-WinGet-<version>-<commit>
maintainer:       publish the GitHub Release
                  -> download that sealed artifact -> validate it against the published
                     asset + TigerWinLab
                  -> copy those bytes, unchanged, into winget-pkgs
```

One rule holds the whole thing together: **the files copied into `winget-pkgs` are byte-for-byte the
files the release workflow generated and validated.** Nothing downstream regenerates them.

Three things generate or hold manifests, and they are not interchangeable:

| | |
| --- | --- |
| `Prepare-TigerMarkViewWinGet.ps1` | **local/pre-release generation.** Writes to `artifacts\winget\`. Hashes whatever installer it is given, normally a local Inno build, so its `InstallerSha256` is *not* the published one. Never submit its output. |
| `TigerMarkView-WinGet-<version>-<commit>` | **the authoritative post-release submission set.** Generated inside the release workflow from the installer that release actually published, then validated, sealed, and uploaded. |
| `Test-TigerMarkViewWinGet.ps1` | **post-release validation.** Downloads that artifact and validates it against the published release and TigerWinLab. It reads nothing under `artifacts\winget\`. |

## What the release workflow does

The workflow builds one installer, hashes it, generates the three manifests from that exact hash and
the immutable `v<version>` asset URL, and runs `winget validate` over them. It then *seals* the result
with `eng/winget/Assert-TigerMarkViewWinGetSubmission.ps1`, which proves the directory holds exactly
the three submission manifests, UTF-8 without a byte-order mark, agreeing on identity and version and
naming that asset URL, and records a digest over the three files.

That directory is uploaded as `TigerMarkView-WinGet-<version>-<commit>`. The artifact root *is* the
submission directory: three YAML files, nothing else. The publication job downloads the artifact and
re-runs the seal against the recorded digest, so an artifact that changed in transit cannot reach a
release.

WinGet is provisioned by the workflow only when the runner's own `winget.exe` is missing or fails
`--info`; the pinned `Microsoft.WinGet.Client` module repairs it in that case. The resolved executable
is passed explicitly to the generator. The client version is never probed: `winget validate` itself
decides whether it understands schema 1.12. Its documented warning-success HRESULT (`0x8A150028`) is
the only accepted nonzero result, and a genuine validation failure stays fatal.

To see what the manifests will say before a release exists:

```powershell
.\eng\winget\Prepare-TigerMarkViewWinGet.ps1
```

They are written to:

```text
artifacts\winget\manifests\i\ItTiger\TigerMarkView\<version>\
```

**That directory is never the post-release submission.** It hashes whichever installer was on hand, and
an Inno rebuild is never byte-identical to the one CI compiled, so a set left there by an earlier local
run declares an `InstallerSha256` that no release ever published. Reading it as though it were the
release's submission is exactly the mistake that failed 0.8.1 in TigerWinLab.

## After the GitHub Release is public

Everything below needs the release **published**: the manifests name the live immutable asset URL, and
that URL does not resolve while the release is a draft. Run from an **elevated** PowerShell 7 session
at the repository root — elevation is TigerWinLab's requirement, not this repository's.

```powershell
.\eng\winget\Test-TigerMarkViewWinGet.ps1 -Version <version>
```

That one command is the whole gate. It fetches the sealed set itself; there is no separate download
step and nothing to generate first.

Fetching the artifact needs a GitHub token with `actions:read` — listing it needs none, but downloading
it does. The token is read from `-GitHubToken`, then `GH_TOKEN`, then `GITHUB_TOKEN`, then
`gh auth token`. On a machine with none, download the artifact from the workflow run page and pass it
with `-ArchivePath <zip>`; it is checked against the same recorded digest, so it is a different route to
the sealed bytes rather than a weaker check.

The gate exits `0` on `PASS` and `1` on `FAIL`, prints a check table, and retains everything under
`artifacts\winget-release\<version>\`:

| Path | |
| --- | --- |
| `submission\` | **the authoritative set** — the three sealed YAML files extracted from the workflow artifact. These are the bytes that go to `winget-pkgs` |
| `submission.json` | provenance — release tag, commit, artifact name and id, workflow run id, the digest GitHub recorded, and the submission digest |
| `artifact\<artifact name>.zip` | the retained archive, so a rerun does not download again |
| `validation\result.json` | the machine-readable record — verdict, every check, installer digests, provenance, and the submission set with per-file hashes |
| `validation\summary.txt` | the same report as printed, so the record outlives the terminal |
| `validation\published\` | the installer, `SHA256SUMS.txt`, and `release-artifacts.json` downloaded from the release |
| `validation\regenerated\` | the throwaway reproducibility copy; never the submission |
| `validation\tigerwinlab-spec.json`, `tigerwinlab-result.json`, `tigerwinlab-artifacts\` | the lab's specification, result envelope, and evidence |

Useful switches: `-Json` emits the result record instead of the table; `-SkipLab` runs the manifest and
published-asset checks only and can never produce a submission-ready `PASS`; `-ArchivePath` supplies an
already-downloaded artifact archive; `-ExpectedSubmissionDigest` pins the submission digest the release
workflow's job summary recorded; `-Refresh` re-downloads over a retained archive; `-TimeoutMinutes`
bounds the guest scenario (default 45); `-TigerWinLabRoot` locates TigerWinLab.

To fetch and verify the sealed set on its own, without validating a release:

```powershell
.\eng\winget\Get-TigerMarkViewWinGetReleaseSubmission.ps1 -Version <version>
```

## What the gate proves

**`submission/source` — these three files came from one identified sealed artifact.** The version
resolves to the published release tagged `v<version>`; that tag resolves to a commit, dereferencing an
annotated tag; that commit selects the one artifact named `TigerMarkView-WinGet-<version>-<commit>`
whose workflow run built it — never merely the most recent WinGet artifact, because repeated release
attempts leave several of the same version behind. The downloaded archive must reproduce the SHA-256
GitHub recorded for that artifact before a single byte is extracted, and the extraction must yield
exactly the three manifests. Every one of those links throws when it breaks; **there is no fallback.**
A run that cannot reach the sealed artifact fails and validates nothing.

`submission/sealed-digest` appears when `-ExpectedSubmissionDigest` is supplied, pinning the manifests
themselves to the digest the workflow's sealing step recorded in its job summary.

**`release/*` — the published asset is the one the manifests describe.** The installer is downloaded
from the immutable URL exactly as an unauthenticated client would and hashed, then compared with the
release's own `SHA256SUMS.txt` and `release-artifacts.json` (digest, length, and `releaseVersion`).
A retained copy of the workflow-produced installer is compared too when one is kept under
`artifacts\winget-release\` (in the `<version>\` directory, an `installer\` subdirectory of it, a legacy
`v<version>\` directory, or directly); when none is, that is a `WARN`, because the pair that actually
matters is the manifests and the published bytes.

This never compares against `artifacts\installer\`. That directory holds the maintainer's own Release
build from step 2 of the release procedure, and an Inno rebuild is never byte-identical to the one CI
compiled, so treating it as a submission gate would fail every release for no reason.

**`submission/*` — the sealed manifests are the submission.** `submission/set` re-runs the same seal the
workflow ran, now against the published digest — this is the check that catches a manifest whose
`InstallerSha256` is not the published installer's. `submission/winget-validate` runs `winget validate`
over the sealed directory — the exact directory that gets copied. `submission/reproducible` regenerates
from the *published* installer into `validation\regenerated\` and requires the result to be
byte-identical to the sealed set. That regeneration is comparison only: it is written to a throwaway
directory and can never replace what is submitted. When the working tree is not at the version being
validated it cannot run, and reports `WARN` rather than a false proof.

**`lab/*` — WinGet can really install it.** The sealed manifest directory and the downloaded release
asset, not a local rebuild of either, are handed to TigerWinLab, which restores its Windows 11 guest to a clean checkpoint and runs the WinGet scenario
there: the declared `.NET Desktop Runtime 10` and `Microsoft Edge WebView2 Runtime` dependencies, a
local-manifest install with hash verification enforced, installed files, ARP registration, machine
`PATH`, `tiger-mark` resolution and smoke commands, a deliberately wrong hash that must be refused,
`winget` uninstall, and cleanup.

A `WARN` is something to read, not something that blocks a submission. Only a `FAIL` does.

## The submission

A `PASS` means these three files are ready, unchanged, for a `winget-pkgs` fork at
`manifests/i/ItTiger/TigerMarkView/<version>/`:

```text
artifacts\winget-release\<version>\submission\ItTiger.TigerMarkView.installer.yaml
artifacts\winget-release\<version>\submission\ItTiger.TigerMarkView.locale.en-US.yaml
artifacts\winget-release\<version>\submission\ItTiger.TigerMarkView.yaml
```

`validation\result.json` records each file's path, length, and SHA-256 under `submission.files`, the
same submission digest the workflow sealed, and under `provenance` the artifact those bytes were
extracted from — so the files submitted can be shown to be the files the release sealed and validated.
Copy them verbatim — a manifest edited after the run is a manifest nothing validated. If a change is
genuinely needed, change the generator, rerun the workflow, and rerun the gate.

**Opening the pull request is a human step and stays one.** Nothing in this repository authenticates
to, forks, or submits to `microsoft/winget-pkgs`. Fork it, copy the three files to the path above,
commit only that one package version, open the pull request, and follow its validation and review.

## Manifest shape

The repository uses the multi-file manifest format recommended by the WinGet community repository:
version, default-locale, and installer manifests at schema 1.12. The Inno installer has two entries
over the same verified asset:

- machine scope with `/ALLUSERS`, adding the install directory to machine `PATH`; and
- user scope with `/CURRENTUSER`, adding it to user `PATH`.

Both use x64, Inno silent/silent-with-progress switches, install-style upgrade behavior, the stable
Inno product code, ARP publisher/name matching, the `tiger-mark` command, and package dependencies on
`.NET Desktop Runtime 10` and `Microsoft Edge WebView2 Runtime`. The machine entry appears first so
TigerWinLab's machine-scope WinGet scenario can validate it explicitly.

Do not emit `AppsAndFeaturesEntries.DisplayVersion` when it is identical to `PackageVersion`. With no
explicit override the generator omits the field. Pass `-InstalledDisplayVersion` only when the
installed ARP display version genuinely differs.

## Failures worth recognising

- `release/assets` failed — the release is not published yet, or its assets are missing. Before
  publication this gate cannot pass, and that is not a defect.
- `release/checksums-file` or `release/artifact-manifest` failed — the published release disagrees with
  its own verification records. Stop and investigate the release; never adjust a manifest to accept
  surprising bytes.
- The run failed before any check, saying the sealed set could not be obtained — the release is not
  published, the workflow artifact has expired (30 days), or no `actions:read` token was found. Fix
  that; do not reach for `artifacts\winget\`. A set generated locally is not this release's submission.
- `submission/set` failed on `InstallerSha256` — the sealed manifests and the published asset disagree.
  Stop: either something other than the validated installer was published, or the wrong artifact was
  sealed.
- `submission/reproducible` failed — the sealed manifests are not what the generator now emits. Find
  out which is wrong before submitting either.
- `lab/result` says no result was written — the lab never ran. Confirm the session is elevated and the
  guest is provisioned with `New-TigerWinLab.ps1`.
- `lab/scenario` reports the lab is in use — there is one mutable VM; wait for its exclusive lease.

Nothing in this flow installs anything on the host or changes the host's WinGet settings. The install
happens in the lab guest, which is discarded afterwards.

## Reusing this for the next release

The flow is version-driven, not release-specific: publish the release, then run the same command with
the new version. The lab specification is generated per run from
`eng\winget\tigermarkview.labspec.template.json`, which is where TigerMarkView's installed shape is
described — expected files, machine `PATH` entry, dependencies, and smoke commands. Edit the template
when the installed shape changes; the version, manifest path, installer path, and expected URL are
filled in for you.

`eng\winget\tests\TigerMarkViewWinGet.Tests.ps1` covers manifest generation, the submission-set rules,
the sealing gate, the workflow's upload shape, and post-release acquisition — artifact selection by
version and commit, a missing or expired artifact, an unpublished release, an archive that does not
match the recorded digest, a published installer the manifests do not describe, an unreproducible
regeneration, and the proof that a stale set under `artifacts\winget\` can neither be selected nor
altered. It runs against a fake GitHub, so there is no VM, no network, and no token. Run it after
touching anything under `eng\winget\`.

Authoritative references are the WinGet community repository's
[manifest documentation](https://github.com/microsoft/winget-pkgs/tree/master/doc/manifest),
[schema 1.12 guide](https://github.com/microsoft/winget-pkgs/tree/master/doc/manifest/schema/1.12.0),
and [first contribution checklist](https://github.com/microsoft/winget-pkgs/blob/master/doc/FirstContribution.md).
