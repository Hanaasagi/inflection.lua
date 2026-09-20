#!/usr/bin/env lua
--- Test entry point: `luajit spec/run.lua` or `make test`.
--- Zero dependencies - loads spec/harness.lua, installs the busted-compatible
--- globals, then runs every spec/*_spec.lua.
local support = dofile((arg and arg[0] or "spec/run.lua"):gsub("[^/\\]*$", "") .. "support.lua")
support.setup_path()
package.path = support.SPEC_DIR .. "/?.lua;" .. package.path

local harness = require("harness")
harness.install_globals()

--- Discover specs, falling back to a fixed list if we cannot list a directory.
local function discover()
  local found = {}
  local pipe = io.popen('ls -1 "' .. support.SPEC_DIR .. '"/*_spec.lua 2>/dev/null')
  if pipe then
    for line in pipe:lines() do
      if line ~= "" then
        found[#found + 1] = line
      end
    end
    pipe:close()
  end
  if #found == 0 then
    for _, name in ipairs({
      "utf8_spec.lua",
      "regex_spec.lua",
      "inflection_spec.lua",
      "corpus_spec.lua",
    }) do
      found[#found + 1] = support.SPEC_DIR .. "/" .. name
    end
  end
  table.sort(found)
  return found
end

local specs = discover()
print(string.format("running %d spec files from %s", #specs, support.SPEC_DIR))
for _, path in ipairs(specs) do
  io.write("  " .. path:match("[^/\\]+$") .. "\n")
  dofile(path)
end

os.exit(harness.run(200))
