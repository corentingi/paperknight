# ADR-0017: The emoji font added to KOReader's UI fallbacks at runtime

- Date: 2026-10-15
- Status: accepted

## Context
Lichess studies often contain emojis, which KOReader's UI fonts don't have:
they show as empty boxes. A monochrome Noto Emoji font, when installed,
renders them if it is among KOReader's UI fallback fonts (`Font.fallbacks`).
CLAUDE.md forbids patching KOReader globals; KOReader has no per-plugin way
to add a fallback font.

## Options
### A. Ask the user to add it (Settings → Device → Additional UI fallback fonts)
- Pros: no global touched.
- Cons: a hidden setting few users find; emojis stay boxes meanwhile.

### B. Write the user's setting (`font_ui_fallbacks`) for them
- Pros: KOReader's own mechanism.
- Cons: changes the user's settings behind their back, permanently.

### C. Extend `Font.fallbacks` at runtime, carefully
- Pros: emojis work as soon as the font is installed; the user's settings
  are untouched; nothing persists.
- Cons: a process-wide change, also seen by the reader's UI (harmless: one
  more fallback after the user's).

## Decision
C, as a documented exception to "never patch globals": once per process,
only for a monochrome Noto Emoji file, at KOReader's insertion point for
additional fallbacks, and not when the user's additional fallbacks already
reach KOReader's limit (`additional_fallback_max_nb`). Cached face
fallbacks are reset so open faces see it (`pkfonts.lua`).

## Consequences
- Revisit if KOReader gains a plugin API for fallback fonts.
