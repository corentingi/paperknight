# ADR-0019: The in-app update runs the release's install.sh

- Date: 2026-10-24
- Status: accepted

## Context
Releases publish `install.sh` (the parts with their versions and sha256)
and one archive per part (docs/releasing.md). Updating meant opening a
terminal on the Kindle. The plugin should offer *Check for updates…*. The
work behind it (downloads, checksums, the plugin folder swapped while the
plugin runs, the install records in `koreader/paperknight/.parts`, studies
of your own kept, older installs migrated) is already in `install.sh`,
tested under busybox (`tools/dist/test-install.sh`).

## Options
### A. Re-implement the update in Lua
KOReader's socket/ssl libraries for HTTPS (with its CA bundle), sha256 and
tar in Lua or through KOReader's tools.
- Pros: no `curl -k`; no dependency on the device's shell tools.
- Cons: a second implementation of every rule of `install.sh` (records,
  migration, the swap), to keep in step and to test again; redirects to
  GitHub's asset host to handle by hand.

### B. Run install.sh from the plugin
Download the latest `install.sh` with `curl`, ask it what would change
(`--list`), show that, then run it for the parts chosen (`--yes
--parts=...`) in the background.
- Pros: one implementation of the update, already tested; the plugin only
  shows the plan and the result.
- Cons: needs `sh`, `curl`, `gzip`, `tar` on the device (there on a
  jailbroken Kindle: the installer already relies on them); `curl -k`, as
  on the command line (the sha256 baked into the installer still check the
  archives, but not the installer itself).

## Decision
B: the installer stays the single place where updating is done, and the
devices Paperknight targets have its tools.

## Consequences
- `install.sh` gains `--list` and `--parts=`; the build writes
  `update-url.txt` into the plugin (the release's `latest/download` URL).
- Stockfish is installed only when asked (a separate button), updated with
  the rest once installed; restarting KOReader loads the new plugin (the
  running code stays the old one until then).
- A device without these tools (another platform) would need option A.
