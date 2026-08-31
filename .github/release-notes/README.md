# Release notes source

One file per release: `<version>.md`, matching `<Version>` in `Version.props`.

This is the deliberate, user-facing summary that the release workflow attaches to
the draft GitHub Release with `gh release create --notes-file`. GitHub's
`--generate-notes` alone is not enough: for 0.8.1 it produced only a
**Full Changelog** link.

## Preparing a version

1. Copy [`TEMPLATE.md`](TEMPLATE.md) to `<version>.md`.
2. Replace every section with real content aimed at someone deciding whether to
   upgrade. Keep it short.
3. Run the check:

   ```powershell
   pwsh eng/release-automation/Assert-ReleaseNotes.ps1 -Version <version>
   ```

`eng/release-automation/Test-TigerMarkViewReleaseReadiness.ps1` runs the same
check, and the release workflow blocks if the file is missing, still holds
placeholder text, is essentially a bare changelog link, or contains a secret or a
local path.

The draft release stays editable, and publishing it is always a human action.
