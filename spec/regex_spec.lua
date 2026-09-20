--- Tests for the Python-regex-subset -> Lua-pattern compiler.
--- Bootstrap package.path so this spec also runs standalone, e.g.
--- `busted spec/regex_spec.lua`, without depending on another spec loading first.
local SPEC_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]*$")) or "spec"
dofile(SPEC_DIR .. "/support.lua").setup_path()

local RX = require("inflection.regex")

local function gsub(pattern, replacement, subject)
  return (RX.gsub(RX.compile(pattern), replacement, subject))
end

describe("regex compiler", function()
  it("expands alternation inside a capture group", function()
    local c = RX.compile([[(?i)(matr|vert|ind)(?:ix|ex)$]])
    assert.are.equal(6, #c.patterns)
  end)

  it("handles the irregular-plural rules", function()
    assert.are.equal("matrices", gsub([[(?i)(matr|vert|ind)(?:ix|ex)$]], [[\1ices]], "matrix"))
    -- Upstream produces "VERTices": \1 preserves the captured case verbatim.
    assert.are.equal("VERTices", gsub([[(?i)(matr|vert|ind)(?:ix|ex)$]], [[\1ices]], "VERTEX"))
    assert.are.equal("indices", gsub([[(?i)(matr|vert|ind)(?:ix|ex)$]], [[\1ices]], "index"))
    assert.are.equal("vertices", gsub([[(?i)(matr|vert|ind)(?:ix|ex)$]], [[\1ices]], "vertices"))
  end)

  it("handles negated classes with IGNORECASE", function()
    local p = [[(?i)([^aeiouy]|qu)y$]]
    assert.are.equal("cities", gsub(p, [[\1ies]], "city"))
    assert.are.equal("tries", gsub(p, [[\1ies]], "try"))
    assert.are.equal("quay", gsub(p, [[\1ies]], "quay"))
    assert.are.equal("day", gsub(p, [[\1ies]], "day"))
  end)

  it("expands optional groups, which Lua patterns cannot quantify", function()
    local p = [[(?i)(alias|status)(es)?$]]
    assert.are.equal("status", gsub(p, [[\1]], "statuses"))
    assert.are.equal("status", gsub(p, [[\1]], "status"))
    assert.are.equal("alias", gsub(p, [[\1]], "alias"))
  end)

  it("keeps ? on a single character working natively", function()
    assert.are.equal("passersby", gsub([[(?i)(passer)s?by$]], [[\1sby]], "passerby"))
    assert.are.equal("passersby", gsub([[(?i)(passer)s?by$]], [[\1sby]], "passersby"))
  end)

  it("maps a bare $ anchor to the empty match at end of string", function()
    assert.are.equal("posts", gsub([[$]], "s", "post"))
    assert.are.equal("posts", gsub([[(?i)s$]], "s", "posts"))
  end)

  it("substitutes every non-overlapping match, like re.sub", function()
    assert.are.equal("IO_Error", gsub([[([A-Z]+)([A-Z][a-z])]], [[\1_\2]], "IOError"))
    assert.are.equal("XML_HttpRequest", gsub([[([A-Z]+)([A-Z][a-z])]], [[\1_\2]], "XMLHttpRequest"))
  end)

  it("honours rules that must stay case sensitive", function()
    assert.are.equal("cow", gsub([[k[iI][nN][eE]$]], "cow", "kine"))
    assert.are.equal("KINE", gsub([[k[iI][nN][eE]$]], "cow", "KINE"))
  end)

  it("is unaffected by the interpreter's own case-folding settings", function()
    -- Every compiled pattern carries an explicit \c or \C, so results cannot
    -- depend on ambient options.
    assert.are.equal("zombies", gsub([[(?i)(z)ombie$]], [[\1ombies]], "zombie"))
    assert.are.equal("Zombies", gsub([[(?i)(z)ombie$]], [[\1ombies]], "Zombie"))
  end)

  it("supports ^ anchors and multi-branch groups", function()
    assert.are.equal("ox", gsub([[(?i)^(ox)en]], [[\1]], "oxen"))
    assert.are.equal("octopus", gsub([[(?i)(octop|vir)(us|i)$]], [[\1us]], "octopi"))
    assert.are.equal("analysis", gsub([[(?i)(a)naly(sis|ses)$]], [[\1nalysis]], "analyses"))
    assert.are.equal("news", gsub([[(?i)(n)ews$]], [[\1ews]], "news"))
  end)

  it("reports the substitution count so callers need only one pass", function()
    local c = RX.compile([[(?i)s$]])
    local result, count = RX.gsub(c, "s", "posts")
    assert.are.equal("posts", result)
    assert.are.equal(1, count)
    local _, none = RX.gsub(c, "s", "post")
    assert.are.equal(0, none)
  end)

  it("rejects constructs it cannot translate instead of degrading silently", function()
    assert.has_error(function()
      RX.compile([[a{2,3}b]])
    end)
    assert.has_error(function()
      RX.compile([[(ab)*c]])
    end)
    assert.has_error(function()
      RX.compile([[a(?=b)c]])
    end)
  end)

  it("caches compiled patterns", function()
    assert.are.equal(RX.compile([[(?i)s$]]), RX.compile([[(?i)s$]]))
  end)
end)
