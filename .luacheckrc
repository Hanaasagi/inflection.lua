-- luacheck configuration.
--
-- The library targets Lua 5.1 (which is what LuaJIT implements) so that using a
-- 5.2+ only API is reported rather than silently breaking one interpreter.
std = "lua51"
max_line_length = 100
max_code_line_length = 110
max_comment_line_length = 100

exclude_files = {
  -- generated; formatting and identifier style are the generator's business
  "lua/inflection/data.lua",
  "lua/inflection/rules.lua",
  "spec/data/upstream_cases.lua",
}

files["lua/**/*.lua"] = {
  -- the modules return a table and define no globals
  allow_defined_top = false,
}

files["spec/harness.lua"] = {
  -- installs describe/it/before_each/assert as globals on purpose
  allow_defined_top = true,
}

files["spec/**/*_spec.lua"] = {
  read_globals = { "describe", "it", "before_each" },
  -- busted (and the bundled harness) replace assert with a callable table
  allow_defined_top = true,
}

files["spec/run.lua"] = { allow_defined_top = true }
files["spec/bench.lua"] = { read_globals = { "jit" } }
files["spec/support.lua"] = { allow_defined_top = true }
