--- Tests for the UTF-8 decoder and the Unicode case mapping tables.
--- Bootstrap package.path so this spec also runs standalone, e.g.
--- `busted spec/utf8_spec.lua`, without depending on another spec loading first.
local SPEC_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]*$")) or "spec"
dofile(SPEC_DIR .. "/support.lua").setup_path()

local U = require("inflection.utf8")

describe("utf8 decoding", function()
  it("counts code points, not bytes", function()
    assert.are.equal(3, U.len("日本語"))
    assert.are.equal(2, U.len("🎉x"))
    assert.are.equal(7, U.len("Ünïcödé"))
    assert.are.equal(0, U.len(""))
  end)

  it("slices with Python's 0-based code point semantics", function()
    assert.are.equal("Ü", U.sub("Ünïcödé", 0, 1))
    assert.are.equal("nïcödé", U.sub("Ünïcödé", 1))
    assert.are.equal("", U.sub("abc", 5))
    assert.are.equal("b", U.sub("abc", 1, 2))
  end)

  it("survives truncated and invalid sequences without looping", function()
    -- Built with string.char, not "\xC3": hex escapes are Lua 5.2+ only and
    -- Lua 5.1 would read that as the four literal characters x, C, 3.
    local truncated = string.char(0xC3)
    local invalid = string.char(0xFF, 0xFE)
    assert.are.equal(2, select(2, U.codepoint_at(truncated, 1)))
    -- Two invalid lead bytes degrade to two single-byte code points, which
    -- keeps the decoder total and loop-free.
    assert.are.equal(2, U.len(invalid))
    assert.are.equal(invalid, U.sub(invalid, 0))
  end)

  it("round-trips encode/decode", function()
    for _, cp in ipairs({ 0x41, 0x7F, 0x80, 0x7FF, 0x800, 0xFFFF, 0x10000, 0x1F389 }) do
      assert.are.equal(cp, U.codepoint(U.encode(cp)))
    end
  end)
end)

describe("unicode case mapping", function()
  it("maps beyond ASCII, which string.upper/lower cannot", function()
    assert.are.equal("ÜNÏCÖDÉ", U.upper("Ünïcödé"))
    assert.are.equal("ünïcödé", U.lower("ÜNÏCÖDÉ"))
    assert.are.equal("í", U.lower("Í"))
  end)

  it("handles one-to-many mappings", function()
    assert.are.equal("SS", U.upper("ß"))
  end)

  it("leaves uncased scripts untouched", function()
    assert.are.equal("日本語", U.upper("日本語"))
    assert.are.equal("日本語", U.lower("日本語"))
  end)

  it("lowercases only ASCII when asked to", function()
    assert.are.equal("ana Í", U.lower_ascii("Ana Í"))
  end)

  it("implements str.capitalize semantics", function()
    assert.are.equal("Í", U.capitalize("Í"))
    assert.are.equal("'s", U.capitalize("'S"))
    assert.are.equal("", U.capitalize(""))
  end)
end)

describe("unicode character classes", function()
  it("treats letters as cased and symbols/CJK as uncased", function()
    assert.is_true(U.is_cased("í"))
    assert.is_false(U.is_cased("©"))
    assert.is_false(U.is_cased("日"))
    assert.is_true(U.is_cased("A"))
    assert.is_false(U.is_cased("1"))
  end)

  it("matches Python's \\w for ASCII and approximates it beyond", function()
    assert.is_true(U.is_word("a"))
    assert.is_true(U.is_word("_"))
    assert.is_true(U.is_word("7"))
    assert.is_false(U.is_word(" "))
    assert.is_true(U.is_word("é"))
  end)
end)

describe("NFKD decomposition table", function()
  it("keeps only the ASCII part of a decomposition", function()
    assert.are.equal("o", U.nfkd_ascii(0x00F6)) -- ö -> o + combining diaeresis
    assert.are.equal("12", U.nfkd_ascii(0x00BD)) -- ½ -> 1 ⁄ 2, fraction slash dropped
  end)

  it("returns nil for characters with no ASCII approximation", function()
    assert.is_nil(U.nfkd_ascii(0x00C6)) -- Æ
    assert.is_nil(U.nfkd_ascii(0x00DF)) -- ß
    assert.is_nil(U.nfkd_ascii(0x65E5)) -- 日
  end)
end)
