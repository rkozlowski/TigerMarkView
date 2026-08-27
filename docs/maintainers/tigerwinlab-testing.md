# TigerMarkView release testing in TigerWinLab

Automated UI and destructive Windows integration tests use TigerWinLab so they cannot move the
maintainer's pointer, steal focus, close a live application, or mutate the workstation's installer,
PATH, ARP, WinGet, or prerequisite state. TigerHyperLab remains the registered-VM, lifecycle,
checkpoint, and lease substrate; TigerMarkView scripts call TigerWinLab's public commands only.

## Lab interface used by this repository

TigerWinLab provides the supported lifecycle and workload boundary:

- `New-TigerWinLab.ps1` provisions and captures the clean guest;
- `Test-TigerWinLab.ps1` reports readiness;
- `Reset-TigerWinLab.ps1` restores `BASE-CLEAN`;
- `Invoke-TigerWinLabJob.ps1` copies a payload, runs PowerShell through PowerShell Direct, and collects
  structured results/logs;
- `Invoke-TigerWinLabInstallerScenario.ps1` validates machine-scope Inno install, reinstall, optional
  upgrade, ARP, files, shortcuts, PATH, smoke commands, uninstall, and cleanup;
- `Invoke-TigerWinLabDesktopScenario.ps1` runs semantic UI Automation, real pointer/keyboard input,
  screenshots, modal/occlusion probes, and evidence collection on the guest's LabUser desktop; and
- `Invoke-TigerWinLabWinGetScenario.ps1` validates manifests, dependencies, local-manifest install,
  hash refusal, PATH/command behavior, uninstall, and cleanup.

Each state-changing operation restores or deliberately reuses a known checkpoint state, holds the
exclusive lab lease, and writes a JSON result plus evidence. Normal TigerMarkView automation should
not call Hyper-V cmdlets or TigerHyperLab directly.

## Repeatable release run

Build the candidate installer, confirm the lab is ready, then run:

```powershell
pwsh installer/Build-Installer.ps1 -Configuration Release
pwsh C:\Projects\TigerWinLab\Test-TigerWinLab.ps1
pwsh eng/lab/Test-TigerMarkViewRelease.ps1
```

The TigerMarkView wrapper first provisions the framework-dependent product prerequisites in a reset
guest. Its installer specification then verifies the all-users path: GUI and CLI files, bundled docs,
machine ARP publisher/version, one machine PATH entry, `tiger-mark` version
and help, reinstall idempotence, optional upgrade replacement, uninstall, and removal of installer
state. A second clean desktop scenario verifies rendering, UI Automation exposure, semantic commands,
physical menu input, modal handling, occlusion, screenshots, and F1 Help without touching the host.

Pass an older installer/version to enable the upgrade phases. Without a previous public build, those
phases are intentionally absent rather than simulated.

## Current concrete lab gaps

TigerWinLab's present generic installer scenario is machine-scope and administrative. It cannot yet
prove the per-user installer path under the non-admin LabUser identity, the absence of a UAC prompt for
that path, or the real interactive UAC boundary for the all-users path. The release workflow performs
a disposable per-user silent install/PATH/uninstall check on its clean Windows runner, but final
interactive coverage should move into TigerWinLab when its installer scenario gains a per-user mode.

The generic installer scenario also assumes a shortcut's parent directory is product-owned and must
be absent before installation and after removal. TigerMarkView intentionally places its single link
directly in Windows' shared `Programs` directory, so the wrapper omits that invalid assertion. Start
Menu launch is a manual lab-console release check until TigerWinLab can validate a root-level link
without treating the shared system directory as product-owned.

The desktop scenario requires a self-contained directory supplied by the host and does not attach to
an application left installed by the installer scenario. Consequently the wrapper verifies the exact
installer bytes and the live desktop in separate lab phases from the same source, not one continuous
installed-GUI session. Its current fixed interaction sequence opens Help but cannot yet navigate the
multi-step About links or complete the Save dialog used by GUI PDF export. CLI/PDF unit and application
tests remain the automated PDF gate; installed GUI About and GUI PDF export require a short manual
check in the lab console until TigerWinLab exposes a client-defined desktop action sequence.

Settings are intentionally under `%LocalAppData%\TigerMarkView` and the Inno source has no
`[UninstallDelete]`. The current generic scenario does not seed and compare a settings file across
uninstall, so settings preservation is a documented product expectation plus source contract, not yet
a lab assertion.

These are explicit gaps, not permission to fall back to invasive host-desktop automation. Record the
missing phase in release evidence and use a manual check inside the VM when it is release-critical.
