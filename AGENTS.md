---
TigerAiCore.version: 1.28.0
---

# AI Agent Instructions

<!-- TigerAiCore:begin version="1.28.0" sha256="860698984e5f9c164617345b8a41adcd3981ba947c3e28139c485b075d6a4f99" -->
## TigerAiCore inherited rules

<!-- Managed content. Author these rules in AGENTS.core.md in the TigerAiCore repository, never in a project copy. -->

### Bootstrap — do this first

Before applying any project instruction or doing any repository work, read the
`TigerAiCoreConfig` environment variable.

When `TigerAiCoreConfig` is set:

1. Treat its value as the path to the TigerAiCore TOML configuration and load
   that exact file.
2. Load the TigerAiCore repository from the configured `core` value.
3. Read `Version.toml` in that repository. Its `version` is the canonical
   instruction version.
4. Compare the `TigerAiCore.version` declared by the configuration with the
   canonical version. If it differs or is absent, refresh only the managed
   configuration block with
   `pwsh -File <TigerAiCore>/tools/Manage-TigerAiCoreConfig.ps1 -Update`,
   then continue. This is routine local maintenance: it needs no separate
   authorization, it preserves machine-specific `[labs.*]`, `[tools.*]`, and
   `[projects.*]` entries, and it must be reported in the task result. If that
   tool reports the configuration as malformed or ambiguous, stop and report it
   instead; never repair the configuration by hand.
5. Load the configured role instructions (`coder` or `consultant`) and verify
   that the role file declares exactly the same `TigerAiCore.version` in its
   front matter. If it does not, stop and report a TigerAiCore inconsistency.
6. Compare the canonical version with the `TigerAiCore.version` declared by
   this file and by `CLAUDE.md` when present. Comparison is exact; a patch
   difference is a real difference.
7. If the versions match, continue.
8. If they differ, the inherited rules in this repository are stale.
   Synchronize them (see *Inherited-rule synchronization*), then continue under
   the refreshed rules.
9. Keep this repository registered as a TigerAiCore consumer with
   `pwsh -File <TigerAiCore>/tools/Manage-TigerAiCoreConfig.ps1 -RegisterProject -ProjectPath <project root>`.
   It maintains one `[projects.<ProjectID>]` entry in the machine-local
   configuration, is idempotent, and leaves everything else in the file alone;
   synchronization performs the same step at the end of its own run. This is
   routine machine-local maintenance and needs no separate authorization.
   Report it only when it registered something or could not complete: a
   conflicting or malformed registration is reported and never repaired by
   hand. Registration is inventory, not authorization — it never makes this or
   any other registered repository writable.
10. Load `<TigerAiCore>/LicensingPolicy.toml` and, when present,
   `<project>/LicensingPolicy.toml`; resolve the default plus only the local
   file's explicit operations. A missing TigerAiCore policy is an inconsistency,
   not permission to infer an allowlist.
11. When this project is a Git repository, keep local project-identity commit
    enforcement active with
    `pwsh -File <TigerAiCore>/tools/Manage-TigerAiCoreGitHooks.ps1 -Enable -ProjectPath <project root>`.
    It writes `core.hooksPath` in the repository's machine-local `.git/config`,
    never committed project content, and is idempotent: an already-activated
    repository is left untouched. Attempt it where this agent can, then settle
    the postcondition with `-Check` rather than inferring success from having
    run the command: the agent's own permission model may refuse it, and
    `-Enable` refuses too, without writing, where the repository has its own
    hooks or another `core.hooksPath` (exit code `3`). Report it only when it
    activated something or protection is not active; an unprotected repository
    is an Architect action, not a blocker for the task.
12. Follow the shared role instructions first, then this file's
   project-specific instructions.
13. Discover Labs, shared tools, and registered consumer projects only from the
    TOML configuration. Do not assume sibling checkouts, fallback locations, or
    hardcoded ecosystem paths.

When `TigerAiCoreConfig` is not set:

1. State that TigerAiCore and its configured Labs/tools are unavailable.
2. Continue in standalone mode with this repository's instructions, including
   the inherited rules already present in this file.
3. Coding, builds, and repository-local validation may continue. Lab-backed
   E2E/VM verification and shared documentation artifact generation may be
   unavailable; report such checks as `NOT RUN` with the reason.
4. Do not probe likely ecosystem locations or invent a replacement integration.
5. Do not attempt to synchronize inherited rules. Without TigerAiCore the
   canonical version is unknown, and the local copy is the best available
   instruction set.
6. Without the TigerAiCore licensing defaults, do not infer automatic licence
   approval from a project override or a familiar licence name; report the
   licensing evaluation as unavailable and preserve the Architect gate.
7. Do not attempt commit-hook activation; the hook lives in TigerAiCore and its
   location is never guessed. A repository activated earlier keeps enforcing
   project identity. Commit subjects still carry `[<ProjectID>]`.
8. Do not attempt consumer registration: there is no machine-local
   configuration to register in, and its location is never discovered.

Configuration contains locations and non-secret integration metadata only.
Never put credentials, tokens, passwords, or private keys in the TOML file or
in this repository.

### Inherited-rule synchronization

Everything between the `TigerAiCore:begin` and `TigerAiCore:end` markers is
machine-managed and is a synchronized cache of TigerAiCore rules, kept local
for salience. TigerAiCore remains the authority.

- Never hand-edit content inside the managed block, and never copy generic
  TigerAiCore rules into project-specific sections.
- Synchronize with the tool in the TigerAiCore repository:
  `pwsh -File <TigerAiCore>/tools/Sync-AgentInstructions.ps1 -ProjectPath <project root>`,
  where `<TigerAiCore>` is the `core` path from the TigerAiCore configuration.
  Add `-Check` to report staleness without writing.
- Synchronization only rewrites the managed block and the `TigerAiCore.version`
  front matter. Project-specific content is never rewritten.
- If synchronization stops because the managed block is missing, duplicated,
  malformed, or locally modified, report the problem and stop. Do not repair it
  by hand-copying rule text.
- Do not write a machine-specific TigerAiCore path into a project repository.

### Always-visible working rules

These apply even when TigerAiCore cannot be loaded. The authoritative and
complete form of each rule is in the role instructions (`AI-CODER.md`,
`AI-CONSULTANT.md`); load them whenever TigerAiCore is available.

- **Project identity** — every prompt and every final response starts with
  `[Project: <ProjectFolderName>]`. On mismatch with the current project root
  folder, stop immediately and report it. The identity follows the work into
  Git: every commit subject begins with `[<ProjectID>]`, the same repository
  root folder name in compact form, and a local TigerAiCore `commit-msg` hook
  refuses a commit that does not carry it. The hook checks identity only, and
  never rewrites a message.
- **Commit protection** — hook activation is attempted, then verified.
  Protection is active only when the repository's local hook configuration
  resolves to the TigerAiCore hooks directory, which
  `Manage-TigerAiCoreGitHooks.ps1 -Check` reports; running `-Enable` is not
  evidence that it did anything. Where activation cannot be completed — the
  agent environment refused the command, another hook configuration owns the
  repository, or it failed outright — surface the required Architect action as
  `ACTION REQUIRED BEFORE COMMIT` immediately before the proposed commit
  message. Never claim protection is active while it is not, never present the
  repository as ready to commit, and never take over hooks that are already
  there. Successful or already-active protection stays quiet.
- **Repository state** — check for uncommitted changes before starting work.
  If unacknowledged changes exist, stop and report them instead of building on
  them.
- **Instruction projections** — TigerAiCore states the same rules in several
  places on purpose: conceptual model, role instructions, always-visible
  fragments, and synchronized project replicas. That overlap is controlled
  denormalization for LLM reliability, not redundancy. Never delete, merge, or
  replace a projection with a pointer to satisfy DRY; report suspected
  redundancy instead.
- **Action mode** — Coding is the default. Non-default modes are declared with
  an explicit `[Action: ...]` header. Never change action mode silently.
  `Autonomous Development` is the only mode that moves a human gate, and only
  while its own header is present; it is never inferred.
