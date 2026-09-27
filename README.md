# TigerMarkView

<p align="center">
  <img src="assets/TMV.png" alt="TigerMarkView icon" width="128">
</p>

TigerMarkView is a Windows desktop application for reading and reviewing local Markdown files. It is
a viewer, not an editor: when a document needs changes, TigerMarkView opens it in a configured
external editor and watches the file for updates.

The project is pre-1.0. Its current version is defined in `Version.props` and shown at run
time under **Help > About TigerMarkView**.

## Features

- rendered `.md` and `.markdown` documents with tables, task lists, links, images, and fenced code;
- drag-and-drop, Open Recent, local Markdown links, Back/Forward, and per-session navigation history;
- Manual, Confirm, and Automatic reload modes for files changed by another application;
- a status bar that distinguishes the viewed version from the version currently on disk;
- configurable external editors, including system default, Visual Studio Code, Notepad3, and a
  custom executable and arguments template;
- Light and Dark application themes;
- optional emoji shortcode expansion and syntax highlighting, both off by default;
- untrusted-content handling: formatting HTML is kept, scripts and other active content are removed,
  and images on network shares are never fetched;
- PDF export using the exact document version currently displayed;
- configurable menu bar, toolbar, status bar, and optional toolbar buttons;
- bundled offline Help, About, licence, and third-party notices;
- one per-user/all-users installer containing the GUI and CLI, which offers TigerMarkView under
  **Open with** for Markdown files without taking over your default app; and
- the `tiger-mark` command-line Markdown-to-PDF converter.

Printing is not included in the shipped application.

## Reading and reviewing

TigerMarkView focuses on files on the local machine. Every document-opening route uses the same
rendering and file-monitoring workflow. Links to other local Markdown files stay in TigerMarkView;
web and mail links open through the associated Windows application, and other local file types are
not launched from a document.

The reload modes determine what happens when the open file changes:

| Mode | Behaviour |
|---|---|
| Manual | Reports that a newer version exists and waits for an explicit reload. |
| Confirm | Shows an unobtrusive reload action. This is the default. |
| Automatic | Reloads automatically and preserves the reading position where practical. |

Open Recent records documents explicitly opened by the user and persists between sessions.
Navigation history records every document visited during the current session, including local links,
and restores the previous scroll position when navigating Back or Forward.

## Rendering

Markdown is converted by Markdig and displayed as HTML in WebView2. The same generated HTML and CSS
are used for the viewer and PDF export:

```text
Markdown -> Markdig -> HTML + CSS -> WebView2 -> viewer / PDF
```

Two rendering options are available under **View > Rendering**:

- **Emoji Shortcodes** expands recognised forms such as `:rocket:`. It is off by default. Literal
  emoji are unaffected, and unrecognised shortcodes or shortcodes inside code remain unchanged.
- **Syntax Highlighting** colours fenced code blocks when their declared language is recognised. It
  is off by default. TigerMarkView does not guess languages; an absent or unsupported language falls
  back to the normal code-block rendering.

Both options are implemented in `TigerMarkView.Core`, so the displayed document and an exported PDF
stay consistent. The CLI currently uses the default rendering with both options off.

Documents are treated as untrusted content. Formatting HTML inside Markdown (`<details>`, `<kbd>`,
sized images, tables, inline styles) is kept; scripts, event handlers, `javascript:` links, frames,
embedded objects, stylesheets, and forms are removed. Every generated page also carries a Content
Security Policy that admits only TigerMarkView's own script, and the viewer and PDF export refuse every
network request except images. Local and web images therefore keep working, while nothing in a
document can run, and the only requests it can cause are for the image addresses its author wrote.
Images on network shares are not loaded, whether addressed as `\\server\share`, through a mapped
network drive, or through a symbolic link to a share, because fetching them would send the reader's
Windows credentials to that server; this includes the images of a document that itself lives on a share
or a mapped drive. If the viewer cannot install its request protection, it shows no documents and says
why rather than showing them unprotected. The viewer, PDF export, and `tiger-mark` apply the same rules.
Inline SVG supports basic shapes with solid fills; external SVG paint resources are removed.
Web images are fetched without browser cookies or Windows sign-in credentials, so an image that
requires signing in does not load; ordinary public web images remain enabled, and a system proxy that
asks for Windows sign-in is still answered.

## PDF export

**File > Export to PDF...** exports the currently displayed document version. If a newer version is
available on disk but has not been reloaded, the PDF contains the version the reviewer can see. PDF
output always uses a light, print-oriented palette regardless of the viewer theme.

Global settings under **Tools > PDF Export Settings** are remembered between sessions:

| Setting | Choices | Default |
|---|---|---|
| Paper size | A3, A4, A5, Letter, Legal | A4 |
| Orientation | Portrait, Landscape | Portrait |
| Margins | Narrow, Normal, Wide | Normal |
| Page numbers | On, Off | Off |

