# Changelog

All notable changes to this project are documented here.

This project keeps its own semantic version, reported as
`inflection._VERSION`. The release of [jpvanhal/inflection][upstream] whose
behaviour it reproduces is tracked separately as
`inflection._UPSTREAM_VERSION`, and is pinned in CI.

## 1.0.0

Initial release. Reproduces upstream `inflection` 0.5.1 byte for byte.

- All twelve functions of upstream `inflection` 0.5.1: `camelize`,
  `dasherize`, `humanize`, `ordinal`, `ordinalize`, `parameterize`,
  `pluralize`, `singularize`, `tableize`, `titleize`, `transliterate`,
  `underscore`, plus the mutable `UNCOUNTABLES` set.
- `inflection.regex`: compiler from the Python regex subset used by the rule
  tables to Lua patterns. Handles `(?i)`, alternation and optional groups;
  raises on anything it cannot express rather than approximating it.
- `inflection.utf8`: UTF-8 decoding and Unicode case mapping backed by
  generated NFKD / upper / lower tables (2166 / 1526 / 1434 entries).
- Test suite of 767 assertions: the upstream pytest suite recorded as data
  (722), a 3,594-word differential corpus against golden output (11), unit
  tests for the regex compiler and the Unicode layer (26), and packaging
  invariants that keep `_VERSION`, the rockspec, the changelog and the CI pins
  from drifting apart (8).
- Verified on LuaJIT 2.1 and Lua 5.1, 5.2, 5.3, 5.4 and 5.5, and under
  busted 2.3.0.

[upstream]: https://github.com/jpvanhal/inflection
