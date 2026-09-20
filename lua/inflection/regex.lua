--- Compiler from the Python regex subset used by the inflection rules down to
--- Lua patterns. Pure Lua, no dependencies.
--
-- Lua patterns are missing three things this needs; each is worked around:
--   1. no case-insensitive flag -> (?i) is expanded into per-character folding
--      ([xX] outside a class, xX inside one)
--   2. no alternation           -> `|` is expanded into the cartesian product of
--      patterns; matching picks the leftmost hit and, on a tie, the earliest
--      expansion, which reproduces Python re's leftmost-first semantics
--   3. quantifiers cannot apply to a group -> (x)? becomes the two branches
--      [x, empty]; a quantifier on a single character or class is kept as is
--
-- Because of (3) the branches of one rule can contain different numbers of
-- captures, so every expansion carries a gmap (Python group number -> Lua
-- capture number) used to translate \1..\9 in the replacement.
--
-- Constructs that cannot be translated raise an error. Silent approximation
-- would turn a rule change upstream into a wrong answer here.

local M = {}

local PAT_SPECIAL = {
  ["^"] = 1,
  ["$"] = 1,
  ["("] = 1,
  [")"] = 1,
  ["%"] = 1,
  ["."] = 1,
  ["["] = 1,
  ["]"] = 1,
  ["*"] = 1,
  ["+"] = 1,
  ["-"] = 1,
  ["?"] = 1,
}
local CLASS_SPECIAL = { ["]"] = 1, ["%"] = 1, ["-"] = 1, ["^"] = 1, ["["] = 1 }
-- Shorthands that can appear inside a character class. Negated forms (^%w) and
-- \s (which is [ \t\n\r\f\v], not a single space) cannot be embedded in a
-- larger Lua class, so they are rejected rather than approximated.
local SHORTHAND_CLASS = { d = "0-9", w = "%w" }

local function esc_lit(c)
  return PAT_SPECIAL[c] and ("%" .. c) or c
end
local function esc_cls(c)
  return CLASS_SPECIAL[c] and ("%" .. c) or c
end

local function fold_lit(c, icase)
  if not icase then
    return esc_lit(c)
  end
  local l, u = c:lower(), c:upper()
  if l == u then
    return esc_lit(c)
  end
  return "[" .. esc_cls(l) .. esc_cls(u) .. "]"
end

local function fold_cls(c, icase)
  if not icase then
    return esc_cls(c)
  end
  local l, u = c:lower(), c:upper()
  if l == u then
    return esc_cls(c)
  end
  return esc_cls(l) .. esc_cls(u)
end