## Window layout

The menu bar, toolbar, and status bar can be shown or hidden. The menu bar and toolbar cannot both be
hidden, and the toolbar's **Menu** (`☰`) button remains available whenever it is the only route to the
full command tree.

**View > Toolbar Buttons** controls three named items:

- **Menu**, shown by default;
- **Open Recent**, hidden by default; and
- **Export to PDF**, hidden by default.

These buttons mirror existing menu commands; toolbar customisation does not change the available
features.

## Installation

The initial public distribution is the Windows installer attached to a
[GitHub Release](https://github.com/rkozlowski/TigerMarkView/releases). The same installer contains
the desktop application, `tiger-mark`, bundled Help, the MIT licence, and third-party notices. It
installs for the current user by default and offers an all-users mode, which asks for administrator
approval. It is built with [TigerSetup](https://github.com/rkozlowski/TigerSetup) and also runs
unattended:

```powershell
TigerMarkView-<version>-win-x64-setup.exe install --quiet                  # for the current user
TigerMarkView-<version>-win-x64-setup.exe install --quiet --scope machine  # for all users
TigerMarkView-<version>-win-x64-setup.exe install --quiet --option path off
```

The **PATH** option is on by default, so `tiger-mark` works from a new shell. A per-user install
changes only the user's PATH; an all-users install changes the machine PATH. Upgrade and uninstall
preserve unrelated PATH entries.

The installer registers TigerMarkView as an available app for `.md` and `.markdown` files, so it
appears under **Open with** and in **Settings > Apps > Default apps**. It never writes a default app
and never replaces one you have chosen. If you have not chosen an app for Markdown files, Windows may
open them with TigerMarkView as the app offered for them. Uninstalling removes the registration and
leaves your settings and your default-app choice alone.

Installing this version over TigerMarkView 0.9.0 or earlier - which used an Inno Setup installer -
removes the earlier installation first and keeps your settings. The earlier installation is found in
the scope you install into, so an all-users installation of an earlier version is replaced by an
all-users install (`--scope machine`, or the all-users choice in the wizard).

TigerMarkView requires:

- Windows 10 version 1809 or later, or Windows 11, on x64-compatible hardware;
- the .NET 10 Desktop Runtime (x64); and
- the Microsoft Edge WebView2 Runtime.

The runtimes are not bundled. The installer checks for both and, when one is missing, downloads it
from Microsoft and installs it before TigerMarkView; installing a runtime asks for administrator
approval.

TigerMarkView is not yet published in the WinGet community repository. The prepared package identity
is `ItTiger.TigerMarkView`; this README will advertise `winget install ItTiger.TigerMarkView` only
after the first manifest has been accepted and the command is live.

To build the installer locally, install the TigerSetup release that `installer/tigersetup.json`
pins (its `tiger-setup` must be on PATH) and run:

```powershell
pwsh installer/Build-Installer.ps1
```

The output is written below `artifacts/`, which is ignored by Git.

## Command line

`tiger-mark` converts one Markdown file to one PDF without opening the desktop application. It is a
TigerCli-based command installed by the normal TigerMarkView installer. No separate CLI installer,
portable archive, or NuGet package is published by this repository.

Write the PDF beside the input (`notes.md` becomes `notes.pdf`):

```text
tiger-mark notes.md
```

Choose an output path and page settings:

```text
tiger-mark notes.md -o report.pdf
tiger-mark notes.md --output "output/review.pdf"
tiger-mark notes.md --paper Letter --orientation Landscape --margins Narrow --page-numbers
```

The command surface is:

- one positional Markdown input (`.md` or `.markdown`);
- `-o` / `--output <file>`; when omitted, the PDF is written beside the input;
- `--paper <A3|A4|A5|Letter|Legal>`;
- `--orientation <Portrait|Landscape>`;
- `--margins <Narrow|Normal|Wide>`;
- `--page-numbers`;
- `--header-left`, `--header-center`, `--header-right`, `--footer-left`, `--footer-center` and
  `--footer-right`, each taking a template;
- `--timestamped-fallback`;
- `--help` and `--version`; and
- `--help-errors` for the documented exit-code meanings.

Enum values are case-insensitive. TigerCli's grammar places the input before TigerMarkView's options:
`tiger-mark <input> [options]`. There are no subcommands, configuration files, multi-file publishing,
custom page dimensions, TOC generation, or CLI switches for emoji or syntax highlighting.

`--help` also lists TigerCli's standard presentation and diagnostics options, including `-h`,
`--version-full`, `--help-env`, `--non-interactive`, `--theme`, `--color`, `--no-color`, and
`--culture`. These control the command-line framework; for example, TigerCli's `--theme` does not
change the PDF palette.

On success the command writes `Created: <path>` to standard output and exits with code `0`. Conversion
failures return `1`, usage errors return `2`, and cancellation returns `3`. `4` means a PDF was created
but the requested output file could not be replaced, and only `--timestamped-fallback` can produce it.
Errors are written to standard error. The CLI is Windows-only and requires WebView2, like the desktop
application.

### Headers and footers

Six independent slots print in the page margins, above and below the text:

```text
tiger-mark report.md --header-left "{Title}" --header-right "{Date}" --footer-center "Page {Page} of {TotalPages}"
```

Each slot takes a template: ordinary text plus placeholders.

| Placeholder | Prints |
|---|---|
| `{Page}` | The current page number |
| `{TotalPages}` | The number of pages in the PDF |
| `{Title}` | The document's title (see below) |
| `{FileName}` | The Markdown file name without its extension |
| `{FileNameWithExt}` | The Markdown file name |
| `{FilePath}` | The Markdown file's full path |
| `{Date}` | The date the PDF was generated (`yyyy-MM-dd`) |
| `{Time}` | The time it was generated (`HH:mm:ss`) |
| `{DateTime}` | Both (`yyyy-MM-dd HH:mm:ss`) |

`{Date}`, `{Time}` and `{DateTime}` take an optional format after a colon — a
[.NET date and time format string](https://learn.microsoft.com/dotnet/standard/base-types/custom-date-and-time-format-strings),
applied with the invariant culture so the same command produces the same PDF on any machine. For
example `{Date:dd MMM yyyy}` prints `30 Aug 2026` and `{Time:HH:mm}` prints `14:25`. Placeholder names
are case-insensitive, and `{{` and `}}` print literal braces.

`{Title}` is the first of these the document offers: a `title:` key in its YAML front matter, then its
first level-one heading, then the file name without its extension.

One timestamp is taken when generation starts and used for every page, so a conversion that runs across
midnight still prints one date throughout. `--page-numbers` is shorthand for
`--footer-center "{Page}"`; an explicit `--footer-center` wins over the flag. Page space is reserved
automatically: a margin too shallow to hold a running head is widened to 14 mm, so headers and footers
never overlap the text. A slot left empty prints nothing and reserves nothing.

A malformed template — an unknown placeholder, a stray brace, an unusable date format — is a usage
error (`2`), reported before the document is read.

### Writing over a PDF that is open

By default the PDF is written straight to its destination, so a target that is open in a reader fails
the conversion after the work has been done. `--timestamped-fallback` writes to
`report-20260830142530.pdf` beside the destination first and then replaces the destination with it:

```text
tiger-mark report.md -o report.pdf --timestamped-fallback
```

If the replacement succeeds the command behaves exactly as it always has — `Created: report.pdf`, exit
`0`, and no timestamped file left behind. If it fails, the timestamped PDF is kept, the existing
`report.pdf` is left untouched, `Created:` names the file that was kept, an explanation goes to standard
error, and the exit code is `4`. Nothing is retried and nothing is deleted.

## Building and testing

The repository requires the .NET 10 SDK on Windows:

```powershell
dotnet restore TigerMarkView.slnx
dotnet build TigerMarkView.slnx
dotnet test TigerMarkView.slnx
dotnet run --project src/TigerMarkView
dotnet run --project src/TigerMarkView.Cli -- README.md -o README.pdf
```

## Repository structure

```text
src/
  TigerMarkView.Core/       Platform-neutral rendering and domain logic
  TigerMarkView/            Avalonia desktop application
  TigerMarkView.Pdf/        Windows/WebView2 PDF support
  TigerMarkView.Cli/        tiger-mark command

tests/
  TigerMarkView.Core.Tests/
  TigerMarkView.Cli.Tests/

docs/                       Bundled user documentation and notices
assets/                     Artwork and licence texts
installer/                  TigerSetup package and build script
```

`TigerMarkView.Core` must remain free of Avalonia and Windows-only dependencies. Both the GUI and CLI
reuse its renderer, and both use `TigerMarkView.Pdf` for PDF generation. `Version.props` is the single
source of product version and shared application metadata; production projects import it explicitly.

Contributor, architecture, and release guidance is in `AGENTS.md`; maintainer procedures are in
`docs/maintainers/`.

## Licence

TigerMarkView is released under the [MIT License](LICENSE). Third-party components and their licence
terms are listed in [docs/THIRD-PARTY-NOTICES.md](docs/THIRD-PARTY-NOTICES.md). Toolbar and status-bar
icons are derived from [Microsoft Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons).

## Copyright & Project Sponsor

TigerMarkView is an open-source project sponsored by [IT Tiger](https://www.ittiger.net/).
