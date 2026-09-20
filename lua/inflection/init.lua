--- inflection.lua - a pure Lua port of jpvanhal/inflection 0.5.1.
--
-- String transformations for English: word-case conversion and regular/irregular
-- pluralization, matching the reference implementation's output byte for byte.
--
-- No dependencies and no host/editor API: the same code runs unmodified on
-- LuaJIT 2.1, Lua 5.1 and Lua 5.4.
--
-- Modules:
--   inflection.rules  the rule tables, copied from upstream in their original
--                     Python regex form so they can be diffed against it
--   inflection.regex  compiler from the Python regex subset to Lua patterns
--   inflection.utf8   code point decoding and Unicode case mapping
--   inflection.data   NFKD decomposition and case mapping tables (generated)
--
-- Acceptance criteria: the complete upstream pytest suite, recorded as
-- data-driven assertions in spec/data/upstream_cases.lua.

local RX = require("inflection.regex")
local R = require("inflection.rules")
local U = require("inflection.utf8")

local M = {}

--- This project's own version. It moves independently of upstream: a fix to
--- the regex compiler or the Unicode layer is a change here, not there.
M._VERSION = "1.0.0"

--- The reference implementation whose behaviour this port reproduces, and the
--- release it is pinned to. Both are checked in CI (see .github/workflows).
M._UPSTREAM = "jpvanhal/inflection"
M._UPSTREAM_VERSION = "0.5.1"

--- Words that are their own plural, mirroring Python's `UNCOUNTABLES` set.
--- Deliberately mutable: the upstream test suite adds and removes entries.
M.UNCOUNTABLES = {}
for _, w in ipairs(R.UNCOUNTABLES) do
  M.UNCOUNTABLES[w] = true
end

