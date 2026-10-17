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

## 7. Why a grey square flickers and text does not (PW2 specifics)

Researched 2026-10-17, completing sections 1-2.

**The PW2's hardware.** The PW2 (2013) was the first e-reader with an
**E Ink Carta** panel, sold as tuned for reading with E Ink's **Regal**
waveforms (fewer full refreshes between pages). It is a "Wario" board, an
i.MX6 (Cortex-A9) with its EPD controller, driven by Amazon's `mxcfb`
driver (KOReader: `frontend/device/kindle/device.lua`). Its waveform
numbers (`ffi/mxcfb_kindle_h.lua`): DU 1, GC16 2, GC16_FAST 3, A2 4,
GL16 5, GL16_FAST 6, DU4 7, REAGL 8, REAGLD 9, GL4 10, GL16_INV 11.

**What the waveforms do with each pixel** (E Ink's mode guide):

- **GC16**: "all the pixels are updated or cleared": every pixel goes
  through black and white before its target. The flash.
- **GL16**: "the entire display except pixels staying in white will update";
  a local update for white→white pixels, a global (GC16-like, clearing)
  one for everything else. "Used to update anti-aliased text with reduced
  flash." REAGL (GLR16) and REAGLD (GLD16) use the same waveform, plus an
  algorithm against ghosting at the edges of text; on Kindles they are
  sent as **full** updates (KOReader's driver: they need it to behave).
- **DU / A2**: black or white only, no flash. **DU4**: non-flashing and
  fast, but only to four levels: 0x00, 0x55, 0xAA, 0xFF. E Ink has no
  non-flashing 16-level grey mode.
- **Update mode**: a *partial* update drives only the pixels whose value
  changed; a *full* one drives every pixel of the region with the waveform.

**So, on the PW2, with Paperknight's `[partial]` (REAGL, full update):**

| Pixel in the refreshed rectangle | What REAGL does | Seen |
|---|---|---|
| white staying white (light squares, page background) | nothing | nothing |
| black staying black (text, piece outlines) | driven again, already saturated | barely |
| black ↔ white (text of a page turn) | the transition REAGL is made for | clean |
| grey staying the same grey (dark squares 0xDD, last-move tint, night squares) | driven again through the clearing sequence | **a visible redraw of the square** |
| grey → another grey (a tint added or removed) | clearing sequence | a flicker of the square |

Text is black on white: its background is a no-op and its glyphs are few,
saturated pixels; only the anti-aliased edges are grey. A chessboard is
half mid-grey squares, so every grey square inside the rectangle, changed
or not, is driven again. That is what was seen on the device: a rectangle
from a move's squares down to the status line redrew every grey square in
between, and a long move (a1 to h8) redraws the dark squares it spans.

**Levers this leaves** (to try on the device, not measured yet):

1. *Partial update mode* instead of full: only changed pixels are driven,
   so unchanged grey squares are left alone; changed grey pixels still get
   GL16's clearing sequence. KOReader's Kindle driver always sends REAGL as
   full; GL16 (5) as partial is what it uses on the non-REAGL Kindle Touch.
2. *DU4, partial*: no flash at all and fast, if the board's greys are
   exactly 0x55/0xAA (today 0xDD and 0xAA by day): pieces' anti-aliasing
   would be quantized to four levels, and fast waveforms ghost more (the
   page flashes clear it). Whether the PW2's waveform file has DU4 is not
   known: FBInk lists it as "on some Kindles, depending on the model".
3. *Smaller REAGL regions*: one per changed square, so no unchanged square
   is inside; each REAGL update waits for the previous one, so a move
   (2 to 4 squares) takes longer.

KOReader's refresh modes do not offer GL16-partial or DU4 on the PW2; a
plugin would call the framebuffer itself (`Screen:mech_refresh(false,
waveform, x, y, w, h)`) after painting.

Sources: E Ink, *UI application guidelines: waveform modes* (via
beck-elektronik.de); epaper-components.dev, *How e-paper partial refresh
works*; FBInk CLI documentation; E Ink's Carta announcement (2013);
KOReader `ffi/framebuffer_mxcfb.lua`, `ffi/mxcfb_kindle_h.lua`.

### Experiment: DU4 board (branch `exp/du4-board`)

Lever 2 above, implemented on a branch to be judged on the PW2:

- The board uses the four DU4 levels only. Day: light squares 0xFF, dark
  0xAA, shapes 0x55. Night (shown values): light 0x55, dark 0x00, shapes
  0xAA. The frame is 0x55.
- The last move is no longer a tint: small triangles in the four corners of
  its two squares, black by day and white at night (they read on both
  square colours, and change no square's grey).
- The board's refreshes (the changed squares, the turn marker) go through
  `PkRefresh.boardRegion`: the region is rounded to the four levels in the
  framebuffer (the pieces' anti-aliased edges), then sent with
  `Screen:mech_refresh(false, DU4, ...)`, a partial update; UIManager gets a
  1-pixel refresh it discards, so it adds none of its own. Elsewhere (the
  emulator, non-Kindle devices) the usual `[partial]` is used.
- The text below the board and the page refreshes are unchanged (REAGL).
- To check on the device: whether DU4 exists in the PW2's waveform (if not,
  the driver may fall back or show nothing), the flash, the speed, the
  ghosting after a long line, and how the four-level pieces look.

## 8. Measuring

- Emulator: `h.recordRefreshes()` (e2e harness) records the refreshes sent
  to the screen, after merges and promotions; the puzzle and study scenarios
  check the rules above with it.
- Device: with KOReader's debug logging on, every update is logged as
  `mxc_update: WxH region @ (x, y) with marker M (WFM: w & UPD: u)` (waveform
  and update mode numbers, `ffi/mxcfb_kindle_h.lua`).
