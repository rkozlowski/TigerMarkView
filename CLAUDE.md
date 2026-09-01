---
TigerAiCore.version: 1.2.0
---

# Claude instructions

<!-- TigerAiCore:begin version="1.2.0" sha256="af7b883b13d1faaab83b76e41a2c18bffea68c77b43f1a90bf6f063460758630" -->
## TigerAiCore inherited rules (Claude)

<!-- Managed content. Author these rules in CLAUDE.core.md in the TigerAiCore repository, never in a project copy. -->

@AGENTS.md

Claude Code imports `AGENTS.md` through the line above. The bootstrap, the
inherited TigerAiCore rules, and the project-specific instructions live there
and are not repeated here.

- Keep only Claude-specific behavior or constraints in `CLAUDE.md`, below this
  managed block.
- `CLAUDE.md` carries its own `TigerAiCore.version` front matter and is
  synchronized from `CLAUDE.core.md` by the same tool that synchronizes
  `AGENTS.md`.
- If `AGENTS.md` is missing or its managed block is stale, fix that first;
  Claude-specific rules never substitute for the shared rules.
<!-- TigerAiCore:end -->

## Project-specific instructions

TigerMarkView's own engineering, product, rendering, packaging, and release
constraints live in `AGENTS.md`. Do not duplicate them here.
