# Translations

Paperknight follows KOReader's language (*Settings → Language* in
KOReader, then a restart). It ships French; any other language shows in
English.

## How it works

KOReader translates only the strings of its own catalogue, which has none
of a plugin's. So the plugin's modules take `_` from `pkgettext.lua`
instead of KOReader's `gettext`: a string is looked up in the plugin's
catalogue for the current language (`l10n/<lang>.po`, read on first use;
`fr_CA` falls back to `fr`), then in KOReader's catalogue (common words
such as *Cancel*), else shown as written. `_meta.lua` keeps KOReader's
`gettext`: KOReader reads it before the plugin's modules can load.

The catalogues are plain `.po` files (msgid / msgstr, no plurals or
contexts: the plugin uses none), read by a small parser in
`pkgettext.lua`.

## Adding or updating a language

    python3 tools/l10n/l10n.py extract   # build/l10n/paperknight.pot: every string, where it is used
    python3 tools/l10n/l10n.py check     # every catalogue (part of make lint)

1. Copy the template to `plugin/paperknight.koplugin/l10n/<lang>.po`
   (KOReader's code for the language: `de`, `es`, `pt_BR`…), or open the
   existing catalogue.
2. Fill in the `msgstr` lines. Keep the placeholders (`%1`, `%2`…) and the
   line breaks (`\n`); the order of the placeholders may change.
   To add several at once: `python3 tools/l10n/merge.py <lang> new.tsv`
   (one `msgid<TAB>msgstr` a line, `\n` for a line break).
3. Run the check: it fails on a broken file, a placeholder lost or added,
   or an entry the code no longer has, and lists what is not translated
   yet (shown in English, not an error).

In the code, mark every string a user reads with `_("...")`, a literal
string (the extractor reads the calls, not variables); templates with
`T(_("%1 to move."), side)`, never by concatenating translated pieces.

French follows the usual typography: a no-break space before `:`, `?`,
`!` and `%`.