- **Git topology** — use the Architect-provided checkout: the current branch
  and the current working tree. Do not create or switch to another branch or
  worktree, and do not move the task into one, unless the declared action or
  the current prompt explicitly permits it; agent and platform isolation
  defaults grant no permission, and a forced isolation that cannot be bypassed
  is reported before any file is modified. `Autonomous Development` is the one
  exception, only because its own contract already defines its dedicated
  branch, and a platform-defined branch or worktree scheme never substitutes
  for that contract.
- **Documentation scope** — documentation is defined by intent, not by file
  extension. Comments, C# XML documentation comments, docstrings, embedded
  examples, help text, test names and display names, diagnostic text,
  identifiers that exist only to name a document, and references to other
  documents are documentation too. `[Action: Documentation]` may therefore
  change a source file, both to correct documentation content and to remove an
  improper dependency on a document, provided production behavior is unchanged.
  Never leave a known stale or invalid documentation reference in code merely to
  avoid touching a source file. When the correction would require changing
  product behavior, architecture, or executable logic, stop and escalate instead
  of widening the mode.
- **Documentation currency** — when work changes behavior, architecture,
  configuration, commands, APIs, dependencies, workflows, supported
  capabilities, or operational assumptions, update the owning documentation in
  the same task. Before reporting completion, check whether existing
  documentation became false, incomplete, or misleading. Update the document
  that owns the detail; do not edit `README.md` reflexively when another
  document owns it. When a document is renamed, moved, or restructured, find
  the comments and embedded references that point at it and keep them aligned.
- **Git carries project history** — current documentation describes what is
  true now, planning describes the next meaningful work, and Git records how the
  project got here; do not preserve historical narrative in current-state
  documentation in case it matters later. But present absence is not evidence of
  historical absence: when current state, documentation, runtime behavior,
  surviving artifacts, comments, tests, or configuration leave reasonable doubt
  about how or why something became the way it is, inspect targeted Git history
  before concluding that a capability, design, behavior, workaround, or
  implementation never existed. Do not turn every task into repository
  archaeology.
- **Durable artifacts do not depend on plans** — planning documents are
  temporary. Source code, comments, tests, fixtures, scripts, diagnostics, and
  durable documentation must never depend on a plan's path, wording, section
  names, step numbers, or milestone labels; they describe the resulting
  behavior, contract, architecture, or capability instead. Tests especially: a
  name like `PlanStep4_...`, or a comment saying "implements PLAN.md section
  3.2", is a defect to rewrite rather than a convention. When a plan is removed,
  renamed, retired, or converted into durable documentation, search the
  repository for its path and its distinctive identifiers and fix every durable
  artifact still pointing at them.
- **Project lessons** — a project may keep `LESSONS_LEARNED.md` at its root:
  current, non-obvious, project-specific knowledge that prevents repeating
  costly mistakes. Read it before retrying an approach that already failed or
  revisiting an area with a history of repeated failures, and do not repeat an
  approach it records as invalid unless new evidence materially changes the
  assumptions. When the project paid materially to learn something non-obvious
  and reusable — repeated failed attempts before the real cause was found, a
  plausible diagnosis proved wrong, an expensive environment or tooling
  constraint — capture it there before reporting completion; a session, chat
  history, and agent memory are not durable project context. Prevent
  mechanically first wherever a test, validation, invariant, or tool can, and
  keep the file to lessons that are still true rather than to a history of every
  defect. Lessons stay in the project that earned them; promote one to
  TigerAiCore or a shared Lab only on evidence that it is genuinely broader, and
  never by writing into that repository as a side effect of this work.
- **Planning layers** — high-level planning (Architect with the Consultant)
  settles what is being built and what must be true about it; repository-aware
  implementation planning fits that design to the real repository; execution
  planning is the Coder's own tactical working state and needs no Architect
  interaction. `Plan & Execute` primarily governs the last one. Planning is
  iterative, not a waterfall: a plan is direction, not a one-way handoff, and
  new evidence may reopen an Architect-owned question.
- **Spike and variant comparisons** — when requesting multiple spikes or
  variants, state which dimension varies and which dimensions stay fixed. Do
  not let an ambiguous request for variants silently choose a comparison
  dimension when that choice materially affects the work.
- **Decision ownership** — ask who should decide. Architect-owned questions
  materially affect product behavior, architecture, public contracts,
  compatibility, security, persistence or ownership semantics, user experience,
  project boundaries, or another hard-to-reverse choice. Evidence-owned
  questions depend on the repository, current behavior, external systems, Git
  history, or an experiment — investigate them instead of asking the Architect
  to guess. Coder-owned questions are local, reversible, and routine. Planning
  is sufficiently complete when the Coder can proceed without having to invent
  Architect-owned decisions.
- **Proportional engineering** — Good enough is an engineering threshold, not a
  universal quality level: the Architect owns a bar that is often high and
  always finite, and once it is met further improvement needs a concrete benefit
  that justifies its cost; it never excuses a known material defect, inadequate
  verification, or misleading documentation. DRY means one authoritative
  implementation of one stable concept, not textual deduplication. KISS means
  simplicity across the whole system and the whole experience, the end user
  included, not local code minimalism. Use the cheapest reliable path to the
  required validated result, counting Architect attention, rework, and recurring
  consumer complexity as cost. Technology choices also count clean/incremental
  build time, dependency-graph and distribution footprint, repeated
  worker/worktree builds, CI/verification, and likely maintenance/update cost
  where relevant; these are inputs, not a smallest-or-fastest mandate.
  **You can only do what you can do**: design around actual capability, and
  never make success depend on a human, agent, tool, environment, or external
  system doing what it cannot reliably do — when capability is insufficient,
  change the design, ownership, tooling, verification strategy, or scope instead
  of demanding impossible reliability from the same weak point again; that is
  not a lower quality bar and not permission to abandon difficult work. So do not
  refactor unrelated working code, abstract before a common responsibility is
  demonstrated, add configurability without a concrete requirement, expand scope
  for hypothetical needs, or keep improving a result that already meets its bar.
- **Desktop application experience** — Tiger desktop applications should look
  and feel like members of the same product family, regardless of
  implementation language or GUI framework: conventional platform behavior,
  restrained presentation, a dominant primary work area, quiet disabled states,
  theme-following icons, and discoverable icon-driven commands. The shared
  contract is the observable user experience — **share a visual and
  interaction language, not a fixed layout**, and do not let the GUI framework
  define the product experience. TigerMarkView (.NET/Avalonia) and
  Tiger3dForge (C++/TigerWinGui over Win32) are reference implementations of
  that experience, not dependencies; their frameworks differ; the shared
  observable UX is the reference. It is the default for new applications and
  substantial redesigns; never "correct" an established UI framework or desktop
  architecture unasked. KISS reaches
  the end user — if the implementation and the integration are simple but the
  end-user experience is confusing, KISS has failed — and family consistency
  never outranks clarity for the user of this product. Light and dark themes,
  and correct behavior under high-DPI and mixed-DPI conditions, are acceptance
  requirements rather than polish; theme coverage includes icons, contrast,
  disabled states, and status and error presentation. Prefer Fluent UI System
  Icons where a suitable concept exists, one coherent family and one glyph per
  concept, under the licensing gate like any other third-party asset. **UI
  state must not imply that stale, invalid, or failed data is current**: after
  a failed refresh, build, or reload, last-known-valid content may stay on
  screen only while the status says that is what it is. Exact layout, icon
  size, toolbar density, and status composition stay product-specific.
- **Command-line application experience** — Tiger CLI applications follow the
  TigerCli command model regardless of implementation language or CLI
  framework: `app <command-path> <positional-arguments> [options]`, with an
  empty command path for a root/default command. The command path selects
  which operation runs; positional arguments carry the command's required
  identity or context and come before options; options carry settings,
  modifiers, switches, and additional values. **Selector means object
  identity/key. Required does not mean selector. Selector usually means
  positional.** TigerCli defines the contract and is the reference
  implementation of that cross-language contract; outside .NET it is not a
  mandatory dependency: a Rust,
  C, C++, or deliberately non-TigerCli .NET implementation reproduces the
  applicable TigerCli command, argument, option, help, and interaction
  conventions rather than inventing a different Tiger CLI shape, and
  TigerCli's `command-apps.md` and
  `arguments-and-options.md` guides own the detail. The model is the
  default for a new CLI, a substantial new command surface, or an intentional
  redesign; never "correct" an established project-specific CLI choice unasked,
  and report a material deviation found in a requested review rather than
  silently changing it.
