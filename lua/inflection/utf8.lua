--- Minimal UTF-8 decoding and Unicode case mapping, in pure Lua.
--
-- LuaJIT implements Lua 5.1 and so has no `utf8` library, while `string.upper`
-- and `string.lower` are byte-wise and locale dependent. Code points are
-- therefore decoded here and looked up in the tables that tools/gen_unicode_data.py
-- generates from Python's `unicodedata` into inflection.data.

local D = require("inflection.data")
local M = {}

------------------------------------------------------------- code point coding
--- Returns (code point, byte position of the next character). Invalid and
--- truncated sequences degrade to a single byte so decoding always terminates.
function M.codepoint_at(s, i)
  local b = s:byte(i)
  if b == nil then
    return nil
  end
  if b < 0x80 then
    return b, i + 1
  end
  local function cont(k)
    local c = s:byte(i + k)
    if c and c >= 0x80 and c <= 0xBF then
      return c
    end
    return nil
  end
  if b >= 0xC2 and b <= 0xDF then
    local c1 = cont(1)
    if c1 then
      return (b - 0xC0) * 64 + (c1 - 0x80), i + 2
    end
  elseif b >= 0xE0 and b <= 0xEF then
    local c1, c2 = cont(1), cont(2)
    if c1 and c2 then
      return ((b - 0xE0) * 64 + (c1 - 0x80)) * 64 + (c2 - 0x80), i + 3
    end
  elseif b >= 0xF0 and b <= 0xF4 then
    local c1, c2, c3 = cont(1), cont(2), cont(3)
    if c1 and c2 and c3 then
      return (((b - 0xF0) * 64 + (c1 - 0x80)) * 64 + (c2 - 0x80)) * 64 + (c3 - 0x80), i + 4
    end
  end
  return b, i + 1
end

function M.char_at(s, i)
  if i > #s then
    return nil
  end
  local _, ni = M.codepoint_at(s, i)
  return s:sub(i, ni - 1), ni
end

function M.codepoint(ch)
  return (M.codepoint_at(ch, 1))
end

function M.encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  end
  if cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  end
  if cp < 0x10000 then
    return string.char(
      0xE0 + math.floor(cp / 4096),
      0x80 + math.floor(cp / 64) % 64,
      0x80 + cp % 64
    )
  end
  return string.char(
    0xF0 + math.floor(cp / 262144),
    0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64,
    0x80 + cp % 64
  )
end

function M.len(s)
  local n, i = 0, 1
  while i <= #s do
    local _, ni = M.codepoint_at(s, i)
    i, n = ni, n + 1
  end
  return n
end

--- Byte position of the n-th code point (0-based); #s + 1 when out of range.
function M.byte_index(s, n)
  local count, i = 0, 1
  while i <= #s do
    if count == n then
      return i
    end
    local _, ni = M.codepoint_at(s, i)
    i, count = ni, count + 1
  end
  return #s + 1
end

--- Python slice semantics: s[i:j] over 0-based code point indices, j optional.
function M.sub(s, i, j)
  local a = M.byte_index(s, i)
  local b = j and M.byte_index(s, j) or (#s + 1)
  if b <= a then
    return ""
  end
  return s:sub(a, b - 1)
end

------------------------------------------------------------------- data tables
local function build(keys, vals)
  local t, i = {}, 1
  for v in (vals .. "\n"):gmatch("([^\n]*)\n") do
    local cp, ni = M.codepoint_at(keys, i)
    if not cp then
      break
    end
    t[cp] = v
    i = ni
  end
  return t
end

local NFKD = build(D.NFKD_KEYS, D.NFKD_VALS)
local UPPER = build(D.UPPER_KEYS, D.UPPER_VALS)
local LOWER = build(D.LOWER_KEYS, D.LOWER_VALS)

--- The ASCII part of a character's NFKD decomposition; nil means the character
--- has no ASCII approximation and must be dropped.
function M.nfkd_ascii(cp)
  return NFKD[cp]
end

-------------------------------------------------------------------- case mapping
local ASCII_UP, ASCII_LO = {}, {}
for c = 0x61, 0x7A do
  ASCII_UP[c] = c - 32
end
for c = 0x41, 0x5A do
  ASCII_LO[c] = c + 32
end

local function casemap(s, ascii_map, uni_map)
  if s == "" then
    return s
  end
  local out, i = {}, 1
  while i <= #s do
    local cp, ni = M.codepoint_at(s, i)
    if cp < 0x80 then
      local m = ascii_map[cp]
      out[#out + 1] = m and string.char(m) or s:sub(i, ni - 1)
    else
      out[#out + 1] = uni_map[cp] or s:sub(i, ni - 1)
    end
    i = ni
  end
  return table.concat(out)
end

function M.upper(s)
  return casemap(s, ASCII_UP, UPPER)
end
function M.lower(s)
  return casemap(s, ASCII_LO, LOWER)
end
-- Code points with a distinct titlecase form (such as U+01C5) are not tabled
-- separately; they fall back to uppercase.
function M.title(s)
  return M.upper(s)
end

--- Lowercase ASCII A-Z only. Used to reproduce Python classes written as an
--- explicit ASCII range, e.g. (?i)[a-z\d], which IGNORECASE widens to A-Za-z0-9
--- but never to non-ASCII letters.
function M.lower_ascii(s)
  return (s:gsub("[A-Z]", function(c)
    return string.char(c:byte() + 32)
  end))
end

--- Python's str.capitalize(): titlecase the first character, lowercase the rest.
function M.capitalize(s)
  if s == "" then
    return s
  end
  local ch, ni = M.char_at(s, 1)
  return M.title(ch) .. M.lower(s:sub(ni))
end

----------------------------------------------------------- character categories
function M.is_cased(ch)
  local cp = M.codepoint(ch)
  if cp < 0x80 then
    return (cp >= 0x41 and cp <= 0x5A) or (cp >= 0x61 and cp <= 0x7A)
  end
  return UPPER[cp] ~= nil or LOWER[cp] ~= nil
end

--- Approximation of Python's \w: ASCII uses [0-9A-Za-z_], and beyond ASCII a
--- character counts as a word character when it has a case mapping. Known
--- deviation: non-ASCII digits and combining marks are reported as non-word.
function M.is_word(ch)
  local cp = M.codepoint(ch)
  if cp < 0x80 then
    return (cp >= 0x30 and cp <= 0x39)
      or (cp >= 0x41 and cp <= 0x5A)
      or (cp >= 0x61 and cp <= 0x7A)
      or cp == 0x5F
  end
  return M.is_cased(ch)
end

return M
