# inflection.lua

A pure Lua port of [jpvanhal/inflection][upstream] 0.5.1 — string
transformations for English: word-case conversion, regular and irregular
pluralization, and ordinals.

Output matches the reference implementation **byte for byte**. That claim is
checked mechanically rather than by eye: upstream's own pytest suite is
executed against the reference and recorded as 722 data-driven assertions, and
a 3,594-word corpus is compared against golden output for all eleven string
functions. Both agree on every case (see [Testing](#testing)).

- **No dependencies.** Nothing but a Lua interpreter.
- **No host API.** The same files run unmodified on LuaJIT 2.1 and Lua 5.1
  through 5.5 — `make test-all` checks every interpreter it can find.
- **Unicode aware.** Full case mapping and NFKD transliteration, which
  LuaJIT's `string.upper`/`string.lower` cannot do.

This project keeps its own semantic version — `inflection._VERSION`, currently
`1.0.0`. The release of the reference implementation whose behaviour it
reproduces is reported separately as `inflection._UPSTREAM_VERSION`, currently
`0.5.1`, and is pinned in CI.

```lua
local inflection = require("inflection")

inflection.camelize("device_type")              --> "DeviceType"
inflection.camelize("device_type", false)       --> "deviceType"
inflection.underscore("IOError")                --> "io_error"
inflection.pluralize("octopus")                 --> "octopi"
inflection.singularize("posts")                 --> "post"
inflection.titleize("man from the boondocks")   --> "Man From The Boondocks"
inflection.parameterize("Donald E. Knuth")      --> "donald-e-knuth"
inflection.ordinalize(-1021)                    --> "-1021st"
```

## Install

With [LuaRocks](https://luarocks.org):

```sh
luarocks install inflection
```

From a checkout — the rockspec installs the five modules under `inflection`:

```sh
git clone https://github.com/Hanaasagi/inflection.lua
cd inflection.lua
luarocks make          # or: make install
```

Without a package manager, put `lua/` on your package path:

```lua
package.path = "/path/to/inflection.lua/lua/?.lua;"
  .. "/path/to/inflection.lua/lua/?/init.lua;" .. package.path
local inflection = require("inflection")
```

Vendoring works too: copy the `lua/inflection/` directory into your project and
`require` it from there.

## Usage

### Word case

```lua
inflection.camelize(s, uppercase_first_letter)  -- default: true
inflection.underscore(s)
inflection.dasherize(s)
inflection.humanize(s)
inflection.titleize(s)
inflection.tableize(s)
```

| call | result |
| --- | --- |
| `camelize("device_type")` | `DeviceType` |
| `camelize("device_type", false)` | `deviceType` |
| `underscore("DeviceType")` | `device_type` |
| `underscore("IOError")` | `io_error` |
| `dasherize("puni_puni")` | `puni-puni` |
| `humanize("employee_salary")` | `Employee salary` |
| `humanize("author_id")` | `Author` |
| `titleize("x-men: the last stand")` | `X Men: The Last Stand` |
| `tableize("RawScaledScorer")` | `raw_scaled_scorers` |

### Pluralization

```lua
inflection.pluralize("octopus")     --> "octopi"
inflection.pluralize("sheep")       --> "sheep"       (uncountable)
inflection.pluralize("CamelOctopus")--> "CamelOctopi" (case is preserved)
inflection.singularize("octopi")    --> "octopus"
inflection.singularize("word")      --> "word"        (already singular)
```

Case is handled by the rules themselves, so `People`, `people` and `PEOPLE` all
inflect correctly. Words that are their own plural live in
`inflection.UNCOUNTABLES`, a set you can extend at runtime:

```lua
inflection.UNCOUNTABLES["pokemon"] = true
inflection.pluralize("pokemon")     --> "pokemon"
```

### URLs and ordinals

```lua
inflection.parameterize("Donald E. Knuth")      --> "donald-e-knuth"
inflection.parameterize("Donald E. Knuth", "_") --> "donald_e_knuth"
inflection.transliterate("Malmö")               --> "Malmo"
inflection.transliterate("Ærøskøbing")          --> "rskbing"  (no ASCII form: dropped)

inflection.ordinal(1)      --> "st"
inflection.ordinal(1003)   --> "rd"
inflection.ordinal(-11)    --> "th"
inflection.ordinalize(2)   --> "2nd"
inflection.ordinalize(-11) --> "-11th"
```

`ordinal` and `ordinalize` accept a number or a numeric string, and truncate
toward zero like Python's `int()`.

### Lower level

Two internal modules are usable on their own:

```lua
local regex = require("inflection.regex")
local compiled = regex.compile([[(?i)(octop|vir)(us|i)$]])
regex.gsub(compiled, [[\1us]], "octopi")    --> "octopus", 1

local utf8 = require("inflection.utf8")
utf8.len("日本語")        --> 3
utf8.upper("Ünïcödé")     --> "ÜNÏCÖDÉ"
utf8.sub("Ünïcödé", 1)    --> "nïcödé"      (Python slice semantics)
```

## Differences from the reference implementation

Deliberate, and covered by the suite unless noted:

- `camelize("", false)` raises, mirroring upstream's `""[0]` `IndexError`.
- `utf8.title()` falls back to `upper()`: code points with a distinct
  titlecase form (U+01C5 and friends) are not tabled separately.
- `utf8.is_word()` approximates Python's Unicode `\w`. ASCII uses
  `[0-9A-Za-z_]`; beyond ASCII a character counts as a word character when it
  has a case mapping, so non-ASCII digits and combining marks are reported as
  non-word. This affects the uncountable boundary check in `singularize` and
  the `\b` handling in `titleize`.
- `inflection.regex` only accepts the constructs the rule tables use. Anything
  else — counted quantifiers `{n,m}`, lookaround, `\b`/`\A`/`\Z`, in-pattern
  backreferences, a quantifier on a group other than `?` — raises at compile
  time rather than being silently approximated. See [Design](#design).

## Testing

```sh
make test        # the whole suite; needs only a Lua interpreter
make test-all    # the suite under luajit, lua5.1 and lua5.4
make bench       # per-function timing
make lint        # luacheck, if installed
make format      # stylua, if installed
```

The suite has no framework dependency: `spec/harness.lua` implements the subset
of the [busted](https://olivinelabs.com/busted/) API used here (`describe`,
`it`, `before_each`, `assert.are.equal`, ...). The specs are also valid busted
specs — `make test-busted` runs them under real busted (verified against 2.3.0),
which loads its own globals and never touches the harness.

`make check` runs everything: the suite, every interpreter available, busted if
installed, and luacheck if installed.

Four layers, 767 assertions in total:

| layer | file | assertions | what it proves |
| --- | --- | --- | --- |
| upstream suite | `spec/inflection_spec.lua` | 722 | recorded from upstream's own tests |
| differential corpus | `spec/corpus_spec.lua` | 11 | 3,594 words × 11 functions = 39,534 comparisons against golden output |
| unit | `spec/regex_spec.lua`, `spec/utf8_spec.lua` | 26 | the regex compiler and the Unicode layer in isolation |
| packaging | `spec/package_spec.lua` | 8 | module, rockspec, changelog and CI pins all agree |

Every spec bootstraps its own `package.path`, so one can be run on its own:
`busted spec/regex_spec.lua`.

The corpus is deliberately broad: irregular and uncountable nouns, acronym and
identifier shapes, leading/trailing/doubled separators, Latin-1 and CJK input.

### How the upstream cases were obtained

`spec/data/upstream_cases.lua` is **generated, not written**. 
`tools/gen_upstream_cases.py` installs a minimal `pytest` stub, wraps every
public function of the reference implementation, runs all 455 parametrized cases
of upstream's `test_inflection.py`, and records each
`(arguments -> return value)` pair. Since every upstream assertion passes, a
recorded return value *is* the expected behaviour — no hand translation of the
tests that could accidentally agree with this port instead of with upstream.

This is what makes state-dependent tests survive the move, e.g.
`test_uncountable_word_is_not_greedy`, which temporarily inserts `"ors"` into
`UNCOUNTABLES` and then checks that `sponsor` is *not* swallowed by it. Each
recorded row carries the extra uncountables that were in effect.

### Benchmark

`luajit spec/bench.lua`, 3,594 words:

```
function                      ms/word      share
singularize                    0.0328      37.0%
pluralize                      0.0241      27.2%
titleize                       0.0126      14.3%
parameterize                   0.0055       6.3%
underscore                     0.0029       3.3%
camelize (lower first)         0.0025       2.8%
transliterate                  0.0019       2.2%
camelize                       0.0018       2.0%
humanize                       0.0016       1.8%
utf8.lower                     0.0014       1.6%
utf8.upper                     0.0012       1.4%
dasherize                      0.0002       0.2%
total                          0.0886
```

`singularize` and `pluralize` dominate because they walk the rule table; the
other nine functions together cost under 0.03 ms per word.

## Design

```
lua/inflection/
  init.lua    public API, the twelve functions
  regex.lua   Python regex subset -> Lua pattern compiler
  utf8.lua    UTF-8 decoding and Unicode case mapping
  rules.lua   generated - upstream's rule tables, in original regex form
  data.lua    generated - NFKD and case mapping tables
```

Hand-written code is about 760 lines; the rest is generated data.

### Why there is a regex compiler

Upstream expresses pluralization as 83 `(pattern, replacement)` rules using
Python regular expressions. Lua patterns are not regular expressions and are
missing exactly three things those rules need, so `inflection.regex` compiles
them at load time:

1. **No case-insensitive flag.** `(?i)` is expanded into per-character folding:
   `quiz` becomes `[qQ][uU][iI][zZ]`, and a class like `[^aeiouy]` becomes
   `[^aeiouyAEIOUY]`.
2. **No alternation.** `|` is expanded into the cartesian product of patterns.
   Matching then picks the leftmost hit and, on a tie, the earliest expansion,
   which reproduces Python's leftmost-first semantics.
3. **Quantifiers cannot apply to a group.** `(es)?` becomes the two branches
   `es` and empty. Because branches of one rule can then contain different
   numbers of captures, every expansion carries a map from Python group numbers
   to Lua capture numbers, used when substituting `\1`…`\9`.

The 83 rules expand to 123 Lua patterns, compiled once and cached.

The alternative would have been to hand-translate the rules into Lua patterns.
That loses the ability to diff `rules.lua` against upstream, so the tables are
kept verbatim and compilation is mechanical instead.

Anything the compiler cannot express raises. This is a deliberate trade: if
upstream ever adds a rule using `{n,m}` or a lookahead, regenerating fails
loudly at `make regen` instead of quietly returning wrong words.

### Unicode

LuaJIT implements Lua 5.1 and has no `utf8` library, and `string.upper` /
`string.lower` are byte-wise and locale dependent. `inflection.utf8` therefore
decodes UTF-8 itself and looks up three tables that
`tools/gen_unicode_data.py` generates from CPython's `unicodedata`:

| table | entries | used for |
| --- | --- | --- |
| `NFKD` | 2,166 | `transliterate`: the ASCII part of a decomposition; absent means "drop the character" |
| `UPPER` | 1,526 | `upper`, including one-to-many mappings such as `ß -> SS` |
| `LOWER` | 1,434 | `lower` |

Decoding is total: truncated and invalid sequences degrade to single bytes, so
a malformed string can never hang the decoder.

## Repository layout

```
lua/inflection/   the library
spec/             tests, harness and the data they read
  data/           corpus.txt, golden_corpus.tsv, upstream_cases.lua
tools/            Python generators for every generated file
.github/          CI: the suite on three interpreters, plus a freshness check
```

Generated files are committed so `make test` needs nothing but an interpreter.
See [tools/README.md](tools/README.md) for regenerating them.

## License

MIT. See [LICENSE](LICENSE).

The rule tables are derived from [jpvanhal/inflection][upstream]
(MIT, Copyright (c) 2012-2020 Janne Vanhala), which in turn derives them from
Rails' ActiveSupport inflector. The Unicode tables are derived from the Unicode
Character Database via CPython's `unicodedata` module.

[upstream]: https://github.com/jpvanhal/inflection
