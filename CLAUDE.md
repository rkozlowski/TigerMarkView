# TigerMarkView engineering guidance

This file records durable architectural and implementation constraints for contributors and coding
agents. Public product behaviour belongs in `README.md`; shipped user instructions belong in
`docs/HELP.md`.

## Build and verification

Run from the repository root:

```powershell
dotnet restore TigerMarkView.slnx
dotnet build TigerMarkView.slnx
dotnet test TigerMarkView.slnx
```

Builds must remain at zero warnings. Automated tests cover Core and CLI behaviour, not the complete
Avalonia/WebView interaction. Automated pointer, keyboard, focus, installer, and other live Windows UI
work should run through TigerWinLab whenever it can reasonably do so; it must not drive the developer's
active desktop, live TigerMarkView process, or unrelated applications. Quick manual host checks remain
available to a developer. TigerWinLab is the application-facing lab interface; TigerHyperLab is its
lower-level VM substrate and must not be scripted ad hoc from this repository.

## Product boundary

TigerMarkView is a Windows Markdown viewer and reviewer, not an editor. Editing stays in an external
editor. The product remains focused on local-file rendering, external-change awareness, navigation,
and PDF export. Do not introduce editing, an IDE-style workspace, tabs, a project browser, Git
integration, or Markdown linting without an explicit product decision.

Printing is not part of the shipped UI. There is no Print menu item, toolbar button, or Ctrl+P command.
The isolated printing types in `TigerMarkView.Core.Printing`, `TigerMarkView.Pdf`, and
`TigerMarkView.Printing` are not reachable from the application. Do not reconnect them without a
separately designed and approved printing feature.

Ctrl+P is still intercepted in the window and document scripts solely to prevent WebView2 from opening
Edge's print preview. The intercepted command must remain a no-op.

## Project boundaries

`TigerMarkView.Core` owns platform-neutral behaviour:

- Markdown parsing, HTML generation, themes, CSS, emoji, and syntax highlighting;
- file-state, reload, navigation, recent-file, timestamp, and window-placement rules;
- editor-launch planning;
- PDF request validation, page geometry, and file naming;
- application-settings shape and version formatting.

`TigerMarkView` owns Avalonia and operating-system integration: windows, menus, WebView hosting, file
watching, settings storage, process launching, status presentation, and PDF export UI.

`TigerMarkView.Pdf` owns Windows/WebView2 PDF generation. `TigerMarkView.Cli` is a thin front end
over Core and Pdf. Core must not reference Avalonia or Windows-only assemblies, and the CLI must not
reference Avalonia.

Root `assets/` is repository-facing. `src/TigerMarkView/Assets/` contains application resources.
The EXE icon is both an `ApplicationIcon` and an Avalonia resource because Windows shell surfaces and
Avalonia windows consume it differently.

Command icons come from Microsoft Fluent UI System Icons, regular 24-pixel weight. Their
`StreamGeometry` values live in `src/TigerMarkView/Assets/Icons.axaml`; keep the upstream icon name
in the adjacent comment and retain the licence in `assets/licenses/`. Use inherited foreground
colours so one geometry works in both themes.

## Rendering and PDF invariants

The single rendering path is:

```text
Markdown -> Markdig -> HTML + CSS -> WebView2 -> viewer / PDF
```

Do not create a second Markdown pipeline, stylesheet, or PDF renderer. `DocumentShell` separates
structural CSS, theme colour tokens, and print rules. A new theme adds tokens, not a copy of the
stylesheet. Print CSS always re-declares the light palette so PDF output is independent of the screen
theme.

`MarkdownRenderingOptions` is a Core value passed through the renderer. Emoji shortcodes and syntax
highlighting are both false by default. Markdig owns shortcode expansion; smiley conversion stays
disabled. Syntax highlighting is produced while HTML is generated, with no script or network
dependency. Unknown or absent language identifiers fall back to the ordinary fenced-code renderer.

`MarkdownRenderer` caches one immutable pipeline for each rendering-option combination. The viewer,
Help, PDF export, and CLI must not assemble their own Markdig pipelines.

`RenderedDocument` retains Markdown, HTML, source timestamp, theme, rendering options, and page setup.
PDF export uses this retained snapshot so it exports the version currently visible, even when the file
on disk is newer. Theme, rendering-option, and page-setting changes re-render the retained Markdown;
they must not re-read the file and silently replace the reviewed version.