- **Autonomy boundary** — decide routine, local, reversible matters yourself.
  Escalate any decision that materially affects product behavior, architecture,
  security, scope, or compatibility; those belong to the Architect.
- **Escalation format** — when an Architect decision is required, present it as
  `PLANNING TRIGGER`, `IMPACT`, `OPTIONS`, `RECOMMENDATION`, `DECISION NEEDED`.
- **Autonomous development** — applies only under an explicit
  `[Action: Autonomous Development]` header, and is never inferred from the size
  of a task or the use of subagents. One Lead Coder governs the run: delegation
  transfers execution, not ownership of architectural coherence, integration,
  verification, repository state, or the result. Work stays on a dedicated
  non-main branch, where the Lead commits coherent verified checkpoints without
  per-commit approval, and may push that branch and create or update its pull
  request where the required access is already granted. Merging remains a human
  gate. `Co-Authored-By` names the model or models that materially authored the
  change — never the orchestrator or a reviewer by default, and never a model
  inferred from a role, an agent name, or a convention; record only provenance
  actually known. Delegate within the project's allowed model pool and
  capability order. Every delegated task gets a bounded timeout chosen for that
  work; a timeout, or a worker that stops producing evidence, is a diagnostic
  event — stop it, reassess, and change the task, model, or verification
  approach instead of repeating the loop. Repeated failure at the highest useful
  capability returns control to the Lead, and escalates when it exposes an
  Architect decision.
- **Human gates** — do not commit, push, publish, or perform other externally
  visible or irreversible actions without explicit authorization. The single
  exception is an explicit `Autonomous Development` run, and only for commits,
  pushes, and pull requests scoped to its own branch.
- **First WinGet submission** — **first WinGet submission requires a critical
  review against current TigerWingetHelper guidance**: the application's source
  and release, not only its manifests, reviewed by TigerWingetHelper's review
  procedure, with every applicable concern resolved by evidence before
  submission. TigerAiCore owns the gate; TigerWingetHelper owns the WinGet
  knowledge — never copy it or substitute a checklist of your own. A passed
  review is not a guarantee of approval. Later submissions are re-reviewed only
  where its guidance or a material change calls for it, and the gate covers
  WinGet only.
- **Ecosystem write boundary** — change only a repository the task explicitly
  puts in scope. Never modify TigerAiCore, a Lab, a shared tool, or another
  project as a side effect of work on this one; escalate the need instead.
  Reading stays within the access and discovery rules above.
- **Cross-project scope** — **write only the primary project's repository
  unless the current prompt explicitly lists additional writable repositories;
  never infer or widen cross-project scope.** The authorization is the
  `[Repositories: <ProjectID>, ...]` prompt header, it names the complete
  writable set including the primary project, it is exact, and it does not
  persist across prompts. Registration in `TigerAiCore.toml` — including a
  `[projects.*]` consumer entry — a dependency, a Lab relationship, an earlier
  session or task, a branch name, filesystem proximity, and mere reachability
  authorize nothing; discovery is not authorization. Read access, resolving a registered capability, and invoking a
  Lab are unaffected — cross-project scope is about writes. **One project owns
  the outcome. Explicitly listed repositories may participate in delivering
  it**: `[Project: ...]` names the primary project that owns the intent, the
  product outcome, and the acceptance that decides completion. Repository scope
  is a separate dimension from `[Action: ...]`, which still governs how the work
  is done and is never inferred from a repository list; `Autonomous Development`
  still needs its own explicit header. Validate every writable repository
  independently — root, identity, applicable instructions, working tree, branch,
  local policy, commit protection — and apply the uncommitted-changes guard per
  repository; authorization never permits absorbing another session's
  unacknowledged work. Fix behavior in the repository that owns it: cross-project
  scope removes a workflow boundary, never an architecture one, so consumer
  semantics still stay out of a provider. **The primary project's acceptance
  closes the loop** — supporting-repository verification is necessary but may be
  intermediate, so rerun the originating scenario after a supporting fix and
  never report completion because the supporting repository alone is green;
  cross-project loops are often expensive, so the loop-economics rules apply
  unchanged. If another repository turns out to need changes, stop and request an
  explicit scope change instead of adding it. **Every modified repository gets
  its own verification, hook state, Git history, and proposed `[<ProjectID>]`
  commit message**; unmodified repositories get none, and no proposal ever spans
  repositories.
- **Registered capabilities** — repository layout is not topology;
  `TigerAiCore.toml` is. Before claiming a Tiger Lab or tool is unavailable,
  guessing its location, or implementing a replacement, resolve the registered
  capability from the machine configuration named by `TigerAiCoreConfig` —
  `pwsh -File <TigerAiCore>/tools/Resolve-TigerAiCoreResource.ps1 -Lab <name>`,
  `-Tool <name>`, or `-Project <ProjectID>`. Never guess a sibling directory,
  assume a drive layout, scan the filesystem, invent a per-Lab discovery
  variable, or copy topology into a project. An explicit caller-supplied path
  remains a valid override where a public interface already accepts one; it is
  an override, not a second discovery system. Without the configuration,
  repository-local coding, builds, tests, and documentation continue; only
  capabilities that need a registered Lab or tool are unavailable, and that is
  not a project failure.
- **Consumer registry** — `[projects.<ProjectID>]` records that a local
  repository consumes TigerAiCore and where its root is, so the machine knows
  its consumers without anyone hand-editing the configuration or scanning
  disks. Bootstrap and synchronization keep the current repository registered;
  the entry is machine-local inventory, is written only by
  `Manage-TigerAiCoreConfig.ps1`, and is independent of `[labs.*]` and
  `[tools.*]` — one repository is often both a consumer and a registered
  capability, and those are different facts that are never merged. A conflict —
  a second existing path claiming one project id, a malformed entry — is
  reported, never silently resolved. **Registration is discovery, not
  authorization**: it supports read-only ecosystem questions and never makes a
  registered repository writable.
- **Lab boundaries** — Labs are generic providers. A Lab exposes parameterized
  capabilities and may document its known consumers, but consumer-specific
  folders, scripts, identities, and configuration belong in the consuming
  project. Labs provide platform capabilities; consumers provide product
  meaning — product semantics, product-specific orchestration, and acceptance
  assertions are the consumer's. Before extending a Lab, use its existing
  generic public interface, then ask whether a genuinely generic platform
  capability is missing: *would this capability still make sense if the current
  consumer did not exist?* If not, it belongs in the consumer. A missing
  generic capability is reported and implemented as a separate task in the
  provider repository, never as a side effect of consumer work. The reference
  Labs each own one layer — TigerHyperLab generic VM capability, TigerWinLab
  generic Windows capability, TigerLinuxLab generic Linux capability — and
  TigerWpLab is intended to compose on TigerLinuxLab for Linux concerns.
  Reference Labs maintain reusable, acceptance-ready platform baselines; system
  maintenance belongs to the Lab, and consumer projects do not absorb baseline
  upkeep.
- **Lab invocation** — a consumer invokes a Lab entry point as a child process,
  so the Lab's exit is a result rather than the end of the caller. The caller
  passes the path the Lab must write its machine-readable result to instead of
  discovering a run id or parsing shared output, defines and interprets the
  Lab's exit-code contract, and allows generous headroom beyond the Lab's own
  timeout because teardown continues after it fires. A missing or unreadable
  expected result is a failure, never a success.
