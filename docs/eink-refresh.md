# E-ink refreshes: the Kindle, KOReader and Paperknight

Why a book page turns without a flicker while a chess move used to flash, and
what Paperknight does about it. Facts about KOReader come from its sources
(`ffi/framebuffer_mxcfb.lua`, `frontend/ui/uimanager.lua`,
`frontend/ui/widget/button.lua`, `frontend/device/kindle/device.lua`); the
measurements come from the desktop emulator (`h.recordRefreshes`, below).
What the panel actually looks like can only be judged on the device.

## 1. The panel in one minute

An e-ink pixel is a cell of black and white particles moved by voltage
pulses. Changing a pixel means playing a **waveform**: a sequence of pulses
that depends on the start and target grey level (16 levels on the PW2, steps
of `0x11`). The screen keeps the image without power; it only changes when
the software asks the controller (the EPDC) to update a **region**.

- **Accurate waveforms** (GC16) drive pixels through black and white before
  settling: the image is clean, but you see it **flash**. They take longest.
- **Fast waveforms** (DU, A2) only go to black or white: quick, but greys
  are lost (posterized) and they leave more **ghosting** (faint traces of the
  previous image).
- **Non-flashing grey waveforms** (GL16, and REAGL on newer Kindles) change
  greys without the black/white swing. REAGL ("regal") was designed for page
  turns: no flash, and it limits ghosting.
- **Update mode**: *partial* drives only the pixels that change; *full*
  drives every pixel of the region. With GC16 a full update is the black
  flash everyone knows; with REAGL it is not visible.

Ghosting builds up over many non-flashing updates, so readers flash once in a
while to clean the screen.

## 2. The Kindle Paperwhite 2 driver

The PW2 uses Amazon's `mxcfb` driver. KOReader sends `MXCFB_SEND_UPDATE`
requests: region, waveform, update mode, and a **marker** to wait on.

The PW2 inherits `isREAGL = yes` from KOReader's Kindle base class, so it
gets the REAGL set:

| KOReader mode | Day waveform | Night waveform | Visible flash |
|---|---|---|---|
| `a2` | A2 | A2 | no (black and white only) |
| `fast` | DU, forced monochrome | DU | no, but greys are crushed |
| `ui`, `[ui]` | GC16_FAST | GC16_FAST | flickers the pixels it changes |
| `partial`, `[partial]` | **REAGL** (always sent as a full update) | GL16_INV | no |
| `flashui` | GC16_FAST, full update | GC16, full | yes |
| `flashpartial` | REAGL, full update | GL16_INV, full update | no (REAGL, by design) |
| `full` | GC16, full update | GC16, full | yes, the whole region |

Driver details that matter for speed:

- Before a REAGL (or GC16) update, KOReader **waits for the previous update
  to complete**. Two refreshes in a row therefore run one after the other:
  one per user action is faster than two.
- Before a `ui` or flashing update it waits for the previous one to be
  submitted, and after a full update it waits for it to complete.
- Night mode is KOReader inverting the image; the driver then swaps
  waveforms (GL16_INV for partial updates, GC16 for flashes).

## 3. The native Kindle reader

The stock reader turns pages with REAGL (KOReader's Kindle driver notes that
it "mostly follows what the stock reader does": REAGL for both the black and
white and the grey history modes). The Kindle's *Page Refresh* setting adds a
full flash on every page; otherwise it flashes only now and then (images,
chapter changes).

## 4. KOReader's pipeline

1. A widget changes and calls `UIManager:setDirty(widget, mode, region)`.
   Nothing happens yet: the widget is queued for painting and the refresh
   for later (`mode` can be a function, evaluated after painting).
2. On the next loop, `UIManager:_repaint()` paints the dirty widgets into the
   framebuffer, then drains the refresh queue.
3. **Merging**: a refresh whose region touches a queued one is merged with
   it: the union of the regions, and the stronger mode
   (`a2 < fast < ui < partial < [ui] < [partial] < flashui < flashpartial < full`).
4. **Promotion**: every `partial` refresh (exactly that mode, once per
   repaint) increments a counter. Every *N*th one, *N* being the user's
   **full refresh rate** (Settings > Screen > E-ink, default 6, "never"
   possible), is promoted: to `full` when it has no region (a book page), to
   `flashui` over its region otherwise. `[partial]` is **not counted**; on
   the PW2 it is the same REAGL waveform (the "no merge" hint is not
   implemented by the Kindle driver).
5. The *Avoid flashing* setting downgrades `flashui` to `ui`, `flashpartial`
   to `partial`, and a regional `partial` to `ui` (not `[partial]`).

Defaults of KOReader widgets:

- **Button taps** (unless the *Flash buttons and menu items* setting is off):
  the button is inverted and refreshed `fast` (DU), the screen is repainted
  and KOReader pauses briefly so the highlight shows *before* the callback
  runs; then the inversion is undone (`fast`, or `ui`).