`PdfPageSetup` is physical geometry in millimetres plus margins and page-number state. Named paper,
orientation, and margin choices are translated only by `PdfPageSetup.For`. The same setup must reach
both the generated `@page` rule and `PdfExportRequest`; otherwise the HTML layout and PDF MediaBox
disagree. Format CSS dimensions with invariant culture.

The GUI exposes only A3/A4/A5/Letter/Legal, Portrait/Landscape, Narrow/Normal/Wide, and page numbers
on/off. `File > Export to PDF...` remains a single save dialog; persistent choices live under
`Tools > PDF Export Settings`.

Page numbers use the CSS `@bottom-center` margin box. Keep WebView2 headers and footers disabled,
because they add date and URL content. `PdfPageSetup.PrintMargins` expands a bottom margin that is too
small for the number band.

## WebView and window integration

The viewer shows one of three generated pages: the rendered document, an error page, or the themed
empty page. `MainWindow.RefreshViewerAsync` is the shared refresh path. The empty page stays blank,
but includes the host-shortcut scripts needed while focus is inside WebView2.

The generated shell scripts have narrow responsibilities:

- fragment links remain inside the current page despite its `<base href>`;
- Alt+Left and Alt+Right are forwarded to navigation;
- F1 is forwarded to Help; and
- Ctrl+P is cancelled and forwarded to a host no-op.

The WebView displays only TigerMarkView-generated preview files. Intercept other navigation:

- local Markdown routes through the normal document-opening pipeline;
- `http`, `https`, and `mailto` route to the system handler; and
- other local or unknown targets are refused.

Every open route must use:

```text
MainWindow.OpenFile
  -> OpenDocumentAsync
  -> ShowCurrentHistoryEntryAsync
  -> AttachDocument
  -> LoadAndRenderAsync
```

Do not load, render, or repoint the watcher in a second entry point.

`Browser` must retain `ClipToBounds="True"`. The native WebView can otherwise intercept pointer
events outside its visual bounds, including status-bar buttons. Icon-button tooltips must be anchored
above the control rather than at the pointer; use the existing toolbar/status styles.

WebView2 user-data folders must be explicit and under Local AppData, never beside the executable.
Viewer, export, and print hosts use separate sibling folders because WebView2 environments may share a
folder only when their creation options match.

`NativeTitleBar` applies the Dark-mode DWM attribute and refreshes the non-client area. Treat this as
best-effort: title-bar theming must never prevent a window from opening.

## Commands, menus, and toolbar

Toolbar buttons reuse their menu item's handler. Navigation enabled state is written by
`UpdateNavigationCommandState`; document-command enabled state is written by
`UpdateDocumentCommandState`. Reload mode has one state source and is reflected into both menu and
toolbar surfaces.

`ToolbarActions` controls the two optional command buttons: Open Recent and Export to PDF. Both are
off by default. The `☰` Menu button is a command surface governed by `CommandSurfaces`, not a
`ToolbarActions` convenience.

`CommandSurfaces` enforces:

- at least one of menu bar and toolbar is visible; and
- the `☰` button is visible whenever the menu bar is hidden.

Keep these rules in Core and repair invalid persisted combinations through
`ApplicationSettings.Normalized`.

`MenuMirror` builds the hamburger flyout from the live menu each time it opens. Mirrored checkbox
clicks do not update `IsChecked` like native menu clicks, so handlers must derive the new value from
application state and then write all check marks. Never use the sender's checked state as the source
of truth.

Flyouts opened from icon buttons use `BottomEdgeAlignedLeft`. An icon-only `DropDownButton` adds its
own chevron, so the navigation-history and Open Recent toolbar dropdowns remain plain buttons that
show a `MenuFlyout`.

## Navigation, recent files, and status

Open Recent and navigation history have different semantics:

- Open Recent persists explicit entry points: picker, drag/drop, command-line path, and a reselected
  recent item.
- Navigation history is the current session's browsing trail and includes local Markdown links.

`DocumentOpenOrigin` is required at every open call. Link navigation, Back/Forward, and history-list
selection must not add to Open Recent. History-list selection moves the existing history cursor and
preserves the Forward branch.

Build both Open Recent surfaces from `BuildRecentFileItems`, and both history surfaces from
`BuildHistoryItems` at open time. A populated `MenuFlyout` does not reliably refresh from a later
`ItemsSource` assignment.

Status semantics keep three timestamps distinct:

- the modification time of the rendered version;
- the current file modification time on disk; and
- the time of the last successful reload.

Status priority is Error, newer-on-disk, recently reloaded, then neutral. A document does not become an
error merely because it has been open for a long time. Temporary status messages replace presentation
only and must not mutate file state.