- **Windows acceptance** — automated Windows GUI and system acceptance runs in
  TigerWinLab, not on the Architect's or a developer's live desktop. Resolve
  the Lab through the configuration, read its public consumer interface, and
  compose the consumer-owned payload and assertions; extend the Lab only when a
  genuinely generic Windows capability is missing. Do not drive pointer or
  keyboard input on a live desktop, require the Architect to leave their
  machine untouched, write one-off Hyper-V scripts inside a consumer, or
  rebuild DPI, theme, elevation, network, input, or evidence machinery per
  project. Manual Architect inspection remains a separate deliberate action.
- **Secrets and access** — use only explicitly granted resources; never store
  credentials, tokens, or keys in plain text anywhere in the repository.
- **Licensing gate** — load the Architect-owned TigerAiCore
  `LicensingPolicy.toml` plus any explicit project-root override. Check the
  actual licence, material terms, distribution implications, domain, and
  attribution decision before material technology or asset investment. Unknown,
  missing, ambiguous, or extra/custom terms never silently pass; genuine `OR`
  alternatives may select and record one approved option, while every `AND`
  component must pass. Re-evaluate updates against the accepted state, and
  surface any licence or material-term change as an Architect gate even if the
  new terms otherwise match an automatic rule. Agents may enforce policy but
  never add, remove, weaken, replace, or work around a licensing rule without
  explicit Architect approval.
- **Preferred technologies and formats** — use Tiger preferred technologies by
  default; deviate only for a concrete project requirement or a materially
  better engineering outcome, and never "correct" an established project
  choice unasked. Policy: TOML and JSON are the only preferred native
  structured-data formats; YAML is not a Tiger-owned file format and must not
  be chosen for new internal configuration or data — use it only where an
  external integration requires it. Preference: Fluent UI System Icons for
  Windows UI where suitable. A preference never overrides the licensing gate.
- **Tiger-owned shared implementations** — when Tiger owns the appropriate
  shared implementation, use it rather than independently reimplementing the
  same Tiger-family capability: **.NET CLI → TigerCli; Windows C++ desktop GUI
  → TigerWinGui**, each where it provides the required capability. A reference
  contract and a mandatory implementation are not the same thing. Deviate only
  for a concrete requirement or a materially better engineering outcome, stated
  where the choice is made, and never migrate an established project to a
  shared component unasked.
- **Verification** — verify with the strongest practical automated checks;
  aim for a clean build and green tests; distinguish a pre-existing dirty
  baseline from new failures; state clearly what could not be verified and why.
- **Open-loop work** — when verification is unavailable, become more
  conservative, not more creative. **Open loops must be kept as small as
  possible**: run it if possible; reuse mechanics a Tiger project has already
  proven; validate everything else locally — scripts, syntax, dry runs, mocked
  inputs, API shapes, the external environment's known differences reproduced;
  research what still cannot run in official documentation and proven runs
  before writing it; and leave only a minimal, isolated fragment as the next
  external run's single new uncertainty. **Close one external loop before
  opening the next.** A list of open loops is a risk register, not readiness;
  an expensive external run is the last step, not a debugging mechanism, and
  the Architect is not the probe that discovers whether automation works.
  **An external step must provide material evidence that cannot reasonably be
  obtained in the closed loop**: duplicating local tests in hosted CI is not
  additional validation by itself; the number of workflows is not a measure of
  open-loop size, and one workflow running a 20-minute suite is still a large
  open loop; hosted CI is not a substitute for the project's authoritative
  acceptance infrastructure; and the Architect must not pay a long
  hosted-validation cost after every ordinary commit for validation already
  required before handoff. Review each external step for the uncertainty it
  closes, why local validation is insufficient, and its expected external
  cost — no justification, no step.
- **Loop economics** — **Open/closed describes observability. Cheap/expensive
  describes iteration economics**, and a closed loop is not automatically an
  efficient one. A loop is expensive when the next meaningful result costs
  materially in elapsed time, compute, AI usage, environment setup,
  coordination, or Architect attention. **When the loop is expensive, make every
  iteration earn its cost**: use the cheapest reliable loop that can answer the
  current question, falsify the obvious causes with cheaper reliable checks
  first, and do not repeat an expensive run unchanged without evidence that
  justifies repeating it — while the expensive acceptance gate that trustworthy
  completion requires still runs. Observation has a cost too. **Do not poll an
  expensive loop more frequently than it can reasonably produce new evidence**:
  prefer a blocking wait, lifecycle-driven completion, a completion sentinel, or
  one structured result read, because **checking again is not new evidence**.
  **For expensive loops, maximize evidence per iteration and per observation.**
  Cheap local loops need none of this ceremony.
- **Required gates** — **a pre-existing failure may show that the current change
  did not introduce a regression; it does not turn a failing required gate into
  a passing gate.** Completion requires every applicable required verification
  gate to pass deterministically, unless the project has explicitly defined that
  gate as non-required or deliberately quarantined it. **Known flaky,
  nondeterministic, or environment-dependent required tests are verification
  defects** — fix them, move the assertion to a stable contract boundary, or
  quarantine them with a documented reason and owner, rather than normalizing
  the failures as "the baseline". Verify the contract at the most stable
  available boundary — structured properties, JSON fields, exit codes, durable
  result artifacts — rather than console rendering, ANSI colour, or terminal
  width. **Do not pay for an expensive gate when a cheaper reliable gate already
  proves the candidate is not ready.** **Green means every applicable required
  gate passed with trustworthy evidence**; report anything less as what it is,
  and never under "none".
- **Background work ownership** — background work the task starts belongs to
  the task. Before reporting completion, every process, job, monitor, waiter,
  worker, or agent it started must be completed, explicitly terminated, or
  deliberately handed off and named in the response; unaccounted task-created
  background work means the task is not complete. **Background accounting is
  registry-based, not process-list-based**: account against the session's own
  record of what this task started and resolve each unit, because one whose
  process has died without reaching a terminal state leaves the process list
  while staying unaccounted for. A process sweep is supplementary evidence, not
  the accounting authority, and where it helps it is scoped by the resources the
  work touched rather than by executable names — orphans are defined by task
  ownership and touched resources, not by executable identity. A monitor ends on
  the lifecycle of what it watches — lifecycle is authoritative, output is
  descriptive — and cleans up on failure, timeout, and cancellation too, so a
  missing marker never leaves an orphan waiter. **A monitor timing out does not
  stop the pipeline it watches**; the timeout ends the observation and says
  nothing about the underlying run, whose lifecycle must be established
  separately. **Background work started by a subagent stays owned by the Lead and
  the session** until it is terminal or explicitly handed off; a worker's "done"
  is a claim about the worker. This covers what the task started, not activity it
  did not start, and a task that started no background work owes no extra
  reporting.
- **Final response** — structured for fast Architect scanning, and ending with
  a `Proposed commit message` section whenever repository contents changed.
- **Commit message** — the subject begins with `[<ProjectID>]`, and the rest is
  proportional to the change and written for `git log`. A single-line subject
  is complete when it fully describes a small, obvious change; a short body is
  for durable context the subject and diff do not give, such as rationale,
  scope, non-obvious behavior, or accepted trade-offs. Never restate the
  implementation, the changed-file list, or the verification report there; that
  detail belongs in the final response.
<!-- TigerAiCore:end -->

## Project-specific instructions

This section is TigerMarkView-specific. It records the durable
architectural, implementation, and release constraints that this repository owns.
Shared role, action-mode, verification, automation-gate, and reporting rules come
from the TigerAiCore Coder instructions and are not repeated here. Public product
behaviour belongs in `README.md`; shipped user instructions belong in
`docs/HELP.md`.

### Repository layout

`TigerMarkView.slnx` groups production code under `src/` and xUnit projects under `tests/`. Keep tests
in the matching project and feature folder, for example `tests/TigerMarkView.Core.Tests/Rendering/`.
User documentation is in `docs/`, maintainer documentation in `docs/maintainers/`, shared artwork and
licence notices in `assets/`, packaging in `installer/`, and engineering automation in `eng/`.
Generated output stays below ignored `artifacts/`.

### Build and verification

Run from the repository root:

```powershell
dotnet restore TigerMarkView.slnx
dotnet build TigerMarkView.slnx
dotnet test TigerMarkView.slnx
```