local PLURALS, SINGULARS = {}, {}
for _, r in ipairs(R.PLURALS) do
  PLURALS[#PLURALS + 1] = { RX.compile(r[1]), r[2] }
end
for _, r in ipairs(R.SINGULARS) do
  SINGULARS[#SINGULARS + 1] = { RX.compile(r[1]), r[2] }
end

local UND_ACRONYM = RX.compile([[([A-Z]+)([A-Z][a-z])]])
local UND_BOUNDARY = RX.compile([[([a-z\d])([A-Z])]])
local HUMAN_TRAILING_ID = RX.compile([[_id$]])
local PARAM_UNWANTED = RX.compile([[(?i)[^a-z0-9\-_]+]])

---------------------------------------------------------------------------- case
--- Make an underscored, lowercase form of a string.
---
--- `underscore("DeviceType")` -> `"device_type"`
---
---@param word string
---@return string
function M.underscore(word)
  word = RX.gsub(UND_ACRONYM, [[\1_\2]], word)
  word = RX.gsub(UND_BOUNDARY, [[\1_\2]], word)
  word = word:gsub("-", "_")
  return U.lower(word)
end

--- Equivalent of `re.sub(r"(?:^|_)(.)", lambda m: m.group(1).upper(), s)`.
---
--- Hand-rolled rather than expressed as a pattern because Lua's `.` matches a
--- single *byte* and would split multi-byte characters in half.
local function camelize_upper(s)
  local out, i, at_start = {}, 1, true
  while i <= #s do
    local ch, ni = U.char_at(s, i)
    if at_start then
      out[#out + 1] = U.upper(ch)
      at_start, i = false, ni
    elseif ch == "_" then
      local ch2, ni2 = U.char_at(s, ni)
      if ch2 then
        out[#out + 1] = U.upper(ch2)
        i = ni2
      else
        out[#out + 1] = "_"
        i = ni
      end
    else
      out[#out + 1] = ch
      i = ni
    end
  end
  return table.concat(out)
end

--- Convert a string to CamelCase.
---
--- `camelize("device_type")` -> `"DeviceType"`, and with
--- `uppercase_first_letter = false` -> `"deviceType"`.
---
---@param s string
---@param uppercase_first_letter boolean|nil defaults to true, as upstream does
---@return string
function M.camelize(s, uppercase_first_letter)
  if uppercase_first_letter == nil then
    uppercase_first_letter = true
  end
  if uppercase_first_letter then
    return camelize_upper(s)
  end
  -- Upstream computes string[0].lower() + camelize(string)[1:], which raises
  -- IndexError on the empty string. Reproduced deliberately.
  if s == "" then
    error("string index out of range", 2)
  end
  return U.lower(U.sub(s, 0, 1)) .. U.sub(camelize_upper(s), 1)
end

--- Replace underscores with dashes.
---
--- `dasherize("puni_puni")` -> `"puni-puni"`
---
---@param word string
---@return string
function M.dasherize(word)
  return (word:gsub("_", "-"))
end

------------------------------------------------------------------ pluralization
--- Return the plural form of a word.
---
--- `pluralize("octopus")` -> `"octopi"`, `pluralize("sheep")` -> `"sheep"`
---
---@param word string
---@return string
function M.pluralize(word)
  if word == "" or M.UNCOUNTABLES[U.lower(word)] then
    return word
  end
  for _, r in ipairs(PLURALS) do
    local res, n = RX.gsub(r[1], r[2], word)
    if n > 0 then
      return res
    end
  end
  return word
end

--- The code point immediately before `byte_pos` (the start byte of the *next*
--- character). Walks back at most three bytes to find the sequence start.
local function prev_char(s, byte_pos)
  local i = byte_pos - 1
  if i < 1 then
    return nil
  end
  while i > 1 do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then
      break
    end
    i = i - 1
  end
  return s:sub(i, byte_pos - 1)
end

--- Equivalent of `re.search(r'(?i)\b(u)\Z', word)`: `u` must sit at the very
--- end of the word, preceded by a word boundary.
---
--- `lw` is the already-lowercased input (hoisted out of the caller's loop).
--- Every uncountable is pure ASCII, so comparing the suffix byte-wise is safe:
--- UTF-8 continuation bytes are all >= 0x80 and can never equal an ASCII byte.
local function uncountable_tail(lw, u)
  local n, un = #lw, #u
  if n < un or lw:sub(n - un + 1) ~= u then
    return false
  end
  if n == un then
    return true
  end
  local prev = prev_char(lw, n - un + 1)
  return prev == nil or not U.is_word(prev)
end

--- Return the singular form of a word, the inverse of `pluralize`.
---
--- `singularize("octopi")` -> `"octopus"`
---
---@param word string
---@return string
function M.singularize(word)
  local lw = U.lower(word)
  for u in pairs(M.UNCOUNTABLES) do
    if uncountable_tail(lw, u) then
      return word
    end
  end
  for _, r in ipairs(SINGULARS) do
    local res, n = RX.gsub(r[1], r[2], word)
    if n > 0 then
      return res
    end
  end
  return word
end

--- Turn a class name into its table name: `underscore` then `pluralize`.
---
--- `tableize("RawScaledScorer")` -> `"raw_scaled_scorers"`
---
---@param word string
---@return string
function M.tableize(word)
  return M.pluralize(M.underscore(word))
end

------------------------------------------------------------------ other transforms
--- Replace non-ASCII characters with an ASCII approximation, dropping any
--- character that has none. Equivalent to
--- `normalize('NFKD', s).encode('ascii', 'ignore').decode('ascii')`.
---
--- `transliterate("Malmö")` -> `"Malmo"`, `transliterate("Ærøskøbing")` -> `"rskbing"`
---
---@param s string
---@return string
function M.transliterate(s)
  local out, i = {}, 1
  while i <= #s do
    local ch, ni = U.char_at(s, i)
    local cp = U.codepoint(ch)
    if cp < 0x80 then
      out[#out + 1] = ch
    else
      local dec = U.nfkd_ascii(cp)
      if dec then
        out[#out + 1] = dec
      end
    end
    i = ni
  end
  return table.concat(out)
end

--- Python 3.7+ `re.escape`: escapes ASCII specials and whitespace only.
local PY_ESCAPE_SPECIAL = {
  ["("] = 1,
  [")"] = 1,
  ["["] = 1,
  ["]"] = 1,
  ["{"] = 1,
  ["}"] = 1,
  ["?"] = 1,
  ["*"] = 1,
  ["+"] = 1,
  ["-"] = 1,
  ["|"] = 1,
  ["^"] = 1,
  ["$"] = 1,
  ["\\"] = 1,
  ["."] = 1,
  ["&"] = 1,
  ["~"] = 1,
  ["#"] = 1,
  [" "] = 1,
  ["\t"] = 1,
  ["\n"] = 1,
  ["\r"] = 1,
  ["\v"] = 1,
  ["\f"] = 1,
}
local function py_escape(s)
  return (
    s:gsub(".", function(c)
      if PY_ESCAPE_SPECIAL[c] then
        return "\\" .. c
      end
      return c
    end)
  )
end

--- Equivalent of `re.sub(r'<sep>{2,}', sep, s)`. Lua patterns cannot repeat a
--- multi-character string, so this scans by hand.
local function collapse_repeats(s, sep)
  local n, out, i = #sep, {}, 1
  while i <= #s do
    if s:sub(i, i + n - 1) == sep then
      out[#out + 1] = sep
      i = i + n
      while s:sub(i, i + n - 1) == sep do
        i = i + n
      end
    else
      out[#out + 1] = s:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Replace special characters so a string can be used in a "pretty" URL.
---
--- `parameterize("Donald E. Knuth")` -> `"donald-e-knuth"`
---
---@param str string
---@param separator string|nil defaults to `"-"`
---@return string
function M.parameterize(str, separator)
  if separator == nil then
    separator = "-"
  end
  str = M.transliterate(str)
  str = RX.gsub(PARAM_UNWANTED, separator, str)
  if separator ~= "" then
    local esc = py_escape(separator)
    str = collapse_repeats(str, separator)
    str = RX.gsub(RX.compile("(?i)^" .. esc .. "|" .. esc .. "$"), "", str)
  end
  return U.lower(str)
end

--- Capitalize the first word, turn underscores into spaces and strip a
--- trailing `"_id"`.
---
--- `humanize("employee_salary")` -> `"Employee salary"`,
--- `humanize("author_id")` -> `"Author"`
---
---@param word string
---@return string
function M.humanize(word)
  word = RX.gsub(HUMAN_TRAILING_ID, "", word)
  word = word:gsub("_", " ")
  -- re.sub(r"(?i)([a-z\d]*)", lower) nets out to "lowercase ASCII A-Z only":
  -- the class is an explicit ASCII range, so IGNORECASE adds A-Z but no more.
  word = U.lower_ascii(word)
  -- re.sub(r"^\w", upper); note that \w is Unicode-aware in Python 3.
  local ch, ni = U.char_at(word, 1)
  if ch and U.is_word(ch) then
    word = U.upper(ch) .. word:sub(ni)
  end
  return word
end

--- Python's `str.title()`: title/uppercase a character when the previous one
--- is not cased, lowercase it otherwise.
local function py_title(s)
  local out, prev_cased, i = {}, false, 1
  while i <= #s do
    local ch, ni = U.char_at(s, i)
    out[#out + 1] = prev_cased and U.lower(ch) or U.title(ch)
    prev_cased = U.is_cased(ch)
    i = ni
  end
  return table.concat(out)
end

--- Equivalent of `re.sub(r"\b('?\w)", capitalize, s)`, hand-rolled to get
--- Unicode `\b` and `\w` semantics.
local function titleize_boundaries(s)
  local out, i, prev_word = {}, 1, false
  while i <= #s do
    local ch, ni = U.char_at(s, i)
    local isw = U.is_word(ch)
    if isw ~= prev_word then -- a \b holds here
      if ch == "'" then
        local ch2, ni2 = U.char_at(s, ni)
        if ch2 and U.is_word(ch2) then
          out[#out + 1] = U.capitalize("'" .. ch2)
          prev_word, i = true, ni2
        else
          out[#out + 1] = ch
          prev_word, i = false, ni
        end
      elseif isw then
        out[#out + 1] = U.capitalize(ch)
        prev_word, i = true, ni
      else
        out[#out + 1] = ch
        prev_word, i = false, ni
      end
    else
      out[#out + 1] = ch
      prev_word, i = isw, ni
    end
  end
  return table.concat(out)
end

--- Capitalize all words to produce a nicer looking title.
---
--- `titleize("man from the boondocks")` -> `"Man From The Boondocks"`
---
---@param word string
---@return string
function M.titleize(word)
  return titleize_boundaries(py_title(M.humanize(M.underscore(word))))
end

---------------------------------------------------------------------- ordinals
--- Python's `int()`: truncates floats toward zero, and for strings accepts an
--- optional sign followed by decimal digits only.
local function to_int(n)
  if type(n) == "number" then
    assert(n == n and n ~= math.huge and n ~= -math.huge, "cannot convert float NaN/inf to integer")
    if n >= 0 then
      return math.floor(n)
    end
    return math.ceil(n)
  end
  local digits = tostring(n):match("^%s*([-+]?%d+)%s*$")
  assert(digits, "invalid literal for int() with base 10: " .. tostring(n))
  return tonumber(digits)
end

--- Return the ordinal suffix for a number: `ordinal(1)` -> `"st"`.
---
---@param number integer|string
---@return string
function M.ordinal(number)
  local n = math.abs(to_int(number))
  local m100 = n % 100
  if m100 == 11 or m100 == 12 or m100 == 13 then
    return "th"
  end
  local suffix = { [1] = "st", [2] = "nd", [3] = "rd" }
  return suffix[n % 10] or "th"
end

--- Turn a number into its ordinal string: `ordinalize(1)` -> `"1st"`.
---
---@param number integer|string
---@return string
function M.ordinalize(number)
  return tostring(number) .. M.ordinal(number)
end

return M
