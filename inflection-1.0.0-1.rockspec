rockspec_format = "3.0"

package = "inflection"
version = "1.0.0-1"

source = {
   url = "git+https://github.com/Hanaasagi/inflection.lua",
   tag = "v1.0.0",
}

description = {
   summary = "Pure Lua port of the Python inflection library",
   detailed = [[
      A port of jpvanhal/inflection 0.5.1: string transformations for English,
      covering word-case conversion (camelize, underscore, dasherize, humanize,
      titleize, tableize, parameterize, transliterate), regular and irregular
      pluralization (pluralize, singularize) and ordinals (ordinal, ordinalize).

      The library has no dependencies and touches no host or editor API, so the
      same files run unmodified on LuaJIT 2.1, Lua 5.1 and Lua 5.4 and can be
      unit tested in CI with nothing but an interpreter.

      Correctness is established against the reference implementation rather
      than by hand-written examples: the upstream pytest suite is recorded as
      722 data-driven assertions, and a 3594-word corpus is compared against
      golden output for all eleven string functions. Both agree byte for byte.
   ]],
   homepage = "https://github.com/Hanaasagi/inflection.lua",
   license = "MIT",
   labels = { "string", "inflection", "pluralize", "singularize", "camelize",
              "underscore", "unicode", "pure-lua" },
}

dependencies = {
   "lua >= 5.1",
}

build = {
   type = "builtin",
   modules = {
      ["inflection"]       = "lua/inflection/init.lua",
      ["inflection.regex"] = "lua/inflection/regex.lua",
      ["inflection.utf8"]  = "lua/inflection/utf8.lua",
      ["inflection.rules"] = "lua/inflection/rules.lua",
      ["inflection.data"]  = "lua/inflection/data.lua",
   },
}