Builds must remain at zero warnings. Add `--collect:"XPlat Code Coverage"` to `dotnet test` when
coverage output is needed.

Other routine commands:

- `dotnet run --project src/TigerMarkView` launches the Windows desktop app.
- `dotnet run --project src/TigerMarkView.Cli -- README.md -o README.pdf` exercises the CLI.
- `pwsh eng/tests/Invoke-EngineeringTests.ps1` runs every engineering PowerShell suite; `-Scope
  Repository` runs the fast ones normal CI also runs, `-Scope Maintainer` the winget-pkgs submission
  ones. Each suite is still an ordinary script that can be run on its own.
- `pwsh installer/Build-Installer.ps1` publishes win-x64 output and builds the TigerSetup installer.
- `pwsh eng/lab/Test-TigerMarkViewRelease.ps1` runs the installer, shell-integration and desktop acceptance in TigerWinLab.
- `git diff --check` before proposing a commit; CI runs it.

The desktop, PDF, and CLI projects require Windows; PDF workflows also require the Edge WebView2
Runtime.

### Lab-backed verification

Automated tests cover Core and CLI behaviour, not the complete Avalonia/WebView interaction.
Automated pointer, keyboard, focus, installer, upgrade/uninstall, first-run, and WinGet work should run
in TigerWinLab whenever it can reasonably do so. It must not drive the developer's active desktop, live
TigerMarkView process, or unrelated applications. Quick manual host checks remain available to a
developer who explicitly chooses them.

TigerWinLab is the application-facing lab interface; TigerHyperLab is its lower-level VM substrate.
Call TigerWinLab's public scenario/job commands only; do not script Hyper-V or TigerHyperLab from this
repository.

Labs and shared tools are resolved through `eng/TigerAiCore.ps1`, which reads the TOML file named by
`TigerAiCoreConfig`. That is the only discovery route. There is no sibling-checkout guess, no per-lab
environment variable, and no hardcoded ecosystem path: an unregistered lab reports why it is
unavailable and the check does not run. A maintainer may still pass an explicit path, because that is
a decision rather than a guess. `docs/maintainers/tigerwinlab-testing.md` records the lab interface
this repository uses and the current coverage gaps.

### Coding style

Follow existing C# style: four-space indentation, file-scoped namespaces, nullable reference types,
implicit usings, and braces on separate lines. Use PascalCase for types, methods, properties, and test
names; camelCase for locals and parameters; and descriptive domain names rather than abbreviations.
Add concise XML documentation where behaviour or architectural intent is not obvious.

Tests use xUnit 2.9. Name files after the subject (`MarkdownRendererTests.cs`) and tests as readable
behaviour statements (`RemoteLinksAreNeverLocalMarkdownHoweverTheyEnd`). Use `[Theory]` for
data-driven cases and `[Fact]` for a single scenario. Every behavioural change should include focused
tests in the corresponding namespace.

PowerShell under `eng/` and `installer/` targets PowerShell 7, uses `Set-StrictMode -Version Latest`
and `$ErrorActionPreference = 'Stop'`, and reports structured results rather than scraped text.

### Product boundary

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

### Project boundaries

`TigerMarkView.Core` owns platform-neutral behaviour:

- Markdown parsing, HTML generation, themes, CSS, emoji, and syntax highlighting;
- file-state, reload, navigation, recent-file, timestamp, and window-placement rules;
- editor-launch planning;
- PDF request validation, page geometry, and file naming;
- application-settings shape, the shared settings file's merge-update semantics
  (`ApplicationSettingsFile`), and version formatting.

`TigerMarkView` owns Avalonia and operating-system integration: windows, menus, WebView hosting, file
watching, the settings file's location (`SettingsStore`), process launching, status presentation, and
PDF export UI.

Multi-window is required, and each window is its own process; do not make TigerMarkView
single-instance or add IPC for it. All windows share one settings file. A window never writes its
whole in-memory `ApplicationSettings`: every change goes through `MainWindow.UpdateSettings`, which
applies that one change to the file as it is now under a per-file named mutex
(`ApplicationSettingsFile.Update`) and adopts the merged Open Recent list back. A change states the
value it sets, never toggles what it finds. Closing a window writes only its placement. Open Recent is
re-read from the file when a window is activated and when a surface showing it opens. Load Remote
Images is the one preference every open window applies as it is in the file now (see *Rendering and PDF
invariants*); other preferences a window adopts at its next start. Generated pages are per process
(`GeneratedPages`), never one shared file.

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

### Rendering and PDF invariants

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

Markdown documents are untrusted. Three layers enforce complementary contracts, each tested directly.
The image allowlist cannot stop executable code from sending data in an image URL; the sanitizer and
CSP must also prevent document code from running:

- `DocumentHtmlSanitizer` sanitizes Markdig's whole output inside `MarkdownRenderer.ToHtmlFragment`
  against an explicit allowlist (HtmlSanitizer/AngleSharp). It keeps passive formatting HTML and removes
  script, event handlers, active URL schemes, frames, plugins, media, stylesheets, forms, `base`, and
  `meta`. `data:` survives only as an `<img>` source. A URL that would fetch a file from another host
  (`\\server\share`, `//server/share`, `file://server/share`, and their encoded or mixed spellings) is
  dropped wherever the page would fetch it; a hyperlink keeps its target. Do not replace it with text
  matching, weaken it to the library defaults, or disable raw HTML wholesale.
- Every generated page (document, empty, error) carries `DocumentContentSecurityPolicy` as the first
  element after the charset: `default-src 'none'`, script and style elements admitted only by the SHA-256
  of the shell's own blocks, `style` attributes allowed, images from `file:`, `data:`, `http:`, and
  `https:`, `base-uri file:`, and `form-action 'none'`. Shell script and style text is emitted through
  `DocumentShell.Block` (LF-only) so the hash matches what the engine parses. Never add `'unsafe-inline'`
  or `'unsafe-eval'` for scripts, and never add a second script element. CSP cannot tell a local
  `file:` from a network one, so it is not a layer against network shares.
- `WebResourcePolicy` is the one request policy for both WebView2 hosts, applied by
  `WebViewResourceBoundary`: images may come from the web, `data:`, or a local file; the page itself
  only from a local file; every other request is answered `403`. Remote web images are an intended
  Markdown feature, so the rule is by resource kind, not by destination. A network file is not local:
  fetching one opens SMB with the reader's Windows credentials. `WebResourcePolicy.IsLocalFile` is an
  allowlist — no host, not UNC, and a decoded local path fully qualified on a drive letter — because
  `System.Uri` and Windows disagree about several share spellings. It is the only layer that stops a
  relative image in a document that itself lives on a share, so such images are not shown.
  `LocalImageStorage` checks DOS-device mappings with `QueryDosDevice` and each immediate reparse
  target, both while sanitizing absolute file URLs and at the Windows request boundary. Do not use
  `DriveInfo.DriveType` to classify a path: inspecting a SUBST alias can itself open its remote root.
  Local volume, optical, floppy and RAM devices are admitted; unknown device providers fail closed.
  The sanitizer also drops absolute network-backed drive image URLs on Windows, so an absolute
  reference never depends on the request callback running before the browser touches the path; the
  boundary repeats the check at request time because mappings and links can change after rendering.
  The two checks are complementary, not independent guarantees against every filesystem alias.
  It inspects each path component's immediate link target before opening the next component, refusing
  network targets and link cycles. Never resolve the final link target by opening it first: that can
  itself authenticate to a share. Local symbolic links remain usable.
  SVG presentation attributes need their own screening; only solid `fill` values survive. URL
  exceptions for hyperlink `href` and image `src` must use actual attribute identity, never matching
  the URL to another attribute on the same element (a CSS URL can have the same value).

  Allowed HTTP(S) images are downloaded by the shared boundary through a credentialless `HttpClient`
  and supplied as response bytes. Only image negotiation headers are copied; browser cookies,
  authorization and referrers are not. Redirects stay HTTP(S). A browser authentication-event veto is
  too late to prevent automatic NTLM negotiation, so never restore direct browser image networking
  without the loopback authentication regression. Images requiring authentication do not load. The
  client also offers nothing to a proxy (`DefaultProxyCredentials` stays `null`): a proxy requiring
  Windows authentication makes web images fail rather than receive the reader's sign-in. Do not restore
  ambient proxy credentials; authenticated-proxy support would be an explicit opt-in product decision.

  Remote images are a reader setting, `ApplicationSettings.LoadRemoteImages`, on by default. It is not
  a rendering option and does not change the HTML: `WebResourcePolicy.Allows(..., remoteImages)` is the
  one rule, and `WebViewResourceBoundary.Apply(core, remoteImages)` asks it on every web image request,
  so the viewer refuses web images before any request when it is off. The setting is global: in a
  window it is `SharedRemoteImagesSetting.AllowedNow()`, which reads the shared settings file at that
  moment and fails closed when the file cannot be read, so a window opened before another window turned
  remote images off never fetches one on its own stale copy. The window's `_settings.LoadRemoteImages`
  is only what its check mark and page show, adopted on activation and when a menu showing it opens.
  GUI PDF export passes that same question, `AllowedNow`, as `PdfExportRequest.RemoteImages`, so its
  boundary asks it at each request too; Help passes `false` (offline by contract); `tiger-mark` keeps
  the default, `null`, which is on.

