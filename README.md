# Glossary Extension for Quarto

This extension provides a shortcode for defining terms and building glossaries
in [Quarto](https://quarto.org). Mark terms in your text to show a popup
definition in HTML (or a link or footnote in PDF and Word), reuse a definition
as text, and list your whole glossary as a table or definition list, in any
output format.

It is a fork of [debruine/quarto-glossary](https://github.com/debruine/quarto-glossary)
with support for PDF and Word, grouped glossary files, aliases and glossary
tables. See [NEWS.md](NEWS.md) for what changed and for the breaking changes
from 1.0.0.

## Installing

```sh
quarto add MitchellAcoustics/quarto-glossary
```

This installs the extension under `_extensions/`. If you use version control,
check that folder in. It needs Quarto 1.4.0 or later and has been tested on
Quarto 1.9. To install a specific release, add a tag:
`quarto add MitchellAcoustics/quarto-glossary@v2.0.0`.

## Quick start

1. Write definitions in a YAML file, using Markdown for paragraphs, links and
   lists. Nest terms under group names if you like.

   ```yaml
   Hypothesis testing:
     alpha:
       definition: |
         The threshold chosen in Neyman-Pearson hypothesis testing...
       aliases: [alpha level, significance level]
     p-value: |
       The probability of the observed data, or more extreme data, if the null
       hypothesis is true.
   ```

2. Set defaults in your document's YAML header, or in `_quarto.yml` for a book
   or website.

   ```yaml
   glossary:
     path: glossary.yml
     popup: click
     link: "#sec-glossary"
   ```

3. Use terms in your text, and add a glossary page.

   ```markdown
   The {{< glossary p-value >}} is compared with {{< glossary alpha >}}.

   {{< glossary table=true >}}
   ```

## Options

Options can be set under `glossary:` in a YAML header or `_quarto.yml`, or on any
single shortcode, where they override the defaults.

| Option | Values | What it does |
|---|---|---|
| `path` | file path (default `glossary.yml`) | The glossary file. |
| `popup` | `"hover"` (default), `"click"`, `"none"` | HTML only. Hover uses the browser's tooltip; click shows a styled popup. |
| `display` | text | Show different text from the term. |
| `def` | text | Use this definition instead of the file's. |
| `link` | `"#section"` | Non-HTML formats: link every term to this section. |
| `nonhtml` | `"text"`, `"link"`, `"footnote"` | Non-HTML formats: plain text, a link to `link`, or the definition as a footnote on the term's first use. Default is `"link"` if `link` is set, otherwise `"text"`. |
| `definition` | `true` | Insert the term's definition as text, in any format. |
| `table` | `true` | Insert the glossary as a table (or list). |
| `groups` | `"A, B, ungrouped"` | With `table`: only these groups. `ungrouped` selects terms not in any group. |
| `layout` | `"grouped"` (default), `"flat"`, `"list"` | With `table`: a band per group, one table with no bands, or definition lists. |
| `sort` | `"file"` (default), `"alpha"` | With `table`: file order, or alphabetical (group names first, then terms within each group). |

The documentation site (source in [index.qmd](index.qmd)) has an example of each.

### Glossary file rules

* An entry is either `term: definition`, or a mapping with a `definition` and
  optional `aliases`. A mapping without a `definition` is a group, so
  `definition` and `aliases` can't be used as term names.
* Only one level of grouping is supported.
* Terms are looked up by name alone, across all groups. If a name is defined
  twice, the first definition in the file is used, with a warning if the wording
  differs. An alias never replaces another term or alias.
* The reserved group name `ungrouped` selects terms that aren't under any group.

## Styling tables

**HTML.** Glossary tables use your theme's table style (Bootstrap's
`table-striped`), and each group's band row has the class `glossary-group`.
Restyle the band with CSS variables:

```css
:root {
  --glossary-group-bg: #c9ded9;
  --glossary-group-color: #003d2f;
}
```

**PDF.** Group bands are shaded with the `glossarygroup` colour (light grey by
default). Shading needs xcolor's `table` option, which you can turn on for any
Quarto PDF with:

```yaml
format:
  pdf:
    classoption: [table]
```

Without it the document still builds, and the bands are just unshaded. To change
the colour, add this to `include-in-header`:

```latex
\colorlet{glossarygroup}{gray!25}
```

The extension doesn't stripe or pad table rows in PDF, because that would affect
every table in your document. If you want zebra striping like the HTML tables,
add this to `include-in-header` as well. It styles every table in the document
(stripes, an unshaded header, row padding and tight lists in cells), and it needs
`classoption: [table]` from above.

```latex
\usepackage{etoolbox}
\usepackage{booktabs}
\usepackage{enumitem}
\AtBeginEnvironment{longtable}{%
  \rowcolors{1}{white}{gray!12}%
  \let\LTorigtoprule\toprule
  \let\LTorigmidrule\midrule
  \def\toprule{\LTorigtoprule\hiderowcolors}%
  \def\midrule{\LTorigmidrule\showrowcolors}%
  \setlength{\aboverulesep}{0pt}%
  \setlength{\belowrulesep}{0pt}%
  \renewcommand{\arraystretch}{1.5}%
  \setlist[itemize]{nosep, leftmargin=1.2em, after=\vspace{0.5\baselineskip}}%
}
% Row colours are global: switch them off after each table, or they would shade
% later alignments such as the rows of `cases` in equations.
\AtEndEnvironment{longtable}{\hiderowcolors}
```

## Upstream issues addressed

This fork resolves these [issues in the original repository](https://github.com/debruine/quarto-glossary/issues):

* #1 Alphabetise table: `sort="alpha"`.
* #2 Keep term case from YAML: tables use the term as written.
* #3 Display Markdown in table: tables are native, with Markdown definitions.
* #4 Make it work for PDFs: terms, definitions and tables work in PDF and Word.
* #5 and #10 Global glossary and a glossary page: `table=true` lists the whole file.
* #7 Show table as a definition list: `layout="list"`.
* #8 Document the `show` option: it did nothing, so it is removed.
* #11 Alternative terms with the same meaning: aliases.

Not addressed yet: an accessible click popover (#6, #12; see the
[maehr/quarto-glossary](https://github.com/maehr/quarto-glossary) fork for a
WCAG 2.2 implementation) and an `<abbr>` syntax (#9).

## Credits and licence

Originally written by [Lisa DeBruine](https://github.com/debruine). The idea of
footnoting a term's definition in non-HTML formats comes from
[maehr/quarto-glossary](https://github.com/maehr/quarto-glossary). Released under
the MIT licence; see [LICENSE.md](LICENSE.md).

To build the documentation site, run `quarto render`; it is written to `docs/`.
