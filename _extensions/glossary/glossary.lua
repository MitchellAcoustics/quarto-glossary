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

---Read the glossary file into a {lowercased term: definition} table.
---Entries may be grouped under group names (see glossaryTable), so any
---mapping value is treated as a group and its entries are read instead; group
---names are not themselves terms.
local function loadGlossary(path)
  local metafile = io.open(path, 'r')
  local content = "---\n" .. metafile:read("*a") .. "\n---\n"
  metafile:close()

  local glossary = {}
  local function add(entries)
    for key, value in pairs(entries) do
      if pandoc.utils.type(value) == "table" then
        add(value)
      else
        glossary[string.lower(key)] = value
      end
    end
  end
  add(pandoc.read(content, "markdown").meta)
  return glossary
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

---Build the glossary as one table, with a full-width band row naming each
---group. `only` optionally limits it to a list of lowercased group names.
---
---In the PDF the band is shaded with the `glossarygroup` colour (override it
---with \colorlet{glossarygroup}{...} in the document header), xcolor's row
---counter is reset so zebra striping restarts below each band, and longtable's
---\nopagebreak keeps each band with its first entry. These need xcolor's
---`table` option; without it the band is simply unshaded. In HTML the band
---gets the `glossary-group` class (styled in glossary.css), and each group is
---its own <tbody> so Bootstrap's striping restarts after every band.
local function glossaryTable(path, only)
  local bandLatex = "\\ifdefined\\cellcolor\\cellcolor{glossarygroup}\\fi"
    .. "\\ifdefined\\rownum\\global\\rownum=2\\relax\\fi"

  local bodies = {}
  for _, group in ipairs(loadGlossaryGroups(path)) do
    local wanted = only == nil
      or (group.name ~= nil and only[string.lower(group.name)])
    if wanted then
      local rows = {}
      if group.name ~= nil then
        local band = pandoc.Plain({pandoc.RawInline("latex", bandLatex), pandoc.Strong(group.name)})
        table.insert(rows, pandoc.Row({cell({band}, 2, pandoc.Attr("", {"glossary-group"}))}))
      end
      for i, entry in ipairs(group.entries) do
        local term = pandoc.Inlines({pandoc.Strong(entry.key)})
        if i == 1 and group.name ~= nil then
          -- \nopagebreak is a \noalign, so it must open the row after the band.
          term:insert(1, pandoc.RawInline("latex", "\\nopagebreak"))
        end
        table.insert(rows, pandoc.Row({cell({pandoc.Plain(term)}), cell(toBlocks(entry.value))}))
      end
      table.insert(bodies, {attr = pandoc.Attr(), body = rows, head = {}, row_head_columns = 0})
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
    popup = "hover",
    show = true
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

  -- table mode (all formats): the whole glossary file as one table, optionally
  -- limited to some of its groups, e.g. groups="Hypothesis testing, Effect sizes"
  if kwExists(kwargs, "table") then
    local options = mergeOptions(kwargs, meta)
    local only = nil
    if kwExists(kwargs, "groups") then
      local known = {}
      for _, group in ipairs(loadGlossaryGroups(options.path)) do
        if group.name ~= nil then known[string.lower(group.name)] = true end
      end
      only = {}
      for name in pandoc.utils.stringify(kwargs.groups):gmatch("[^,]+") do
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
    return pandoc.Blocks({glossaryTable(options.path, only)})
  end

  -- non-HTML formats (e.g. PDF): no popups, so render the display text inline,
  -- optionally linked to the glossary section given by the `link` option
  if not quarto.doc.isFormat("html:js") then
    local options = mergeOptions(kwargs, meta)
    local display = pandoc.utils.stringify(args[1])
    if kwExists(kwargs, "display") then
      display = pandoc.utils.stringify(kwargs.display)
    end

    local text = pandoc.Inlines(display)
    if options.link ~= nil and options.link ~= "" then
      return pandoc.Link(text, options.link)
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
