# Changelog

## 2.0.0

This version is a fork of [debruine/quarto-glossary](https://github.com/debruine/quarto-glossary)
(1.0.0). It needs Quarto 1.4.0 or later; it has been tested on Quarto 1.9.

### Breaking changes

* `{{< glossary table=true >}}` now lists **every term in the glossary file**
  (or the groups chosen with `groups=`), not just the terms used on the current
  page. Use `groups=` to list part of the glossary. The table is built in the
  glossary file's order, so use `sort="alpha"` for alphabetical order.
* The `add_to_table` option is removed, because the table no longer depends on
  which terms a page uses.
* The `show` option never did anything and is no longer documented. Existing
  configs that set it keep working; it is ignored.
* The table is a native table rather than raw HTML, so it takes its style from
  your theme (Bootstrap's `table-striped` in HTML). The old `.glossary_table`
  CSS rules are removed.

### New features

* **Non-HTML output.** Terms are no longer dropped from PDF and Word output.
  The `nonhtml` option chooses plain `"text"`, a `"link"` to the section given by
  `link`, or a `"footnote"` holding the definition on a term's first use. The
  footnote idea is from [maehr/quarto-glossary](https://github.com/maehr/quarto-glossary).
* **`definition=true`** inserts a term's definition as text, in any format.
* **Grouped glossary files.** Nest terms one level deep under group names.
* **Tables in every format**, with a shaded band per group, Markdown (including
  lists) in definitions, and options `groups`, `layout` (`"grouped"`, `"flat"` or
  `"list"`) and `sort` (`"file"` or `"alpha"`). `groups="ungrouped"` selects terms
  that aren't in a group.
* **Aliases:** other names for a term (`definition:` and `aliases:`) that look up
  the same definition and are shown as "Also: ..." in tables and lists.

### Bug fixes

* Some terms intermittently got empty popups, because the lookup table was
  modified while it was being iterated.
* A straight apostrophe in a hover definition ended the popup text early, and
  `<` or `&` in a definition or `display` text could be read as markup.
* Terms defined more than once now use the first definition, with a warning if
  the wording differs, instead of an arbitrary one.

### Issues from the original repository addressed

#1 (alphabetise the table), #2 (keep term case), #3 (Markdown in the table),
#4 (PDF output), #5 and #10 (a table of every term, for books and sites), #7
(definition lists), #8 (the undocumented `show` option) and #11 (aliases).