`ExportedPdfRegistry` remembers successful output per Markdown document for the current session.
Failed or cancelled exports do not replace a previous successful path, and actions must recheck that a
remembered output still exists.

## Help and bundled documentation

Help is an application documentation context, not a reader-opened document. It uses a separate
modeless `HelpWindow` and preview file. It must not affect the main document, watcher, scroll,
history, Open Recent, editor target, or PDF target.

`docs/HELP.md`, `docs/THIRD-PARTY-NOTICES.md`, and the root `LICENSE` are copied beside the
executable by `TigerMarkView.csproj`. `BundledDocuments` is the only path mapping. Help must remain
available offline; do not fetch documentation at run time. The licence is rendered verbatim from the
single root file rather than duplicated as Markdown.

Help links may open another bundled document, send `http`/`https`/`mailto` to
`ExternalLinkLauncher`, or be refused. They do not open arbitrary local files.

## The command line

`tiger-mark` converts one Markdown input to one PDF. It reuses
`MarkdownDocumentLoader.LoadHtmlDocument`, `PdfPageSetup.For`, and `PdfExporter.ExportAsync`.
The GUI exports the retained viewed version; the CLI has no viewer and reads the file when invoked.
CLI rendering options remain at their default.

TigerCli owns parsing, help, version display, error rendering, exit-code resolution, and interaction
policy. Do not pre-parse arguments, rewrite argv, add local usage text, or vendor/patch the framework
inside this repository. TigerCli's grammar is `tiger-mark <input> [options]`.

`TigerMarkApp.Create()` is the single application factory used by `Program` and tests.
`TigerMarkExitCode` is the single exit-code declaration. Domain failures become
`TigerCliCommandException`; successful output is exactly one `Created: <path>` line on stdout.

The app declares `NonInteractive`: missing values fail rather than opening prompts.
`settings.CancellationToken` must be passed explicitly to `TigerTui.RunActivityAsync`; activities do
not inherit it automatically. In `PdfConversion`, check a successful result before checking
cancellation so a completed PDF is reported as success.

The CLI page-option defaults must be explicit: A4, Portrait, Normal, and no page numbers. Some enum
zero values differ from those defaults. No dimensions or margin values belong in the CLI project.

## Versioning and packaging

`Version.props` is the single source of `Version`, assembly/file/informational versions, `Product`,
`Authors`, `Company`, `Copyright`, repository/documentation/issue links, and shared description.
The four shipped projects import it explicitly; test/helper projects do not. `Directory.Build.props`
contains repository-wide build policy only. Assemblies, About, TigerCli help/version output, installer
metadata, artifact names, release automation, and WinGet preparation derive from `Version.props`. Do
not repeat a literal product version elsewhere, except for the manual release workflow's input
default. That default only pre-populates the GitHub form; release validation must reject any value
that does not exactly match `Version.props`. Copyright metadata must match `LICENSE`.

`ApplicationVersion` strips build metadata for display. Tests verify formatting rules and metadata
consistency without asserting the current literal version.

`installer/Build-Installer.ps1` stages framework-dependent win-x64 GUI and CLI output in one tree and
invokes `TigerMarkView.iss`. The release workflow builds the solution once, then uses the script's
`-NoBuild` path so validation, installer compilation, hashing, and upload all concern the same binary
outputs. Generated files stay below ignored `artifacts/`.

The Inno script derives identity and version from the published executable. Keep its `AppId` fixed so
upgrades recognise previous installations. Per-user installation is the default; all-users
installation may elevate. The PATH task is checked for a first install and owns at most one exact raw
install-directory entry in the selected user/machine scope. It must not claim a pre-existing entry or
remove more than the entry it recorded. Uninstall leaves Local AppData settings and WebView profiles
intact.

Neither .NET nor WebView2 is bundled. The installer checks for both, downloads nothing, creates no
Markdown file association, and excludes debug symbols and XML documentation from the installed files.

TigerMarkView is an application repository. It publishes one GUI+CLI installer, not NuGet packages,
a separate CLI installer, or a portable ZIP. Public documentation remains `README.md` plus `docs/`;
do not introduce DocFX, generated API docs, or an API-documentation site. Release automation creates a
draft release and never submits to `winget-pkgs`; the first and subsequent WinGet pull requests remain
explicit maintainer actions after live-asset validation in TigerWinLab.

Inno Setup's preprocessor treats a line beginning with `#` as a directive, including in code blocks;
use `Chr(13) + Chr(10)` rather than a line-leading `#13#10` expression.
