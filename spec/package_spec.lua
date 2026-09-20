--- Packaging invariants.
---
--- The version number lives in several places that nothing else cross-checks:
--- the module, the rockspec, its filename and the changelog. This spec fails
--- when they drift apart, which is otherwise easy to do and invisible at
--- runtime.
local SPEC_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]*$")) or "spec"
local support = dofile(SPEC_DIR .. "/support.lua")
support.setup_path()

local inflection = require("inflection")

--- A rockspec is a Lua chunk that assigns to globals, so load it with a private
--- environment instead of polluting _G. Written to work on 5.1 and 5.2+.
local function load_rockspec(path)
  local handle = assert(io.open(path, "r"), "cannot read " .. path)
  local source = handle:read("*a")
  handle:close()
  local env = {}
  local chunk
  if setfenv then -- Lua 5.1 / LuaJIT
    chunk = assert(loadstring(source, "=" .. path))
    setfenv(chunk, env)
  else -- Lua 5.2+
    chunk = assert(load(source, "=" .. path, "t", env))
  end
  chunk()
  return env
end

local function read_file(path)
  local handle = assert(io.open(path, "r"), "cannot read " .. path)
  local content = handle:read("*a")
  handle:close()
  return content
end

local function find_rockspecs()
  local found = {}
  local pipe = io.popen('ls -1 "' .. support.ROOT .. '"/*.rockspec 2>/dev/null')
  if pipe then
    for line in pipe:lines() do
      if line ~= "" then
        found[#found + 1] = line
      end
    end
    pipe:close()
  end
  return found
end

describe("packaging", function()
  local rockspecs = find_rockspecs()

  it("ships exactly one rockspec", function()
    assert.are.equal(1, #rockspecs)
  end)

  it("names the rockspec <package>-<version>.rockspec", function()
    local spec = load_rockspec(rockspecs[1])
    local expected = ("%s-%s.rockspec"):format(spec.package, spec.version)
    assert.are.equal(expected, rockspecs[1]:match("[^/\\]+$"))
  end)

  it("agrees on the version between the module and the rockspec", function()
    local spec = load_rockspec(rockspecs[1])
    -- A rockspec version is <package-version>-<rockspec-revision>; the module
    -- reports only the package version.
    local package_version = spec.version:match("^(.-)%-%d+$") or spec.version
    assert.are.equal(inflection._VERSION, package_version)
  end)

  it("declares the module it is named after", function()
    local spec = load_rockspec(rockspecs[1])
    assert.are.equal("inflection", spec.package)
    assert.are.equal(
      support.ROOT .. "/lua/inflection/init.lua",
      support.ROOT .. "/" .. spec.build.modules["inflection"]
    )
  end)

  it("points every declared module at a file that exists", function()
    local spec = load_rockspec(rockspecs[1])
    for name, relpath in pairs(spec.build.modules) do
      local path = support.ROOT .. "/" .. relpath
      local handle = io.open(path, "r")
      assert(handle ~= nil, "declared module " .. name .. " is missing: " .. relpath)
      handle:close()
    end
  end)

  it("pins the same upstream release everywhere", function()
    local common = read_file(support.ROOT .. "/tools/common.py")
    local pinned = common:match('REFERENCE_VERSION%s*=%s*"([^"]+)"')
    assert.are.equal(inflection._UPSTREAM_VERSION, pinned)

    local workflow = read_file(support.ROOT .. "/.github/workflows/test.yml")
    assert(
      workflow:find("pip install inflection==" .. pinned, 1, true),
      "CI does not pin inflection==" .. pinned
    )
    assert(
      workflow:find("--branch " .. pinned, 1, true),
      "CI does not clone upstream tag " .. pinned
    )
  end)

  it("has a changelog entry for the current version", function()
    local changelog = read_file(support.ROOT .. "/CHANGELOG.md")
    assert(
      changelog:find("## " .. inflection._VERSION, 1, true),
      "CHANGELOG.md has no ## " .. inflection._VERSION .. " section"
    )
  end)

  it("reports a version and an upstream it tracks", function()
    assert.are.equal("string", type(inflection._VERSION))
    assert.are.equal("jpvanhal/inflection", inflection._UPSTREAM)
    assert(
      inflection._VERSION:match("^%d+%.%d+%.%d+$"),
      "_VERSION should be semantic: " .. tostring(inflection._VERSION)
    )
  end)
end)
