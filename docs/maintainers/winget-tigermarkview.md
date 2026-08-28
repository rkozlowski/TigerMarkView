# Preparing the TigerMarkView WinGet package

The community identifier is `ItTiger.TigerMarkView`, following the established `ItTiger.TigerSqlCmd`
publisher spelling. Do not advertise the install command as live until the first `winget-pkgs` pull
request has been accepted and the community source returns the package.

## The flow

```text
build installer -> generate manifests -> winget validate -> store the exact manifests
  -> publish the GitHub Release -> validate the published asset + TigerWinLab
  -> copy the stored manifests, unchanged, into winget-pkgs
```

One rule holds the whole thing together: **the files copied into `winget-pkgs` are byte-for-byte the
files the release workflow generated and validated.** Nothing downstream regenerates them.

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

To generate the same files locally — they are byte-identical to the workflow's, which is what the
post-release gate proves:

```powershell
.\eng\winget\Prepare-TigerMarkViewWinGet.ps1
```

They are written to, and read back from:

```text
artifacts\winget\manifests\i\ItTiger\TigerMarkView\<version>\
```

That is also where you extract the workflow artifact if you would rather submit those bytes directly.

## After the GitHub Release is public

Everything below needs the release **published**: the manifests name the live immutable asset URL, and
that URL does not resolve while the release is a draft. Run from an **elevated** PowerShell 7 session
at the repository root — elevation is TigerWinLab's requirement, not this repository's.

```powershell
.\eng\winget\Prepare-TigerMarkViewWinGet.ps1
.\eng\winget\Test-TigerMarkViewWinGet.ps1 -Version <version>
```

`Test-TigerMarkViewWinGet.ps1` is the gate. It exits `0` on `PASS` and `1` on `FAIL`, prints a check
table, and leaves both readings of the run under `artifacts\winget\validation\<version>\`:

| File | |
| --- | --- |
| `result.json` | the machine-readable record — verdict, every check, installer digests, and the submission set with per-file hashes |
| `summary.txt` | the same report as printed, so the record outlives the terminal |
| `published\` | the installer, `SHA256SUMS.txt`, and `release-artifacts.json` downloaded from the release |
| `regenerated\` | the throwaway reproducibility copy; never the submission |
| `tigerwinlab-spec.json`, `tigerwinlab-result.json`, `tigerwinlab-artifacts\` | the lab's specification, result envelope, and evidence |

Useful switches: `-Json` emits the result record instead of the table; `-SkipLab` runs the manifest and
published-asset checks only and can never produce a submission-ready `PASS`; `-ManifestDirectory`
points at an extracted workflow artifact; `-TimeoutMinutes` bounds the guest scenario (default 45);
`-TigerWinLabRoot` locates TigerWinLab.

## What the gate proves

**`release/*` — the published asset is the one the manifests describe.** The installer is downloaded
from the immutable URL exactly as an unauthenticated client would and hashed, then compared with the
release's own `SHA256SUMS.txt` and `release-artifacts.json` (digest, length, and `releaseVersion`).
A retained copy of the workflow-produced installer is compared too when one is kept under
`artifacts\winget-release\` (either directly or in a `v<version>\` subdirectory); when none is, that is
a `WARN`, because the pair that actually matters is the manifests and the published bytes.

This never compares against `artifacts\installer\`. That directory holds the maintainer's own Release
build from step 2 of the release procedure, and an Inno rebuild is never byte-identical to the one CI
compiled, so treating it as a submission gate would fail every release for no reason.

**`submission/*` — the stored manifests are the submission.** `submission/set` re-runs the same seal
the workflow ran, now against the published digest. `submission/winget-validate` runs `winget validate`
over the stored directory — the exact directory that gets copied. `submission/reproducible` regenerates
from the *published* installer into `regenerated\` and requires the result to be byte-identical to the
stored set. That regeneration is comparison only: it is written to a throwaway directory and can never
replace what is submitted. When the working tree is not at the version being validated it cannot run,
and reports `WARN` rather than a false proof.

**`lab/*` — WinGet can really install it.** The downloaded release asset, not a local rebuild, is handed
to TigerWinLab, which restores its Windows 11 guest to a clean checkpoint and runs the WinGet scenario
there: the declared `.NET Desktop Runtime 10` and `Microsoft Edge WebView2 Runtime` dependencies, a
local-manifest install with hash verification enforced, installed files, ARP registration, machine
`PATH`, `tiger-mark` resolution and smoke commands, a deliberately wrong hash that must be refused,
`winget` uninstall, and cleanup.

A `WARN` is something to read, not something that blocks a submission. Only a `FAIL` does.

## The submission

A `PASS` means these three files are ready, unchanged, for a `winget-pkgs` fork at
`manifests/i/ItTiger/TigerMarkView/<version>/`:

```text
artifacts\winget\manifests\i\ItTiger\TigerMarkView\<version>\ItTiger.TigerMarkView.installer.yaml
artifacts\winget\manifests\i\ItTiger\TigerMarkView\<version>\ItTiger.TigerMarkView.locale.en-US.yaml
artifacts\winget\manifests\i\ItTiger\TigerMarkView\<version>\ItTiger.TigerMarkView.yaml
```

`result.json` records each file's path, length, and SHA-256 under `submission.files`, plus the same
submission digest the workflow sealed, so the files submitted can be shown to be the files validated.
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
- `submission/reproducible` failed — the stored manifests are not what the generator now emits. Find
  out which is wrong before submitting either.
- `lab/result` says no result was written — the lab never ran. Confirm the session is elevated and the
  guest is provisioned with `New-TigerWinLab.ps1`.
- `lab/scenario` reports the lab is in use — there is one mutable VM; wait for its exclusive lease.

Nothing in this flow installs anything on the host or changes the host's WinGet settings. The install
happens in the lab guest, which is discarded afterwards.

## Reusing this for the next release

The flow is version-driven, not release-specific: publish the release, then run the same two commands
with the new version. The lab specification is generated per run from
`eng\winget\tigermarkview.labspec.template.json`, which is where TigerMarkView's installed shape is
described — expected files, machine `PATH` entry, dependencies, and smoke commands. Edit the template
when the installed shape changes; the version, manifest path, installer path, and expected URL are
filled in for you.

`eng\winget\tests\TigerMarkViewWinGet.Tests.ps1` covers manifest generation, the submission-set rules,
the sealing gate, and the workflow's upload shape, with no VM and no network. Run it after touching
anything under `eng\winget\`.

Authoritative references are the WinGet community repository's
[manifest documentation](https://github.com/microsoft/winget-pkgs/tree/master/doc/manifest),
[schema 1.12 guide](https://github.com/microsoft/winget-pkgs/tree/master/doc/manifest/schema/1.12.0),
and [first contribution checklist](https://github.com/microsoft/winget-pkgs/blob/master/doc/FirstContribution.md).
