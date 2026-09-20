#!/usr/bin/env lua
--- Per-function timing over the differential corpus: `luajit spec/bench.lua`.
--- Not part of `make test`; useful when touching the regex compiler or the rule
--- tables, since pluralize/singularize dominate the cost.
local support = dofile((arg and arg[0] or "spec/bench.lua"):gsub("[^/\\]*$", "") .. "support.lua")
support.setup_path()

local inflection = require("inflection")
local U = require("inflection.utf8")

local words = {}
for line in io.lines(support.data_file("corpus.txt")) do
  if line ~= "" then
    words[#words + 1] = line
  end
end

local FUNCTIONS = {
  { "underscore", inflection.underscore },
  {
    "camelize",
    function(w)
      return inflection.camelize(w, true)
    end,
  },
  {
    "camelize (lower first)",
    function(w)
      return inflection.camelize(w, false)
    end,
  },
  { "dasherize", inflection.dasherize },
  { "humanize", inflection.humanize },
  { "titleize", inflection.titleize },
  { "parameterize", inflection.parameterize },
  { "transliterate", inflection.transliterate },
  { "pluralize", inflection.pluralize },
  { "singularize", inflection.singularize },
  { "utf8.upper", U.upper },
  { "utf8.lower", U.lower },
}

local function clock()
  if os.clock then
    return os.clock()
  end
end

print(
  string.format(
    "%d words, %s %s\n",
    #words,
    jit and ("LuaJIT " .. jit.version) or _VERSION,
    jit and "" or ""
  )
)
print(string.format("%-24s %12s %10s", "function", "ms/word", "share"))

local total, results = 0, {}
for _, entry in ipairs(FUNCTIONS) do
  local name, fn = entry[1], entry[2]
  local t0 = clock()
  for i = 1, #words do
    fn(words[i])
  end
  local elapsed = (clock() - t0) * 1000
  results[#results + 1] = { name, elapsed / #words, elapsed }
  total = total + elapsed
end
for _, r in ipairs(results) do
  print(string.format("%-24s %12.4f %9.1f%%", r[1], r[2], 100 * r[3] / total))
end
print(string.format("%-24s %12.4f", "total", total / #words))