- `Button:refresh()` (after `enableDisable`, `setText`…): `fast` or `ui`.
- `TitleBar:setTitle` / `setSubTitle`: `ui` over the title bar.
- A book page turn (ReaderView): one whole-screen `partial`, so REAGL, with
  the periodic full flash.

## 5. Why a page turn did not flicker but a move did

A page turn is one REAGL refresh, plus a flash every *N* pages. A puzzle
move, measured in the emulator before the fix (refreshes actually sent to the
screen, after merges and promotions):

| Action | Refreshes sent |
|---|---|
| Tap a piece | `fast` (square inverted in black and white), `ui` (GC16_FAST: undo + selection) |
| Tap the target, then the reply | `fast` (inversion), then per update a `partial` for the board and one for the status line (2 REAGL refreshes in a row, the second waiting for the first) |
| Every few moves | one of those `partial` promoted to `flashui`: a flash over the board or status line |
| The solving move | `fast`, `ui`, `fast`, and a **whole-screen** `partial` (the new button bar had no position yet): a full black flash when the counter landed on it |
| A replay step (‹ ›) | `fast` (button inverted), status `partial`, board `partial` |

So each move showed two black-and-white square inversions (the tap
highlights), GC16_FAST flicker, two sequential refreshes, and a periodic
flash. Studies were similar: a `fast` arrow highlight and a `ui` refresh of
the unchanged title bar on every step.

## 6. Paperknight's approach

Rules, implemented in `pkrefresh.lua`, `pkbutton.lua` and the views:

1. **Steps never flash.** A move, a selection, the status line, a replay or
   study step is a `[partial]` refresh (`PkRefresh.STEP`): REAGL like a book
   page (GL16_INV at night), not counted, so never promoted to a flash.
2. **Pages flash like a book.** A new puzzle, chapter or drill line is a
   counted whole-screen `partial` (`PkRefresh.page`): every *N* pages (the
   user's full refresh rate) it becomes a full flash that clears the ghosting
   left by the steps.
3. **No tap highlight where the board is the feedback.** Board squares
   (`no_feedback` in `pkbutton.lua`; the selection border shows the tap) and
   the arrows that step through a line (`PkButton.noFeedback`): no DU
   inversion, and no forced repaint and pause before the move is handled.
4. **Tight regions, one per area.** The board collects the squares an
   update changes (pieces, last-move tint, badge, arrows and circles) into
   one rectangle (`Board.square_refresh`), refreshed once: each REAGL
   refresh waits for the previous one, so one per square would be slow. The
   text under the board (status line, study panel, buttons) is a separate
   refresh (`PkRefresh.step` from the status line, `PkRefresh.below` under
   the board). They are **never joined**: REAGL is sent as a full update and
   redraws every pixel of its region, which shows on the grey squares. Tried
   on the PW2: one rectangle from a move's squares down to the status line
   visibly redrew everything below the highest changed square.
5. **No `ui` or `fast` on grey content.** GC16_FAST flickers and DU crushes
   the grey squares. The title bar's subtitle is set without TitleBar's own
   `ui` refresh, and only when it changed (`PkRefresh.setSubTitle`).

After the fix, measured the same way:

| Action | Refreshes sent |
|---|---|
| Tap a piece | one `[partial]`, the square only |
| Tap the target, then the reply | per update, one `[partial]` around the changed squares and one for the status line |
| The solving move | the same, plus the title bar (rating) and the new button bar |
| A replay or study step | the changed squares, and the text below the board |
| Periodic flash | none during a puzzle or a line; every *N* new puzzles or chapters |

Still left as KOReader does it: the tap highlight of text buttons (Retry,
Hint, Solution, Next, Lines, Train…: a short black-and-white inversion of the
button, as a press confirmation), and menus and dialogs.

### Trade-offs and what to check on the device

- **Ghosting**: with no flash during a puzzle, traces can build up over a
  long line; REAGL limits them, and the next page flash (or a new puzzle)
  clears them. If it is too much, a flash every *K* steps could be added.
- **Long moves**: the rectangle around a move's squares (and the previous
  move's tint) can cover a large part of the board, e.g. a1 to h8; REAGL
  then redraws the unchanged squares inside it too. Refreshing each square
  apart would avoid that, but each refresh waits for the previous one.
- **User settings still apply**: a full refresh rate of "never" removes the
  page flashes; *Flash buttons and menu items* off removes the remaining
  button highlights everywhere in KOReader.

## 7. Measuring

- Emulator: `h.recordRefreshes()` (e2e harness) records the refreshes sent
  to the screen, after merges and promotions; the puzzle and study scenarios
  check the rules above with it.
- Device: with KOReader's debug logging on, every update is logged as
  `mxc_update: WxH region @ (x, y) with marker M (WFM: w & UPD: u)` (waveform
  and update mode numbers, `ffi/mxcfb_kindle_h.lua`).
