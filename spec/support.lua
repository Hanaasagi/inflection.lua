--- Shared bootstrap for the spec runner and the benchmark script.
--- Resolves the repo root from this file's own location so the suite can be
--- run from any working directory.
local M = {}

local function dir_of(level)
  local src = debug.getinfo(level, "S").source:sub(2)
  return (src:match("^(.*)[/\\][^/\\]*$")) or "."
end

M.SPEC_DIR = dir_of(2)
M.ROOT = (M.SPEC_DIR:match("^(.*)[/\\][^/\\]*$")) or "."

--- Put lua/ on package.path so `require("inflection")` works from a checkout
--- without installing the rock.
function M.setup_path()
  local lua_dir = M.ROOT .. "/lua"
  package.path = table.concat({
    lua_dir .. "/?.lua",
    lua_dir .. "/?/init.lua",
    package.path,
  }, ";")
  return M
end

--- Absolute-ish path to a file inside spec/.
function M.data_file(name)
  return M.SPEC_DIR .. "/data/" .. name
end

return M
