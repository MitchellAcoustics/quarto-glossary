-- Glossary.lua
-- Author: Lisa DeBruine

-- Helper Functions

local function addHTMLDeps()
  -- add the HTML requirements for the library used
    quarto.doc.add_html_dependency({
    name = 'glossary',
    stylesheets = {'glossary.css'}
  })
end

local function kwExists(kwargs, keyword)
    for key, value in pairs(kwargs) do
        if key == keyword then
            return true
        end
    end
    return false
end

-- Warnings already shown, so a problem with the glossary file is reported once
-- per render rather than on every shortcode that reads it.
local warned = {}
local function warnOnce(key, message)
  if not warned[key] then
    warned[key] = true
    quarto.log.warning("glossary: " .. message)
  end
end

---Escape text for use in HTML attribute values and element content, so a
---definition or display text containing quotes, `<` or `&` can't break out of
---the popup markup.
local function escapeHtml(text)
  return (text:gsub("[&<>\"']", {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;",
  }))
end

---Return the line number where `key` is defined in the glossary text, so
---entries can keep their file order (pandoc's metadata reader does not).
local function keyLine(lines, key)
  for i, line in ipairs(lines) do
    local text = line:gsub("^%s+", "")
    for _, form in ipairs({key, '"' .. key .. '"', "'" .. key .. "'"}) do
      if text:sub(1, #form + 1) == form .. ":" then
        return i
      end
    end
  end
  return math.huge
end

---Return `entries` (a {key: value} table) as a list of {key, value} pairs in
---file order.
local function inFileOrder(entries, lines)
  local items = {}
  for key, value in pairs(entries) do
    table.insert(items, {key = key, value = value, line = keyLine(lines, key)})
  end
  table.sort(items, function(a, b) return a.line < b.line end)
  return items
end

---Turn a raw glossary item into an entry {key, value = the definition,
---aliases = list of strings, line}. An item is either a plain definition or a
---mapping with a `definition` key and optionally `aliases` (other names for the
---same term). A mapping without `definition` is a group, not an entry.
local function asEntry(item)
  local entry = {key = item.key, value = item.value, aliases = {}, line = item.line}
  if pandoc.utils.type(item.value) == "table" and item.value.definition ~= nil then
    entry.value = item.value.definition
    local aliases = item.value.aliases
    if pandoc.utils.type(aliases) == "List" then
      for _, alias in ipairs(aliases) do
        table.insert(entry.aliases, pandoc.utils.stringify(alias))
      end
    elseif aliases ~= nil then
      table.insert(entry.aliases, pandoc.utils.stringify(aliases))
    end
  end
  return entry
end

---Whether a raw glossary item is a group (a mapping without `definition`).
local function isGroup(item)
  return pandoc.utils.type(item.value) == "table" and item.value.definition == nil
end

---Read the glossary file as a list of groups in file order, each
---{name = group name, or nil for ungrouped terms, entries = {entry}} (see
---asEntry).
local function loadGlossaryGroups(path)
  local metafile = io.open(path, 'r')
  local text = metafile:read("*a")
  metafile:close()
  local lines = pandoc.List()
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines:insert(line)
  end

  local groups = {}
  local ungrouped = {}
  for _, item in ipairs(inFileOrder(pandoc.read("---\n" .. text .. "\n---\n", "markdown").meta, lines)) do
    if isGroup(item) then
      local entries = {}
      for _, inner in ipairs(inFileOrder(item.value, lines)) do
        if isGroup(inner) then
          warnOnce("nested\0" .. path .. "\0" .. item.key .. "\0" .. inner.key,
            "'" .. inner.key .. "' in group '" .. item.key .. "' in " .. path
            .. " has no `definition`, so it looks like a nested group; only one level of grouping is supported")
        end
        table.insert(entries, asEntry(inner))
      end
      table.insert(groups, {name = item.key, entries = entries})
    else
      table.insert(ungrouped, asEntry(item))
    end
  end
  if #ungrouped > 0 then
    table.insert(groups, 1, {name = nil, entries = ungrouped})
  end
  return groups
end

---Read the glossary file into a {lowercased name: definition} table.
---Entries may be grouped under group names (see glossaryTable); group names are
---not themselves terms. Lookups are by name alone, so if a term appears in more
---than one group, the first definition in the file wins. An entry's aliases
---look up its definition too, but never replace another entry's name. Also
---returns a {lowercased name: entry} table, so a name can be mapped back to its
---canonical term.
local function loadGlossary(path)
  local glossary = {}
  local owner = {}
  local groups = loadGlossaryGroups(path)

  for _, group in ipairs(groups) do
    for _, entry in ipairs(group.entries) do
      local term = string.lower(entry.key)
      if glossary[term] == nil then
        glossary[term] = entry.value
        owner[term] = entry
      elseif pandoc.utils.stringify(glossary[term]) ~= pandoc.utils.stringify(entry.value) then
        warnOnce("dup\0" .. path .. "\0" .. term, "'" .. entry.key .. "' is defined more than once in "
          .. path .. " with different wording; popups and definition=true use the first")
      end
    end
  end

  for _, group in ipairs(groups) do
    for _, entry in ipairs(group.entries) do
      for _, alias in ipairs(entry.aliases) do
        local name = string.lower(alias)
        if glossary[name] == nil then
          glossary[name] = entry.value
          owner[name] = entry
        elseif owner[name] ~= entry then
          warnOnce("alias\0" .. path .. "\0" .. name, "the alias '" .. alias .. "' of '" .. entry.key .. "' in " .. path
            .. " is already used by '" .. owner[name].key .. "', which is kept")
        end
      end
    end
  end
  return glossary, owner
end

-- Terms that already have a footnote in this document (nonhtml="footnote"), so
-- only a term's first use gets one, under any of its aliases. Each file of a
-- book is its own document.
local footnoted = {}
-- Whether the missing-`link` warning for nonhtml="link" has been shown.
local warnedNoLink = false

---Convert a glossary definition (metadata value) to blocks for a table cell.
local function toBlocks(value)
  local kind = pandoc.utils.type(value)
  if kind == "Blocks" then
    return value
  elseif kind == "Inlines" then
    return pandoc.Blocks({pandoc.Plain(value)})
  end
  return pandoc.Blocks({pandoc.Plain(pandoc.Inlines(pandoc.utils.stringify(value)))})
end

local function cell(blocks, colspan, attr)
  return pandoc.Cell(blocks, pandoc.AlignDefault, 1, colspan or 1, attr or pandoc.Attr())
end

-- Name that selects terms not under any group, e.g. groups="ungrouped, Platform".
local UNGROUPED = "ungrouped"

---Sort a list of items in place, case-insensitively, by the field `key`.
local function sortAlpha(items, key)
  table.sort(items, function(a, b) return string.lower(a[key]) < string.lower(b[key]) end)
end

---Return the glossary's groups, limited to `only` (a set of lowercased group
---names, or nil for all) and sorted alphabetically if `alpha` is true:
---group names first, then the terms within each group. Ungrouped terms stay
---first, ahead of any named group.
local function selectGroups(path, only, alpha)
  local selected = {}
  for _, group in ipairs(loadGlossaryGroups(path)) do
    local name = group.name and string.lower(group.name) or UNGROUPED
    if only == nil or only[name] then
      table.insert(selected, {name = group.name, entries = {table.unpack(group.entries)}})
    end
  end
  if alpha then
    local first = selected[1] and selected[1].name == nil and table.remove(selected, 1)
    sortAlpha(selected, "name")
    if first then table.insert(selected, 1, first) end
    for _, group in ipairs(selected) do sortAlpha(group.entries, "key") end
  end
  return selected
end

---Return the line "Also: alias, alias" in smaller text as inlines, or nil if
---the entry has no aliases. The `glossary-aliases` class styles it in HTML (see
---glossary.css); in LaTeX it is set in \small, and in other formats it is just
---emphasised.
local function aliasLine(entry)
  if #entry.aliases == 0 then return nil end
  return pandoc.Inlines({
    pandoc.RawInline("latex", "{\\small "),
    pandoc.Span(
      {pandoc.Emph(pandoc.Inlines("Also: " .. table.concat(entry.aliases, ", ")))},
      pandoc.Attr("", {"glossary-aliases"})),
    pandoc.RawInline("latex", "}"),
  })
end

local function termRow(entry, keepWithPrevious)
  local term = pandoc.Inlines({pandoc.Strong(entry.key)})
  local aliases = aliasLine(entry)
  if aliases ~= nil then
    -- In a LaTeX table a LineBreak makes pandoc wrap the cell in a minipage,
    -- which would hide the \nopagebreak that has to open the row (see below),
    -- so use a raw \newline there.
    term:insert(quarto.doc.isFormat("latex") and pandoc.RawInline("latex", "\\newline ")
      or pandoc.LineBreak())
    term:extend(aliases)
  end
  if keepWithPrevious then
    -- \nopagebreak is a \noalign, so it must open the row after the band.
    term:insert(1, pandoc.RawInline("latex", "\\nopagebreak"))
  end
  return pandoc.Row({cell({pandoc.Plain(term)}), cell(toBlocks(entry.value))})
end

local function tableBody(rows)
  return {attr = pandoc.Attr(), body = rows, head = {}, row_head_columns = 0}
end

---Build the glossary as one table. `only` optionally limits it to a set of
---lowercased group names. With `layout` "grouped", each group gets a
---full-width band row naming it (ungrouped terms come first, with no band);
---with "flat", the selected terms are listed together with no bands. `alpha`
---sorts alphabetically instead of keeping file order.
---
---In the PDF the band is shaded with the `glossarygroup` colour (override it
---with \colorlet{glossarygroup}{...} in the document header), xcolor's row
---counter is reset so zebra striping restarts below each band, and longtable's
---\nopagebreak keeps each band with its first entry. These need xcolor's
---`table` option; without it the band is simply unshaded. In HTML the band
---gets the `glossary-group` class (styled in glossary.css), and each group is
---its own <tbody> so Bootstrap's striping restarts after every band.
local function glossaryTable(path, only, layout, alpha)
  local bandLatex = "\\ifdefined\\cellcolor\\cellcolor{glossarygroup}\\fi"
    .. "\\ifdefined\\rownum\\global\\rownum=2\\relax\\fi"
  local groups = selectGroups(path, only, alpha)

  local bodies = {}
  if layout == "flat" then
    local entries = {}
    for _, group in ipairs(groups) do
      for _, entry in ipairs(group.entries) do table.insert(entries, entry) end
    end
    if alpha then sortAlpha(entries, "key") end
    local rows = {}
    for _, entry in ipairs(entries) do table.insert(rows, termRow(entry, false)) end
    table.insert(bodies, tableBody(rows))
  else
    for _, group in ipairs(groups) do
      local rows = {}
      if group.name ~= nil then
        local band = pandoc.Plain({pandoc.RawInline("latex", bandLatex), pandoc.Strong(group.name)})
        table.insert(rows, pandoc.Row({cell({band}, 2, pandoc.Attr("", {"glossary-group"}))}))
      end
      for i, entry in ipairs(group.entries) do
        table.insert(rows, termRow(entry, i == 1 and group.name ~= nil))
      end
      table.insert(bodies, tableBody(rows))
    end
  end

  local head = pandoc.TableHead({pandoc.Row({
    cell({pandoc.Plain({pandoc.Strong("Term")})}),
    cell({pandoc.Plain({pandoc.Strong("Definition")})}),
  })})
  return pandoc.Table(
    pandoc.Caption(),
    {{pandoc.AlignDefault, 0.3}, {pandoc.AlignDefault, 0.7}},
    head,
    bodies,
    pandoc.TableFoot(),
    pandoc.Attr("", {"striped", "glossary-table"})
  )
end

---Build the glossary as definition lists, one per group, with the group name
---as a bold line above it (no label for ungrouped terms, which come first).
---`only` and `alpha` work as they do for glossaryTable. Group labels are
---paragraphs rather than headings so they don't add entries to the table of
---contents. In the PDF, \nopagebreak keeps a label with its list.
local function glossaryList(path, only, alpha)
  local blocks = pandoc.Blocks({})
  for _, group in ipairs(selectGroups(path, only, alpha)) do
    local items = {}
    for _, entry in ipairs(group.entries) do
      -- The aliases go at the start of the definition: a line break inside a
      -- LaTeX description label is lost, which would run them into the term.
      local definition = pandoc.Blocks({})
      local aliases = aliasLine(entry)
      if aliases ~= nil then definition:insert(pandoc.Plain(aliases)) end
      definition:extend(toBlocks(entry.value))
      table.insert(items, {pandoc.Inlines(entry.key), {definition}})
    end
    local content = pandoc.Blocks({})
    if group.name ~= nil then
      content:insert(pandoc.Para({pandoc.Strong(group.name)}))
      content:insert(pandoc.RawBlock("latex", "\\nopagebreak[4]"))
    end
    content:insert(pandoc.DefinitionList(items))
    blocks:insert(pandoc.Div(content, pandoc.Attr("", {"glossary-list"})))
  end
  return blocks
end

---Merge user provided options with defaults
---@param userOptions table
local function mergeOptions(userOptions, meta)
  local defaultOptions = {
    path = "glossary.yml",
    popup = "hover"
  }

  -- override with meta values first
  if meta.glossary ~= nil then
    for k, v in pairs(meta.glossary) do
      local value = pandoc.utils.stringify(v)
      if value == 'true' then value = true end
      if value == 'false' then value = false end
      defaultOptions[k] = value
    end
  end

  -- then override with function keyword values
  if userOptions ~= nil then
    for k, v in pairs(userOptions) do
      local value = pandoc.utils.stringify(v)
      if value == 'true' then value = true end
      if value == 'false' then value = false end
      defaultOptions[k] = value
    end
  end

  return defaultOptions
end


-- Main Glossary Function Shortcode

return {

["glossary"] = function(args, kwargs, meta)

  -- definition mode (all formats): return the term's definition from the
  -- glossary file as inline text, so chapters can reuse the glossary wording
  if kwExists(kwargs, "definition") then
    local options = mergeOptions(kwargs, meta)
    local term = string.lower(pandoc.utils.stringify(args[1]))
    local value = loadGlossary(options.path)[term]
    if value ~= nil then
      if pandoc.utils.type(value) == "Blocks" then
        return pandoc.utils.blocks_to_inlines(value)
      end
      return value
    end
    quarto.log.warning("glossary: no definition found for '" .. term .. "'")
    return pandoc.Inlines({})
  end

  -- table mode (all formats): the whole glossary file as one table. Options:
  --   groups="Platform, ungrouped"  only these groups ("ungrouped" selects
  --                                 terms not under any group)
  --   layout="grouped" | "flat" | "list"
  --                                 band each group, list terms together with
  --                                 no bands, or use definition lists with the
  --                                 group names as labels
  --   sort="file" | "alpha"         file order, or alphabetical (group names
  --                                 first, then terms within each group)
  if kwExists(kwargs, "table") then
    local options = mergeOptions(kwargs, meta)
    local layout = options.layout or "grouped"
    local sort = options.sort or "file"
    if layout ~= "grouped" and layout ~= "flat" and layout ~= "list" then
      quarto.log.warning("glossary: layout should be 'grouped', 'flat' or 'list', not '" .. layout .. "'")
      layout = "grouped"
    end
    if sort ~= "file" and sort ~= "alpha" then
      quarto.log.warning("glossary: sort should be 'file' or 'alpha', not '" .. sort .. "'")
      sort = "file"
    end

    local only = nil
    if options.groups ~= nil then
      local known = {[UNGROUPED] = true}
      for _, group in ipairs(loadGlossaryGroups(options.path)) do
        if group.name ~= nil then
          if string.lower(group.name) == UNGROUPED then
            warnOnce("ungrouped\0" .. options.path, "a group named '" .. group.name .. "' in " .. options.path
              .. " is selected together with the ungrouped terms by groups=\"" .. UNGROUPED .. "\"")
          end
          known[string.lower(group.name)] = true
        end
      end
      only = {}
      for name in options.groups:gmatch("[^,]+") do
        name = string.lower(name:match("^%s*(.-)%s*$"))
        if not known[name] then
          warnOnce("nogroup\0" .. options.path .. "\0" .. name, "no group named '" .. name .. "' in " .. options.path)
        end
        only[name] = true
      end
    end

    if layout == "list" then
      return glossaryList(options.path, only, sort == "alpha")
    end

    if quarto.doc.isFormat("html") then
      addHTMLDeps()
    elseif quarto.doc.isFormat("latex") then
      quarto.doc.include_text("in-header",
        "\\AtBeginDocument{\\ifdefined\\providecolor\\providecolor{glossarygroup}{gray}{0.85}\\fi}")
    end
    return pandoc.Blocks({glossaryTable(options.path, only, layout, sort == "alpha")})
  end

  -- non-HTML formats (e.g. PDF, Word): no popups, so render the display text
  -- inline. How it is dressed up depends on the `nonhtml` option:
  --   "text"      the display text alone
  --   "link"      the display text linked to the section given by `link`
  --   "footnote"  the display text, with the definition as a footnote on the
  --               term's first use in the document
  -- The default is "link" if `link` is set, otherwise "text".
  if not quarto.doc.isFormat("html:js") then
    local options = mergeOptions(kwargs, meta)
    local term = string.lower(pandoc.utils.stringify(args[1]))
    local display = pandoc.utils.stringify(args[1])
    if kwExists(kwargs, "display") then
      display = pandoc.utils.stringify(kwargs.display)
    end

    local hasLink = options.link ~= nil and options.link ~= ""
    local mode = options.nonhtml
    if mode == nil then
      mode = hasLink and "link" or "text"
    elseif mode ~= "text" and mode ~= "link" and mode ~= "footnote" then
      quarto.log.warning("glossary: nonhtml should be 'text', 'link' or 'footnote', not '" .. tostring(mode) .. "'")
      mode = hasLink and "link" or "text"
    end

    local text = pandoc.Inlines(display)
    if mode == "link" then
      if hasLink then
        return pandoc.Link(text, options.link)
      elseif not warnedNoLink then
        warnedNoLink = true
        quarto.log.warning("glossary: nonhtml='link' needs a `link` option; showing plain text")
      end
    elseif mode == "footnote" then
      local blocks
      local key = term
      if kwExists(kwargs, "def") then
        blocks = pandoc.Blocks({pandoc.Plain(pandoc.Inlines(pandoc.utils.stringify(kwargs.def)))})
      else
        local glossary, owner = loadGlossary(options.path)
        if glossary[term] ~= nil then
          blocks = toBlocks(glossary[term])
          key = string.lower(owner[term].key)
        end
      end
      if blocks ~= nil and #blocks > 0 and not footnoted[key] then
        footnoted[key] = true
        text:insert(pandoc.Note(blocks))
      end
    end
    return text
  end

  addHTMLDeps()

  -- or set up in-text term
  local options = mergeOptions(kwargs, meta)

  local display = pandoc.utils.stringify(args[1])
  local term = string.lower(display)

  if kwExists(kwargs, "display") then
    display = pandoc.utils.stringify(kwargs.display)
  end

  -- get definition
  local def = ""
  if kwExists(kwargs, "def") then
    def = pandoc.utils.stringify(kwargs.def)
  else
    local glossary = loadGlossary(options.path)
    if glossary[term] ~= nil then
      def = pandoc.utils.stringify(glossary[term])
    end
  end

  def = escapeHtml(def)
  display = escapeHtml(display)

  if options.popup == "hover" then
    glosstext = "<button class='glossary' title='" .. def .."'>" .. display .. "</button>"
  elseif options.popup == "click" then
    glosstext = "<button class='glossary'><span class='def'>" .. def .."</span>" .. display .. "</button>"
  elseif options.popup == "none" then
    glosstext = "<button class='glossary'>" .. display .. "</button>"
  end

  return pandoc.RawInline("html", glosstext)

end

}