PDF export additionally runs with document script, web messages, and host objects disabled, and cancels
any navigation other than its own temporary file. `eng/lab/Test-TigerMarkViewActiveContent.ps1` is the
TigerWinLab acceptance for all of this against the real viewer and `tiger-mark`.

`RenderedDocument` retains Markdown, HTML, source timestamp, theme, rendering options, and page setup.
PDF export uses this retained snapshot so it exports the version currently visible, even when the file
on disk is newer. Theme, rendering-option, and page-setting changes re-render the retained Markdown;
they must not re-read the file and silently replace the reviewed version.

`PdfPageSetup` is physical geometry in millimetres plus margins and the page's running heads and feet.
Named paper, orientation, and margin choices are translated only by `PdfPageSetup.For`. The same setup
must reach both the generated `@page` rule and `PdfExportRequest`; otherwise the HTML layout and PDF
MediaBox disagree. Format CSS dimensions with invariant culture.

The GUI exposes only A3/A4/A5/Letter/Legal, Portrait/Landscape, Narrow/Normal/Wide, and page numbers
on/off. `File > Export to PDF...` remains a single save dialog; persistent choices live under
`Tools > PDF Export Settings`. Header/footer templates are a command-line capability; do not add a GUI
surface for them without a product decision.

Headers and footers are the six CSS `@page` margin boxes, written from `PdfHeaderFooter`'s six template
slots. Keep WebView2 headers and footers disabled, because they add date and URL content. Page numbering
is not a separate mechanism: `PdfPageSetup.ShowPageNumbers` is derived from the footer-centre slot
holding `HeaderFooterTemplate.PageNumber`, and `PdfPageSetup.PrintMargins` widens any margin too shallow
for the band on the edge that has something printed on it. A slot that prints nothing writes no margin
box and reserves no space.

`HeaderFooterTemplate` owns the template language and is the only thing that turns a template into CSS.
`{Page}` and `{TotalPages}` must stay unresolved as `counter(page)`/`counter(pages)`; every other
placeholder is resolved once, from `PdfDocumentFacts`, so all pages carry identical text. One timestamp
is captured at generation start and carried in those facts. Dates use invariant culture. Template text
reaching CSS must be escaped, including `<`, because the stylesheet lives inside a `<style>` element. A
malformed template is refused at the command line and dropped — never thrown — during rendering.
`MarkdownDocumentTitle` resolves `{Title}` as front matter `title:`, then first H1, then file name, and
parses with the shared Markdig pipeline rather than matching text.

Print tables use automatic layout with `overflow-wrap: break-word` cells, so printed column widths match
the viewer's. Do not restore `table-layout: fixed` (it divides the page evenly, ignoring content) and do
not widen cell wrapping to `overflow-wrap: anywhere` (it makes a cell's minimum one character, which
collapses every narrow column). Inline `code` wraps the same way for the same reason; `pre` keeps
`anywhere`.

### WebView and window integration

The viewer shows one of three generated pages: the rendered document, an error page, or the themed
empty page. `MainWindow.RefreshViewerAsync` is the shared refresh path. The empty page stays blank,
but includes the host-shortcut scripts needed while focus is inside WebView2.

The generated shell scripts have narrow responsibilities:

- fragment links remain inside the current page despite its `<base href>`;
- Alt+Left and Alt+Right are forwarded to navigation;
- F1 is forwarded to Help; and
- Ctrl+P is cancelled and forwarded to a host no-op.

The WebView displays only TigerMarkView-generated preview files. Intercept other navigation:

- local Markdown routes through the normal document-opening pipeline, except that while a document is
  on screen no WebView request may open a Markdown file not on local storage: `NetworkLinkPolicy`
  refuses it before anything opens it, whatever `ViewerRequestOrigin` concluded, because opening a share
  signs in to its host with the reader's credentials and href matching must not be the only guard.
  Explicit opens that bypass the WebView (picker, a drop on the chrome or the empty viewer, Open Recent,
  command line) may still name a share;
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

The viewer and Help navigate their WebView only through `DocumentWebView.Navigate`, never by assigning
`NativeWebView.Source`. Avalonia starts navigating a pre-set `Source` before it raises `AdapterCreated`,
so `DocumentWebView` holds the first target until `WebViewResourceBoundary` is installed on the new
`CoreWebView2`; otherwise the first document, often one named on the command line, would load without
the request boundary. `ViewerNavigationGate` owns that decision and fails closed: if the boundary cannot
be installed, no document is ever shown in that WebView, a generated notice names the reason, and the
viewer's status bar reports it as an error. Do not reintroduce a fallback that shows documents
unprotected; the boundary is the only layer against relative images on a network share. PDF export
fails the export instead, because `WebViewResourceBoundary.Apply` failing aborts it.
Adapter destruction resets the navigation gate and clears Avalonia's remembered source before a new
adapter can replay it. Host messages are accepted only from the current protected preview URL; host
objects and frame navigation are disabled. Viewer and Help refuse unknown navigation schemes.

`Browser` must retain `ClipToBounds="True"`. The native WebView can otherwise intercept pointer
events outside its visual bounds, including status-bar buttons. Icon-button tooltips must be anchored
above the control rather than at the pointer; use the existing toolbar/status styles.

WebView2 user-data folders must be explicit and under Local AppData, never beside the executable.
Viewer, export, and print hosts use separate sibling folders because WebView2 environments may share a
folder only when their creation options match.

Every WebView2 engine runs InPrivate (Avalonia's `IsInPrivateModeEnabled` for viewer and Help, the
controller option for PDF export), so viewing leaves no browsing history, cache or session on disk.
`InPrivateBrowsing.RemovePersistentProfile` deletes the persistent `EBWebView\Default` profile earlier
versions recorded, once per folder (marker file). Do not reintroduce a persistent profile or replace
InPrivate with clearing data at shutdown, which a crash defeats.

`NativeTitleBar` applies the Dark-mode DWM attribute and refreshes the non-client area. Treat this as
best-effort: title-bar theming must never prevent a window from opening.

### Commands, menus, and toolbar

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

### Navigation, recent files, and status

Open Recent and navigation history have different semantics:

- Open Recent persists explicit entry points: picker, drag/drop, command-line path (Open with and
  shell launches), and a reselected recent item.
- Navigation history is the current session's browsing trail and includes local Markdown links.

`DocumentOpenOrigin` is required at every open call. Link navigation, Back/Forward, and history-list
selection must not add to Open Recent. History-list selection moves the existing history cursor and
preserves the Forward branch.

WebView2 reports a file dropped on the document area the same way as a followed link: a request to
show a local `file:` URL. `ViewerRequestOrigin` classifies every such request: it is `Navigation` only
when the displayed page has an `href` to that file (a sanitized page runs no script, so it can navigate
nowhere else), and `ExplicitOpen` otherwise, including every request on the empty and error pages.
A dropped file the page also links to is indistinguishable from following the link and is treated as
one, which keeps "links never enter Open Recent" exact.

