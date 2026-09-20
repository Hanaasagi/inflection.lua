--- Differential test against golden output recorded from the reference
--- implementation (CPython `inflection` 0.5.1).
---
--- spec/data/golden_corpus.tsv holds, for every word in spec/data/corpus.txt,
--- what each public string function returns upstream. Regenerate it with
--- `make golden` after `pip install inflection==0.5.1`.
---
--- The corpus is deliberately broad: irregular and uncountable nouns, acronym
--- and identifier shapes, separator edge cases, Latin-1 and CJK input.
local SPEC_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]*$")) or "spec"
local support = dofile(SPEC_DIR .. "/support.lua")
support.setup_path()

local inflection = require("inflection")

local path = support.data_file("golden_corpus.tsv")
local fh = assert(
  io.open(path, "r"),
  "missing " .. path .. " - run `make golden` (needs: pip install inflection==0.5.1)"
)

local columns, rows, reference = nil, {}, "?"
for line in fh:lines() do
  if line:sub(1, 1) == "#" then
    reference = line:match("^# reference:%s*(.*)$") or reference
    local header = line:match("^# columns:%s*(.*)$")
    if header then
      columns = {}
      for name in header:gmatch("[^\t]+") do
        columns[#columns + 1] = name
      end
    end
  elseif line ~= "" then
    rows[#rows + 1] = line
  end
end
fh:close()
assert(columns and columns[1] == "word", "malformed golden header in " .. path)

--- Maps a golden column to the call under test.
local CALLS = {
  underscore = function(w)
    return inflection.underscore(w)
  end,
  camelize = function(w)
    return inflection.camelize(w, true)
  end,
  camelize_lower = function(w)
    return inflection.camelize(w, false)
  end,
  dasherize = function(w)
    return inflection.dasherize(w)
  end,
  humanize = function(w)
    return inflection.humanize(w)
  end,
  pluralize = function(w)
    return inflection.pluralize(w)
  end,
  singularize = function(w)
    return inflection.singularize(w)
  end,
  tableize = function(w)
    return inflection.tableize(w)
  end,
  titleize = function(w)
    return inflection.titleize(w)
  end,
  parameterize = function(w)
    return inflection.parameterize(w)
  end,
  transliterate = function(w)
    return inflection.transliterate(w)
  end,
}

--- Apply the same lossy normalisation the generator applied, so a cell can be
--- compared verbatim: tabs become spaces and newlines become a literal \n.
local function normalise(value)
  return (tostring(value):gsub("\t", " "):gsub("\n", "\\n"))
end

for index = 2, #columns do
  local column = columns[index]
  local call = CALLS[column]
  describe("differential corpus: " .. column, function()
    it(string.format("matches %s for all %d words", reference, #rows), function()
      assert(type(call) == "function", "no test call mapped for golden column " .. column)
      local mismatches, compared = {}, 0
      for _, line in ipairs(rows) do
        local cells = {}
        for cell in line:gmatch("([^\t]*)\t?") do
          if cell ~= "" or #cells <= #columns then
            cells[#cells + 1] = cell
          end
        end
        local word, want = cells[1], cells[index]
        if word ~= nil and want ~= nil then
          compared = compared + 1
          local ok, got = pcall(call, word)
          local got_text = ok and normalise(got)
            or ("<ERR:%s>"):format(tostring(got):match("([%w_]+Error)") or "?")
          if got_text ~= want then
            if #mismatches < 10 then
              mismatches[#mismatches + 1] =
                string.format("%s: got %s, want %s", normalise(word), got_text, normalise(want))
            else
              mismatches[#mismatches + 1] = "..."
            end
          end
        end
      end
      if #mismatches > 0 then
        assert.are.equal(
          0,
          #mismatches,
          string.format(
            "%d of %d words differ:\n%s",
            #mismatches,
            compared,
            table.concat(mismatches, "\n")
          )
        )
      end
    end)
  end)
end
