# Repository Guidelines

## Project Structure & Module Organization

`TigerMarkView.slnx` groups production code under `src/` and xUnit projects under `tests/`. `TigerMarkView.Core` owns platform-neutral Markdown rendering and domain logic; `TigerMarkView` is the Avalonia desktop UI; `TigerMarkView.Pdf` contains Windows/WebView2 PDF support; and `TigerMarkView.Cli` provides the `tiger-mark` command. Keep tests in the matching project and feature folder, for example `tests/TigerMarkView.Core.Tests/Rendering/`. User documentation is in `docs/`, shared artwork and licence notices in `assets/`, and packaging scripts in `installer/`.

## Build, Test, and Development Commands

- `dotnet restore TigerMarkView.slnx` restores NuGet dependencies.
- `dotnet build TigerMarkView.slnx` compiles the full .NET 10 solution.
- `dotnet test TigerMarkView.slnx` runs all xUnit tests; add `--collect:"XPlat Code Coverage"` when coverage output is needed.
- `dotnet run --project src/TigerMarkView` launches the Windows desktop app.
- `dotnet run --project src/TigerMarkView.Cli -- README.md -o README.pdf` exercises the CLI.
- `pwsh installer/Build-Installer.ps1` publishes win-x64 output and builds the Inno Setup installer under `artifacts/`.
- `pwsh eng/lab/Test-TigerMarkViewRelease.ps1` runs installer and desktop release scenarios in TigerWinLab.

The desktop, PDF, and CLI projects require Windows; PDF workflows also require the Edge WebView2 Runtime.

## Coding Style & Naming Conventions

Follow existing C# style: four-space indentation, file-scoped namespaces, nullable reference types, implicit usings, and braces on separate lines. Use PascalCase for types, methods, properties, and test names; camelCase for locals and parameters; and descriptive domain names rather than abbreviations. Keep Core free of Avalonia and Windows-only dependencies, keep the CLI thin, and share rendering/PDF behavior through Core and Pdf. Add concise XML documentation where behavior or architectural intent is not obvious. `Version.props` is the only source of product version and common application metadata; only shipped production projects import it.

## Testing Guidelines

Tests use xUnit 2.9. Name files after the subject (`MarkdownRendererTests.cs`) and tests as readable behavior statements (`RemoteLinksAreNeverLocalMarkdownHoweverTheyEnd`). Use `[Theory]` for data-driven cases and `[Fact]` for a single scenario. Every behavioral change should include focused tests in the corresponding namespace; run the full solution before submitting.

Automated TigerMarkView UI interaction should run in TigerWinLab rather than on the developer's active desktop whenever the test can reasonably be executed there. This includes pointer/keyboard automation, installer, upgrade/uninstall, first-run, and WinGet scenarios. Use TigerWinLab's public scenario/job commands; do not script Hyper-V or TigerHyperLab directly from this repository. Quick manual host checks remain acceptable when a developer explicitly chooses them.

## Release and Documentation Boundaries

TigerMarkView ships one installer containing the GUI and `tiger-mark`. It does not publish NuGet packages, a separate CLI installer, or a portable ZIP. Release automation must build once, validate and hash the exact installer bytes, create an annotated tag at the validated commit, and create a draft GitHub Release. Publishing that draft and creating the final `microsoft/winget-pkgs` PR remain explicit human actions; deterministic post-release automation may prepare and push the exact sealed-manifest branch. Every stage after a human checkpoint must verify that checkpoint before mutation. Public documentation belongs in `README.md` and `docs/`. Do not add DocFX, generated API documentation, or an API-doc website for this application repository.

## Commit & Pull Request Guidelines

Use short, imperative or outcome-focused commit subjects. Keep each commit cohesive and avoid bundling unrelated cleanup. Pull requests should explain the user-visible change, identify affected projects, link relevant issues, and report test commands/results. Include screenshots for Avalonia UI changes and sample output for rendering, PDF, or CLI changes. Update `README.md` and `docs/HELP.md` when public or shipped behaviour changes, and keep durable architecture guidance in `CLAUDE.md` or close to the relevant code.