-------------------------------------------------------------------------- parse
local function parse(pat)
  local icase = pat:sub(1, 4) == "(?i)"
  local i = icase and 5 or 1
  local ncap = 0
  local parse_alt

  local function parse_class()
    local j = i + 1 -- i points at '['
    local neg = pat:sub(j, j) == "^"
    if neg then
      j = j + 1
    end
    local parts, first = {}, true
    while j <= #pat and (pat:sub(j, j) ~= "]" or first) do
      first = false
      local c = pat:sub(j, j)
      if c == "\\" then
        local e = pat:sub(j + 1, j + 1)
        assert(
          SHORTHAND_CLASS[e] or not e:match("%a"),
          "unsupported escape inside character class: \\" .. e .. " in " .. pat
        )
        parts[#parts + 1] = SHORTHAND_CLASS[e] or esc_cls(e)
        j = j + 2
      elseif j + 2 <= #pat and pat:sub(j + 1, j + 1) == "-" and pat:sub(j + 2, j + 2) ~= "]" then
        local lo, hi = c, pat:sub(j + 2, j + 2) -- a range is kept whole
        parts[#parts + 1] = esc_cls(lo) .. "-" .. esc_cls(hi)
        if icase and lo:upper() ~= lo then
          parts[#parts + 1] = esc_cls(lo:upper()) .. "-" .. esc_cls(hi:upper())
        end
        j = j + 3
      else
        parts[#parts + 1] = fold_cls(c, icase)
        j = j + 1
      end
    end
    i = j + 1
    return { "lit", "[" .. (neg and "^" or "") .. table.concat(parts) .. "]" }
  end

  local function parse_atom()
    local c = pat:sub(i, i)
    if c == "^" or c == "$" then
      i = i + 1
      return { "anchor", c }
    end
    if c == "[" then
      return parse_class()
    end
    -- Lua patterns cannot express a counted quantifier; treating "{" as a
    -- literal would silently change the meaning of the rule.
    if c == "{" then
      error("counted quantifier {n,m} is not expressible as a Lua pattern: " .. pat)
    end
    if c == "(" then
      if pat:sub(i, i + 1) == "(?" and pat:sub(i, i + 2) ~= "(?:" then
        error("unsupported (?...) construct (lookaround / inline flags): " .. pat)
      end
      if pat:sub(i, i + 2) == "(?:" then
        i = i + 3
        local inner = parse_alt()
        assert(pat:sub(i, i) == ")", "missing ) in " .. pat)
        i = i + 1
        return { "grp", inner }
      end
      i = i + 1
      ncap = ncap + 1
      local inner = parse_alt()
      assert(pat:sub(i, i) == ")", "missing ) in " .. pat)
      i = i + 1
      return { "cap", inner, ncap }
    end
    if c == "\\" then
      local e = pat:sub(i + 1, i + 1)
      i = i + 2
      local m = { d = "%d", D = "%D", w = "%w", W = "%W", s = "%s", S = "%S" }
      if m[e] then
        return { "lit", m[e] }
      end
      -- \b \B \A \Z \z need Unicode word boundaries Lua patterns lack, and
      -- \1..\9 in a *pattern* is a backreference. Fail loudly on both.
      if e:match("%a") then
        error("unsupported escape \\" .. e .. " (word boundary / assertion): " .. pat)
      end
      if e:match("%d") then
        error("backreference \\" .. e .. " inside a pattern is not supported: " .. pat)
      end
      return { "lit", esc_lit(e) }
    end
    assert(c ~= "", "pattern ended unexpectedly: " .. pat)
    i = i + 1
    return { "lit", fold_lit(c, icase) }
  end

  local function is_atom_node(n)
    -- Can a quantifier follow this node directly? Only for a single `lit`
    -- shaped as one character, an escape (%x) or a character class ([...]).
    if n[1] ~= "lit" then
      return false
    end
    local f = n[2]
    if #f == 1 then
      return true
    end
    if #f == 2 and f:sub(1, 1) == "%" then
      return true
    end
    if f:sub(1, 1) == "[" and f:sub(-1) == "]" then
      return true
    end
    return false
  end

  local function parse_item()
    local a = parse_atom()
    local q = pat:sub(i, i)
    if q == "?" or q == "*" or q == "+" then
      i = i + 1
      return { "quant", q, a, is_atom_node(a) }
    end
    return a
  end

  local function parse_seq()
    local items = {}
    while i <= #pat do
      local c = pat:sub(i, i)
      if c == ")" or c == "|" then
        break
      end
      items[#items + 1] = parse_item()
    end
    if #items == 1 then
      return items[1]
    end
    assert(#items > 0, "empty branch: " .. pat)
    return { "seq", items }
  end

  parse_alt = function()
    local branches = { parse_seq() }
    while pat:sub(i, i) == "|" do
      i = i + 1
      branches[#branches + 1] = parse_seq()
    end
    if #branches == 1 then
      return branches[1]
    end
    return { "alt", branches }
  end

  local ast = parse_alt()
  assert(i > #pat, "pattern not fully parsed (at offset " .. i .. "): " .. pat)
  return ast, ncap, icase
end

------------------------------------------------------------------------- expand
-- Each expansion is a sequence of pieces: {lit="..."} or {cap=group, inner=pieces}
local function expand(n)
  local k = n[1]
  if k == "lit" or k == "anchor" then
    return { { { lit = n[2] } } }
  end
  if k == "grp" then
    return expand(n[2])
  end
  if k == "cap" then
    local out = {}
    for _, seq in ipairs(expand(n[2])) do
      out[#out + 1] = { { cap = n[3], inner = seq } }
    end
    return out
  end
  if k == "alt" then
    local out = {}
    for _, b in ipairs(n[2]) do
      for _, seq in ipairs(expand(b)) do
        out[#out + 1] = seq
      end
    end
    return out
  end
  if k == "quant" then
    local op, child, atom = n[2], n[3], n[4]
    local subs = expand(child)
    if atom then -- single character or class: Lua supports this natively
      local out = {}
      for _, seq in ipairs(subs) do
        local c = {}
        for _, p in ipairs(seq) do
          c[#c + 1] = p
        end
        c[#c] = { lit = c[#c].lit .. op }
        out[#out + 1] = c
      end
      return out
    end
    if op == "?" then -- optional group -> the two branches [child, empty]
      local out = {}
      for _, seq in ipairs(subs) do
        out[#out + 1] = seq
      end
      out[#out + 1] = {}
      return out
    end
    error("a Lua pattern quantifier cannot apply to a group; unsupported * / +: " .. tostring(op))
  end
  if k == "seq" then
    local out = { {} }
    for _, item in ipairs(n[2]) do
      local es, nxt = expand(item), {}
      for _, pre in ipairs(out) do
        for _, e in ipairs(es) do
          local c = {}
          for _, p in ipairs(pre) do
            c[#c + 1] = p
          end
          for _, p in ipairs(e) do
            c[#c + 1] = p
          end
          nxt[#nxt + 1] = c
        end
      end
      out = nxt
    end
    return out
  end
  error("unknown node: " .. tostring(k))
end

local function flatten(pieces)
  local buf, gmap, idx = {}, {}, 0
  local function walk(ps)
    for _, p in ipairs(ps) do
      if p.lit then
        buf[#buf + 1] = p.lit
      else
        idx = idx + 1
        gmap[p.cap] = idx
        buf[#buf + 1] = "("
        walk(p.inner)
        buf[#buf + 1] = ")"
      end
    end
  end
  walk(pieces)
  return table.concat(buf), gmap
end

local cache = {}
function M.compile(pat)
  if cache[pat] then
    return cache[pat]
  end
  local ast, ncap = parse(pat)
  local seen, list = {}, {}
  for _, pieces in ipairs(expand(ast)) do
    local s, gmap = flatten(pieces)
    if not seen[s] then
      seen[s] = true
      list[#list + 1] = { pat = s, gmap = gmap }
    end
  end
  assert(#list <= 64, "too many alternation expansions (" .. #list .. "): " .. pat)
  local c = { patterns = list, ncap = ncap, source = pat }
  cache[pat] = c
  return c
end

-------------------------------------------------------------------------- match
-- Python re.sub replacement strings: \1..\9 are groups, \\ is a literal
-- backslash, and % is an ordinary character (unlike Lua's own gsub).
local function repl_text(repl, caps, gmap, whole)
  local out, i = {}, 1
  while i <= #repl do
    local c = repl:sub(i, i)
    local d = repl:sub(i + 1, i + 1)
    if c == "\\" and d:match("%d") then
      local n = tonumber(d)
      local lua_i = gmap[n]
      out[#out + 1] = (lua_i and caps[lua_i]) or (n == 0 and whole) or ""
      i = i + 2
    elseif c == "\\" and d == "\\" then
      out[#out + 1] = "\\"
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Leftmost match; ties go to the earliest expansion, i.e. Python's
--- leftmost-first. Hot path: the scan uses scalar locals only, and captures are
--- fetched just once, for the winning pattern.
local function best(c, s, init)
  local pats = c.patterns
  local ba, bb, bidx = nil, nil, nil
  for idx = 1, #pats do
    local a, b = s:find(pats[idx].pat, init)
    if a ~= nil and (ba == nil or a < ba) then
      ba, bb, bidx = a, b, idx
    end
  end
  if ba == nil then
    return nil
  end
  local e = pats[bidx]
  local caps, third = {}, { s:find(e.pat, ba) }
  for k = 3, #third do
    caps[k - 2] = third[k]
  end
  return { a = ba, b = bb, gmap = e.gmap, caps = caps, whole = s:sub(ba, bb) }
end

local function apply(repl, f)
  if type(repl) == "function" then
    return repl(f.caps, f.whole, f.gmap)
  end
  return repl_text(repl, f.caps, f.gmap, f.whole)
end

function M.search(c, s)
  return best(c, s, 1) ~= nil
end
function M.match(c, s)
  local f = best(c, s, 1)
  return f and f.whole or nil
end

--- Equivalent of Python's re.sub(count=0): replaces every non-overlapping
--- match and advances one character after an empty match.
---
--- The second return value is the number of substitutions, which lets callers
--- replace a rule without scanning twice (search then sub).
function M.gsub(c, repl, s)
  local out, pos, guard, n = {}, 1, 0, 0
  while pos <= #s + 1 do
    local f = best(c, s, pos)
    if not f then
      break
    end
    guard = guard + 1
    assert(guard < 100000, "gsub iterated too many times: " .. c.source)
    n = n + 1
    out[#out + 1] = s:sub(pos, f.a - 1)
    out[#out + 1] = apply(repl, f)
    if f.b < f.a then
      out[#out + 1] = s:sub(f.a, f.a)
      pos = f.a + 1
    else
      pos = f.b + 1
    end
  end
  out[#out + 1] = s:sub(pos)
  return table.concat(out), n
end

function M.sub(c, repl, s)
  local f = best(c, s, 1)
  if not f then
    return s
  end
  return s:sub(1, f.a - 1) .. apply(repl, f) .. s:sub(f.b + 1)
end

return M
