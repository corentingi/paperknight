# ADR-0015: Home screen and quick settings for navigation and screen settings

- Date: 2026-10-06
- Status: accepted

## Context
Each mode was opened from KOReader's menu (Tools > Paperknight) and closed
back to KOReader: switching mode took several taps through KOReader. The
Paperknight screens cover the display and take every touch, so KOReader's
gestures (frontlight swipe, night mode) don't work there, and there was no
way to change brightness or night mode without leaving.

## Options
### A. Open KOReader's own menu on top
- Pros: every setting, nothing to build.
- Cons: the file manager's menu (open file, cloud…) mostly doesn't apply,
  and some items act on the screen underneath.
### B. Edge swipes like KOReader (brightness)
- Pros: familiar.
- Cons: the board takes almost the full width: clashes with taps on the
  a/h files; invisible.
### C. A home screen, plus a shared quick-settings pop-up
A home screen lists the modes (with a status line) and the screen settings;
every screen's ☰ menu ends with the same quick settings (frontlight, night
mode, the other modes, Home), also opened by a tap on the screen's title.
- Pros: one tap to switch; visible; reuses KOReader's frontlight dialog and
  night mode toggle (its settings stay the source of truth).
- Cons: one more screen; the puzzle theme list is one tap deeper.

## Decision
C (pknav.lua). Modes open above the home screen, so closing one goes back
to it; switching closes the Paperknight screens above home (found by their
`paperknight_` widget name, a screen may clean up in `pk_close`). The
KOReader menu entries and the Paperknight gesture action go through it.

Amended 2026-10-16: the two menus are split. A tap on the title opens the
quick settings (frontlight, night mode, modes, Home: Paperknight as a
whole); ☰ holds only the actions of the screen shown, then one last row,
*Settings & modes…*, which opens the quick settings (one way to them, and
the gesture can be learnt from it). They used to end every ☰ menu, so the
two menus mostly offered the same things. List screens have a ☰ only when
the list has actions of its own (Studies: hide done studies; a study's
chapter list: its done mark); the home screen and the Openings list have
none.

## Consequences
- New screens must have a `paperknight_` name to be closed when switching.
- The home screen is the place for Paperknight's own settings later.
- The KOReader menu stays reachable by closing the home screen.
