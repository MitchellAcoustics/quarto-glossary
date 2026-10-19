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

---Read the glossary file as a list of groups in file order, each
---{name = group name, or nil for ungrouped terms, entries = {{key, value}}}.
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
    if pandoc.utils.type(item.value) == "table" then
      table.insert(groups, {name = item.key, entries = inFileOrder(item.value, lines)})
    else
      table.insert(ungrouped, item)
    end
  end
  if #ungrouped > 0 then
    table.insert(groups, 1, {name = nil, entries = ungrouped})
  end
  return groups
end

-- Duplicate terms already warned about, so each is reported once per render.
local warnedDuplicates = {}

---Read the glossary file into a {lowercased term: definition} table.
---Entries may be grouped under group names (see glossaryTable); group names are
---not themselves terms. Lookups are by term alone, so if a term appears in more
---than one group, the first definition in the file wins.
local function loadGlossary(path)
  local glossary = {}
  for _, group in ipairs(loadGlossaryGroups(path)) do
    for _, entry in ipairs(group.entries) do
      local term = string.lower(entry.key)
      if glossary[term] == nil then
        glossary[term] = entry.value
      elseif pandoc.utils.stringify(glossary[term]) ~= pandoc.utils.stringify(entry.value)
          and not warnedDuplicates[path .. "\0" .. term] then
        warnedDuplicates[path .. "\0" .. term] = true
        quarto.log.warning("glossary: '" .. entry.key .. "' is defined more than once in "
          .. path .. " with different wording; popups and definition=true use the first")
      end
    end
  end
  return glossary
end

-- Terms that already have a footnote in this document (nonhtml="footnote"), so
-- only a term's first use gets one. Each file of a book is its own document.
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

local function termRow(entry, keepWithPrevious)
  local term = pandoc.Inlines({pandoc.Strong(entry.key)})
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
  --   layout="grouped" | "flat"     band each group, or list terms together
  --   sort="file" | "alpha"         file order, or alphabetical (group names
  --                                 first, then terms within each group)
  if kwExists(kwargs, "table") then
    local options = mergeOptions(kwargs, meta)
    local layout = options.layout or "grouped"
    local sort = options.sort or "file"
    if layout ~= "grouped" and layout ~= "flat" then
      quarto.log.warning("glossary: layout should be 'grouped' or 'flat', not '" .. layout .. "'")
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
            quarto.log.warning("glossary: a group named '" .. group.name .. "' in " .. options.path
              .. " is selected together with the ungrouped terms by groups=\"" .. UNGROUPED .. "\"")
          end
          known[string.lower(group.name)] = true
        end
      end
      only = {}
      for name in options.groups:gmatch("[^,]+") do
        name = string.lower(name:match("^%s*(.-)%s*$"))
        if not known[name] then
          quarto.log.warning("glossary: no group named '" .. name .. "' in " .. options.path)
        end
        only[name] = true
      end
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
    elseif mode == "footnote" and not footnoted[term] then
      local blocks
      if kwExists(kwargs, "def") then
        blocks = pandoc.Blocks({pandoc.Plain(pandoc.Inlines(pandoc.utils.stringify(kwargs.def)))})
      else
        local value = loadGlossary(options.path)[term]
        if value ~= nil then blocks = toBlocks(value) end
      end
      if blocks ~= nil and #blocks > 0 then
        footnoted[term] = true
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