Build both Open Recent surfaces from `BuildRecentFileItems`, and both history surfaces from
`BuildHistoryItems` at open time. Clear Recent Files ends both Open Recent surfaces, after a separator,
only while the list has entries; it clears and saves at once, with no confirmation, and touches neither
the documents nor the session's navigation history. A populated `MenuFlyout` does not reliably refresh from a later
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

### Help and bundled documentation

Help is an application documentation context, not a reader-opened document. It uses a separate
modeless `HelpWindow` and preview file. It must not affect the main document, watcher, scroll,
history, Open Recent, editor target, or PDF target.

`docs/HELP.md`, `docs/PRIVACY.md`, `docs/THIRD-PARTY-NOTICES.md`, and the root `LICENSE` are copied
beside the executable by `TigerMarkView.csproj`. `BundledDocuments` is the only path mapping. Help must remain
available offline; do not fetch documentation at run time. The licence is rendered verbatim from the
single root file rather than duplicated as Markdown.

Help links may open another bundled document, send `http`/`https`/`mailto` to
`ExternalLinkLauncher`, or be refused. They do not open arbitrary local files.

### The command line

`tiger-mark` converts one Markdown input to one PDF. It reuses
`MarkdownDocumentLoader.RenderHtmlDocument`, `PdfPageSetup.For`, and `PdfExporter.ExportAsync`.
The GUI exports the retained viewed version; the CLI has no viewer and reads the file when invoked.
It reads that file exactly once: the same text is rendered and resolves `{Title}`, so a running head
cannot describe a version the PDF does not contain. CLI rendering options remain at their default.

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

The six `--header-*`/`--footer-*` options bind straight to `PdfHeaderFooter`'s slots; the template
language, its validation, and its CSS belong to Core. `--page-numbers` remains shorthand for
`--footer-center "{Page}"`, and an explicit `--footer-center` wins over the flag. A malformed template
is refused through `ConvertSettings.Validate` — a usage error, before anything is read or written.

`--timestamped-fallback` is opt-in and is the only way to reach `TigerMarkExitCode.TargetNotReplaced`.
It writes to `PdfFileNaming.TimestampedVariant` beside the destination and then moves the file over the
destination. A failed move keeps the timestamped PDF, leaves the destination untouched, still writes one
`Created:` line naming the file that exists, and explains itself on stderr. It never retries, waits for a
lock, or deletes anything, and the default direct-write path must stay unchanged.

### Versioning and packaging

`Version.props` is the single source of `Version`, assembly/file/informational versions, `Product`,
`Authors`, `Company`, `Copyright`, repository/documentation/issue/privacy-statement links, and shared
description. The privacy statement link is the WinGet `PrivacyUrl`, which every submission set must
declare. It is version-derived - `$(RepositoryUrl)/releases/download/v$(Version)/PRIVACY.md`, the
version's own immutable release asset - and generation, sealing, and the post-release gate refuse any
other value, `blob/main` included. A privacy statement is version-specific product behaviour: never
point a released version at a mutable copy. The manifest's `LicenseUrl` (`blob/v<version>/LICENSE`) and
`ReleaseNotesUrl` (`releases/tag/v<version>`) are pinned to the version the same way, through the
`{version}` token `Resolve-TigerMarkViewWinGetVersionedUrls` resolves.
The four shipped projects import it explicitly; test/helper projects do not. `Directory.Build.props`
contains repository-wide build policy only. Assemblies, About, TigerCli help/version output, installer
metadata, artifact names, release automation, and WinGet preparation derive from `Version.props`. Do
not repeat a literal product version elsewhere, except for the manual release workflow's input
default. That default only pre-populates the GitHub form; release validation must reject any value
that does not exactly match `Version.props`. Copyright metadata must match `LICENSE`.

`ApplicationVersion` strips build metadata for display. Tests verify formatting rules and metadata
consistency without asserting the current literal version.

The installer is built with TigerSetup, the Tiger-owned installer tool, following its own proven
TigerMarkView package. `installer/TigerSetup.toml` is the package; `installer/tigersetup.json` pins
the one TigerSetup release (version, URL, SHA-256) every build uses, and `installer/TigerSetupBuilder.ps1`
is the one place that resolves the builder (`-TigerSetupPath`, else `tiger-setup.exe` on PATH) and
refuses any other version. `installer/Build-Installer.ps1` stages framework-dependent win-x64 GUI and
CLI output in one tree, checks its metadata, and runs `tiger-setup build` and `verify`, keeping the
artifact name `TigerMarkView-<version>-win-x64-setup.exe`. `-Version` builds a local upgrade candidate
through an MSBuild global property without editing `Version.props`; release automation never passes
it. The release workflow builds the solution once, then uses the script's `-NoBuild` path so
validation, installer building, hashing, and upload all concern the same binary outputs. Generated
files stay below ignored `artifacts/`.

The manifest states no version: `[metadata] source = "msbuild"` reads it from `Version.props`, and the
builder refuses a published executable that disagrees. The few values TigerSetup cannot read from the
build (product links, WinGet descriptions) are repeated in the manifest and kept equal to
`Version.props` by `eng/tests/Installer.Tests.ps1`. The package id `ItTiger.TigerMarkView` is the
Add/Remove Programs key and the WinGet identifier; never change it. `[legacy]` names the Inno Setup
registration of 0.9.0 and earlier (`{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}_is1`), which the first
TigerSetup install in the same scope removes with its own quiet uninstaller. Per-user installation is
the default; all-users installation elevates. The PATH option is on by default and TigerSetup owns at
most one install-directory entry per scope, never claiming a pre-existing one.

Uninstall removes what the installation owns and then, through the one custom action
`remove-local-data` (`installer/actions/remove-local-data.cmd`, a packaged `post-uninstall` action),
the uninstalling account's `%LOCALAPPDATA%\TigerMarkView` (settings, Open Recent, WebView2 profiles)
and `%TEMP%\TigerMarkView` (generated pages). An upgrade keeps them: TigerSetup runs uninstall-phase
actions on an uninstall only, never on an upgrade, so do not move this into an install phase or a
TigerMarkView-side workaround. Every per-user folder the application writes must stay under those two
roots; `eng/tests/Installer.Tests.ps1` checks that, and the script removes links without following
them. The action reports failure (`on_failure = "continue"`) rather than rolling an uninstall back
over a held file. `docs/PRIVACY.md` describes this behaviour to users and must change with it.

The installer registers TigerMarkView as an available Markdown handler for exactly the extensions
`MarkdownLinkResolver.MarkdownExtensions` names: the ProgID `TigerMarkView.Markdown` (the installed
`TigerMarkView.exe "%1"`), the extensions' `OpenWithProgids`, and a Default apps capability. It never
writes an extension's default value or `UserChoice`, so it is offered under Open with and never replaces
a default the user chose; uninstall removes exactly those values. For a user who never chose a Markdown
app, Windows itself opens the only recommended handler, which is then TigerMarkView. Do not add a
default association.

Neither .NET nor WebView2 is bundled. Both are declared TigerSetup dependencies: detected first, and a
missing one is acquired from its vendor and installed before the product (a quiet per-user install
fails with `dependency_requires_elevation` rather than prompting). Debug symbols and XML documentation
are excluded from the installed files.

