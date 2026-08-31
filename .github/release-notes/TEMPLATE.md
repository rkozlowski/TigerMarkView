<!--
  Copy this file to .github/release-notes/<version>.md during release preparation
  and replace every section with real, user-facing content.

  Rules enforced by eng/release-automation/Assert-ReleaseNotes.ps1:
    - the file must be named exactly <version>.md and be UTF-8 without a BOM;
    - it must keep at least two level-2 (##) sections;
    - it must have real prose, not just a "Full Changelog" link;
    - it must contain no placeholder text (TODO, TBD, <describe ...>, ...);
    - it must contain no secret or local filesystem path.

  Keep it short. This is what a person reads on the GitHub Release page to decide
  whether to upgrade.
-->

## Highlights

One or two short paragraphs, or a few bullets, on what is new or better for
someone using the TigerMarkView desktop app or the `tiger-mark` command.

## Fixed

- Bug fixes that a user would notice. Remove this section if there are none and
  add another meaningful one instead.

## Prerequisites and known limitations

- Windows 10 or later, x64.
- .NET Desktop Runtime 10 and the Microsoft Edge WebView2 Runtime must be
  installed. The installer checks for both and does not bundle them.
- Builds are currently unsigned. Windows SmartScreen may warn on first run.

## Install

- Download and run the `TigerMarkView-<version>-win-x64-setup.exe` asset below, or
- `winget install ItTiger.TigerMarkView` once the manifest is live in the
  community repository.
