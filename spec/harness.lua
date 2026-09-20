--- A dependency-free test harness implementing the subset of the busted API
--- that this suite uses: `describe`, `it`, `before_each` and an `assert` table
--- exposing `are.equal` / `are.same` / `is_true` / `is_nil` / `has_error`.
---
--- It exists so `make test` works on a bare interpreter. Because the specs only
--- touch that subset, they also run under real busted (verified with 2.3.0):
--- `make test-busted`, and this file is simply never loaded.

local H = {}

--- `table.unpack` is Lua 5.2+; `unpack` is Lua 5.1 / LuaJIT.
--- `table.unpack` is Lua 5.2+; `unpack` is Lua 5.1 / LuaJIT.
local UNPACK = table.unpack or unpack -- luacheck: ignore 143

local suites, scope_stack, before_eachs = {}, {}, {}
local current_test = nil

local function fmt(v)
  if type(v) == "string" then
    return string.format("%q", v)
  end
  if type(v) == "table" then
    local parts = {}
    for _, e in ipairs(v) do
      parts[#parts + 1] = fmt(e)
    end
    local extra = {}
    for k in pairs(v) do
      if type(k) ~= "number" then
        extra[#extra + 1] = tostring(k) .. "=" .. fmt(v[k])
      end
    end
    table.sort(extra)
    return "{ "
      .. table.concat(parts, ", ")
      .. (#extra > 0 and ("; " .. table.concat(extra, ", ")) or "")
      .. " }"
  end
  return tostring(v)
end
H.fmt = fmt

local function fail(message)
  error({ harness = true, message = message, test = current_test }, 3)
end

local function deep_same(a, b)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  for k, v in pairs(a) do
    if not deep_same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

-------------------------------------------------------------------- assertions
local A = setmetatable({}, {
  __call = function(_, value, message)
    if not value then
      fail(message or "expected a truthy value, got " .. fmt(value))
    end
    return value
  end,
})

function A.are_equal(expected, actual, message)
  if expected ~= actual then
    fail(
      (message and (message .. "\n      ") or "")
        .. "expected "
        .. fmt(expected)
        .. "\nactual   "
        .. fmt(actual)
    )
  end
  return true
end

function A.are_same(expected, actual, message)
  if not deep_same(expected, actual) then
    fail(
      (message and (message .. "\n      ") or "")
        .. "expected "
        .. fmt(expected)
        .. "\nactual   "
        .. fmt(actual)
    )
  end
  return true
end

function A.is_true(value, message)
  if value ~= true then
    fail(message or "expected true, got " .. fmt(value))
  end
  return true
end

function A.is_false(value, message)
  if value ~= false then
    fail(message or "expected false, got " .. fmt(value))
  end
  return true
end

function A.is_nil(value, message)
  if value ~= nil then
    fail(message or "expected nil, got " .. fmt(value))
  end
  return true
end

function A.has_error(fn, message)
  local ok = pcall(fn)
  if ok then
    fail(message or "expected an error, but the call succeeded")
  end
  return true
end

A.are = { equal = A.are_equal, same = A.are_same }
A.equal = A.are_equal
A.is_equal = A.are_equal
A.same = A.are_same
A.is_not_equal = function(a, b, m)
  if a == b then
    fail(m or "expected values to differ, both are " .. fmt(a))
  end
  return true
end

------------------------------------------------------------------- registration
function H.describe(name, body)
  scope_stack[#scope_stack + 1] = name
  local saved = #before_eachs
  body()
  for i = #before_eachs, saved + 1, -1 do
    before_eachs[i] = nil
  end
  scope_stack[#scope_stack] = nil
end

function H.it(name, body)
  local full = #scope_stack > 0 and (table.concat(scope_stack, " ") .. " " .. name) or name
  suites[#suites + 1] = {
    name = full,
    body = body,
    -- Resolved through UNPACK rather than `a and a() or b()`, which would fall
    -- through to b when before_eachs is empty and a() returns no values.
    hooks = { UNPACK(before_eachs) },
  }
end

function H.before_each(fn)
  before_eachs[#before_eachs + 1] = fn
end

-------------------------------------------------------------------------- run
--- @return number exit_code
function H.run(report_every)
  local pass, failures = 0, {}
  for index, test in ipairs(suites) do
    current_test = test.name
    local hooks = test.hooks
    local ok, err = xpcall(function()
      for i = 1, #hooks do
        hooks[i]()
      end
      test.body()
    end, function(e)
      if type(e) == "table" and e.harness then
        return e.message
      end
      return debug.traceback(tostring(e), 2)
    end)
    if ok then
      pass = pass + 1
    else
      failures[#failures + 1] = { name = test.name, message = err }
    end
    current_test = nil
    if report_every and index % report_every == 0 then
      io.write(string.format("\r  %d/%d", index, #suites))
      io.flush()
    end
  end
  if report_every and #suites >= report_every then
    io.write("\n")
  end

  local shown = 0
  for _, f in ipairs(failures) do
    shown = shown + 1
    if shown <= 25 then
      print(string.format("FAIL %s\n      %s", f.name, tostring(f.message):gsub("\n", "\n      ")))
    end
  end
  if shown > 25 then
    print(string.format("... and %d more failures", shown - 25))
  end

  print(string.format("\n%d passed, %d failed / %d assertions", pass, #failures, #suites))
  return #failures == 0 and 0 or 1
end

function H.install_globals()
  _G.describe, _G.it, _G.before_each, _G.assert = H.describe, H.it, H.before_each, A
  _G.finally = function() end
end

H.assert = A
return H
