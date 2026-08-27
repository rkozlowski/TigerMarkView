# Preparing the TigerMarkView WinGet package

The planned community identifier is `ItTiger.TigerMarkView`, following the established
`ItTiger.TigerSqlCmd` publisher spelling. Do not advertise the install command as live until the first
`winget-pkgs` pull request has been accepted and the community source returns the package.

The repository uses the current multi-file manifest format recommended by the WinGet community
repository: version, default-locale, and installer manifests using schema 1.12. The Inno installer has
two entries over the same verified asset:

- machine scope with `/ALLUSERS`, adding the install directory to machine PATH; and
- user scope with `/CURRENTUSER`, adding it to user PATH.

Both use x64, Inno silent/silent-with-progress switches, install-style upgrade behavior, the stable
Inno product code, ARP publisher/name matching, the `tiger-mark` command, and package dependencies on
`.NET Desktop Runtime 10` and `Microsoft Edge WebView2 Runtime`. The machine entry appears first so
TigerWinLab's current machine-scope WinGet scenario can validate it explicitly.

Do not emit `AppsAndFeaturesEntries.DisplayVersion` when it is identical to `PackageVersion`. With no
explicit installed display-version override, the generator treats the ARP version as the package
version and omits the field. Emit it only when the installed ARP display version genuinely differs,
by passing that value through `-InstalledDisplayVersion`.

## Before publication

The release workflow generates and runs `winget validate` over the manifests from the exact local
installer hash. It uploads them as the workflow artifact
`TigerMarkView-WinGet-<version>-<commit>`. This proves schema and release construction but not the
future public URL, which does not resolve while the GitHub Release is a draft.

The hosted runner's preinstalled WinGet is not trusted merely because it is present. The workflow
uses a pinned `Microsoft.WinGet.Client` module to force-provision WinGet 1.29.290, prints
`winget --info`, and passes that exact executable to the generator. The generator rejects clients
older than the manifest schema's 1.12 major/minor before validation and always uses
`--disable-interactivity`. WinGet's documented warning-success HRESULT (`0x8A150028`) is the only
accepted nonzero result; schema-incompatible clients and genuine validation failures remain fatal.

To generate the same files locally:

```powershell
pwsh eng/winget/Prepare-TigerMarkViewWinGet.ps1 -Validate
```

Local validation likewise requires WinGet 1.12 or later. Use `-WinGetPath` to bind the check to a
specific provisioned executable rather than whichever app execution alias happens to be first on
`PATH`.

They are written to:

```text
artifacts/winget/manifests/i/ItTiger/TigerMarkView/<version>/
```

## After the GitHub Release is public

Run the end-to-end readiness gate:

```powershell
pwsh eng/winget/Test-TigerMarkViewWinGet.ps1 -Version <version>
```

The command downloads the public installer, `SHA256SUMS.txt`, and `release-artifacts.json` without
GitHub authentication. It compares URL, hash, length, version, the retained local installer when
available, regenerates the manifests, runs `winget validate`, and hands the public installer plus
manifests to TigerWinLab. The lab resets its guest, validates the machine-scope manifest, installs
declared dependencies, installs with hash enforcement, checks GUI/CLI files, ARP, machine PATH,
`tiger-mark` resolution/version/help, tests a deliberately wrong hash is refused, uninstalls through
WinGet, and proves cleanup.

`-SkipLab` is available for a quick live-asset/schema check, but the release record should say that the
VM install gate was skipped. A submission-ready run ends with:

```text
PASS: ItTiger.TigerMarkView <version> is ready for a manual winget-pkgs submission.
```

Structured lab results and downloaded assets remain below
`artifacts/winget/validation/<version>/`.

## Manual first submission

After a full `PASS`, fork `microsoft/winget-pkgs` and copy the three validated YAML files verbatim to:

```text
manifests/i/ItTiger/TigerMarkView/<version>/
```

Commit only that one package version, open the pull request manually, and follow community validation
and review. Do not edit the copied manifests after the passing run; regenerate and rerun if a change is
needed. The TigerMarkView workflow deliberately has no credentials, fork operation, branch push, or
PR submission for `winget-pkgs`.

If the live hash differs from either release verification record, stop and investigate the GitHub
Release; do not adjust the manifest to accept surprising bytes. If the lab is `BUSY`, wait for the
exclusive lease. If the lab times out or a prerequisite cannot be installed, retain its artifacts and
reset before retrying.

Authoritative references are the WinGet community repository's
[manifest documentation](https://github.com/microsoft/winget-pkgs/tree/master/doc/manifest),
[schema 1.12 guide](https://github.com/microsoft/winget-pkgs/tree/master/doc/manifest/schema/1.12.0),
and [first contribution checklist](https://github.com/microsoft/winget-pkgs/blob/master/doc/FirstContribution.md).
