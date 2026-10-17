# ADR-0018: The board is drawn in four greys and refreshed with DU4

- Date: 2026-10-17
- Status: accepted

## Context
On the PW2, each move visibly redrew the board's grey squares, even with
the non-flashing REAGL refresh (docs/eink-refresh.md §7): REAGL is sent as
a full update and drives every pixel of its region through a clearing
sequence, except white pixels staying white. A board is half mid-grey
squares, so every grey square inside a move's rectangle flickered. Text
does not have the problem (a white background and few saturated pixels).

## Options
### A. Keep REAGL, refresh each changed square apart
- Pros: no palette change.
- Cons: the changed squares still flicker; one refresh per square, each
  waiting for the previous one, makes a move slower.

### B. GL16 in partial update mode
- Pros: unchanged squares are left alone.
- Cons: a changed grey square still goes through GL16's clearing sequence.

### C. DU4 in partial update mode, the board in its four levels
- Pros: DU4 is non-flashing and fast; partial mode drives only changed
  pixels. Works in day and night mode (the four levels invert onto each
  other).
- Cons: four greys only (0x00, 0x55, 0xAA, 0xFF): no grey tint for the last
  move, pieces' anti-aliasing rounded to four levels; KOReader has no
  refresh mode for it (the framebuffer is called directly); fast waveforms
  leave more ghosting.

## Decision
C, tried on branch `exp/du4-board` and confirmed on the PW2 ("it
definitely works"). Board palette: day light 0xFF, dark 0xAA (the lightest
grey DU4 offers), shapes 0x55; night (shown) light 0x55, dark 0x00, shapes
0xAA; frame 0x55. The last move is marked by small triangles in its
squares' corners (black by day, white at night). `PkRefresh.boardRegion`
rounds the region to the four levels in the framebuffer and sends
`Screen:mech_refresh(false, DU4)`; UIManager gets a 1 px refresh it
discards. Elsewhere than on Kindles, the usual `[partial]` is used.

## Consequences
- Anything drawn on the board must use the four levels (no new grey tint):
  marks are shapes in black or white, or the 0x55/0xAA greys.
- The text below the board and page refreshes stay REAGL; the periodic
  page flash clears DU4's ghosting.
- Kindles whose waveform file lacks DU4 (other models) would need a check
  or a fallback; revisit if the plugin targets them.