TigerMarkView is an application repository. It publishes one GUI+CLI installer, not NuGet packages,
a separate CLI installer, or a portable application ZIP. A release carries five assets: TigerSetup's
four - the installer, `TigerMarkView-<version>-WinGet.zip` packed from the sealed submission set (never
regenerated; `release-artifacts.json` records its hash and the set's submission digest),
`SHA256SUMS.txt`, and `release-artifacts.json` - plus `PRIVACY.md`, the commit's `docs/PRIVACY.md`
frozen byte for byte (kind `PrivacyStatement` in both records, proven equal to the commit's blob and to
the installer's `Docs\PRIVACY.md`; `.gitattributes` pins the file to LF so checkouts reproduce those
bytes). Releases up to 0.10.0 keep their published three assets;
`Test-TigerMarkViewReleasePredatesWinGetArchive` is that one historic boundary, and 0.11.0, 0.11.1 and
0.12.0 were never published. Release notes link the release's `PRIVACY.md` asset, which the notes gate requires. Public documentation remains `README.md` plus `docs/`;
do not introduce DocFX, generated API docs, or an API-documentation site. TigerMarkView's completed
release/WinGet workflow is the reference model for future Tiger projects. The durable maintainer
lifecycle is in `docs/maintainers/releasing-tigermarkview.md` and the artifact and submission rules
are in `docs/maintainers/winget-tigermarkview.md`. Those two documents are the contract; the release
automation they describe is implemented.

Automation is verified where it runs. Normal CI stays lightweight: restore, build at zero warnings,
`dotnet test`, the `Repository`-scope engineering suites, and `git diff --check`. GitHub workflows
stay thin and declarative: a step is one call into an `eng/` or `installer/` script that a maintainer
can read and run locally, never a block of logic that only ever executes on a runner. The release
workflow carries only intrinsically CI-bound work - the authoritative build, the static installer
check, WinGet generation and sealing, the draft release, and the human publication handoff - and
post-release WinGet submission stays one local maintainer command. It reruns no test suite (the CI
run it requires already tested that commit) and needs no WinGet client: TigerSetup generates the
manifests, and `winget validate` and the TigerWinLab lab rows run on the sealed set after the draft. Do not add CI behaviour that exists only to
simulate the local submission state machine, and do not give a runner a Git identity or otherwise
patch a fixture so a maintainer-environment suite passes there; move the suite instead.

The human decides when to publish. Automation may prepare release changes and, after publication,
prepare, commit, and push the exact WinGet submission branch. It must never commit/push the source
release preparation, publish the GitHub draft, or create the final `microsoft/winget-pkgs` pull
request. Any stage after a required human action must prove that exact action occurred before
mutation: expected commit on `origin/main`, successful CI and release runs for that commit, public
non-draft release, authenticated/authorized `gh` session, or safe expected `winget-pkgs` repository
state as applicable. Missing or ambiguous state stops loudly; it is never inferred or silently
repaired. Human checkpoints end with explicit `READY FOR HUMAN ACTION` instructions.

The authoritative WinGet submission set for a published release is the release workflow's sealed
`TigerMarkView-WinGet-<version>-<commit>` artifact, and nothing else.
`Prepare-TigerMarkViewWinGet.ps1` wraps `tiger-setup winget prepare` and `finalize` with the pinned builder;
run locally it generates into `artifacts\winget\`, and that output hashes a local installer and must
never be submitted or validated as a release's set.
`eng/winget/WinGetReleaseValidation.ps1` owns the post-release gate as a callable function: it
resolves the release tag to a commit, downloads that commit's artifact, verifies it against the digest
GitHub recorded, extracts it to `artifacts\winget-release\<version>\submission\`, checks the public
installer, regenerates for comparison only, runs `winget validate`, and runs TigerWinLab. It must not
read `artifacts\winget\`, and it must fail rather than fall back when the artifact cannot be
retrieved. Regeneration stays a throwaway byte-for-byte reproducibility comparison and never replaces
the sealed set. `Test-TigerMarkViewWinGet.ps1` is the thin command around that function; the
submission orchestrator calls the function directly and requires its full result, lab included.

A retained sealed set may be reused only while its recorded provenance still binds it to what GitHub
says now: version, tag, release commit, artifact name and id, GitHub's recorded artifact digest, the
retained archive's hash, and the extracted set's submission digest. Any changed binding re-downloads.

`eng/winget/Prepare-TigerMarkViewWinGetSubmission.ps1` is the single post-release command, and
`eng/winget/WinGetPkgsSubmission.ps1` is the guarded mutation behind it. It manages only the dedicated
`C:\Projects\winget-pkgs-TigerMarkView\` clone, creating it only when its path is absent and never
adopting an existing directory. It verifies the fork/upstream identities, `master`, clean and
operation-safe state, and the latest project-specific TigerMarkView PR before any sync or submission
mutation. Open and draft matching PRs block; merged and manually closed PRs do not. After guarded
fork synchronization it copies only the sealed bytes, validates the destination and the exact final
diff, commits, pushes, and hands PR creation to the human. Local generation is never an authority or
fallback.

Only fast-forward and additive Git operations are authorized there. No reset, force push, branch
deletion, or history rewrite: fork-only commits, a branch based on something other than current
`upstream/master`, and a remote branch at a different commit each stop the run with evidence. Every
step is absent, already correct, or conflicting, so a second complete run makes no new commit and no
new push and still ends at the same pull-request handoff. `-PlanOnly` runs the read-only gates and can
never report a submission `PASS`. Only the requested version's manifest directory may carry leftover
worktree changes from an interrupted run; anything else outside it must be clean.

Local GitHub operations use a verified `gh auth login`/`gh auth status` session. Do not design routine
PAT entry/export, token arguments or logging, arbitrary credential-store reads, or unrelated
credential fallbacks. Actions jobs use scoped `GITHUB_TOKEN` permissions, with the minimum permission
each job needs. GitHub's generic generated notes alone are insufficient: 0.8.1 produced only a Full
Changelog link, so release preparation/workflow automation must supply useful version-specific notes.

`eng/release-automation/ReleaseAutomation.ps1` is the shared vocabulary for release automation: the
`PASS`/`WARN`/`BLOCKED`/`FAIL`/`READY FOR HUMAN ACTION` result objects with one text/Markdown/JSON
renderer, the fixed repository/workflow/asset constants, an injectable `gh`-only CLI adapter that
takes no token input, the `gh` session preflight, exact-SHA workflow-run selection, annotated-tag
dereference, and published release-state inspection. New release scripts compose these rather than
scraping `gh` output or adding a second query path. Version-specific notes live in
`.github/release-notes/<version>.md`; `eng/release-automation/Assert-ReleaseNotes.ps1` gates them for
a real summary with no placeholder text, bare changelog link, or leaked secret/path, and
`Publish-GitHubDraftRelease.ps1` passes the file to `gh release create --notes-file`. Version
preparation touches only `Version.props` and the release-workflow dispatch default
(`eng/release-automation/Set-TigerMarkViewReleaseVersion.ps1`); no shipped `src/` or `installer/`
source may hardcode the version. `Assert-ReleaseCommitReady.ps1` is the release workflow's
one pre-build gate - version, notes, commit on `origin/main`, that commit's successful `CI` push run,
and an unused release tag - and `Publish-GitHubDraftRelease.ps1` writes the `READY FOR HUMAN ACTION`
handoff itself, so neither check nor handoff is expressed in YAML.

The dedicated-clone path, fork/upstream slugs, default branch, and submission branch prefix are
configured in `eng/winget/winget-pkgs.clone.json` (an explicit value, not TigerAiCore discovery; only
the path is overridable, with `-ClonePath`). `eng/winget/WinGetPkgsClone.ps1` holds the read-only
safety layer - config validation, canonical GitHub-slug comparison, interrupted-operation detection,
clone-identity checks, and the project-specific previous-PR gate - that must all pass before any
fetch, synchronization, branch, copy, commit, or push. Clone identity is judged on the URL a remote
declares (`git config --get remote.<name>.url`), because `git remote get-url` returns it after
`url.<base>.insteadOf` rewriting; any difference between the two is reported separately rather than
hidden behind whichever one was read. `Invoke-TigerCloneGit` is the one way this repository invokes
git against that clone.

### Pull requests

Keep each commit cohesive and avoid bundling unrelated cleanup. Pull requests should explain the
user-visible change, identify affected projects, link relevant issues, and report test
commands/results. Include screenshots for Avalonia UI changes and sample output for rendering, PDF, or
CLI changes. Update `README.md` and `docs/HELP.md` when public or shipped behaviour changes, and keep
durable architecture guidance in this file or close to the relevant code.
