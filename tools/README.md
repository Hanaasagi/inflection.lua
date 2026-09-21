# tools

Python 3 generators for every committed-but-generated file in this repository.
Nothing here runs during `make test`; the outputs are checked in so the test
suite needs nothing but a Lua interpreter.

## Prerequisites

```sh
pip install inflection==0.5.1

# only needed by the two generators that read upstream's test suite,
# which the wheel does not ship:
git clone --branch 0.5.1 https://github.com/jpvanhal/inflection /tmp/upstream
```

`common.py` resolves all paths relative to the repository root and imports the
installed reference implementation, warning if its version is not 0.5.1.

## Generators

| script | writes | from |
| --- | --- | --- |
| `gen_rules.py` | `lua/inflection/rules.lua` | `inflection.PLURALS` / `SINGULARS` / `UNCOUNTABLES` |
| `gen_unicode_data.py` | `lua/inflection/data.lua` | CPython `unicodedata` |
| `gen_upstream_cases.py` | `spec/data/upstream_cases.lua` | upstream's `test_inflection.py`, executed |
| `gen_corpus.py` | `spec/data/corpus.txt`, `spec/data/golden_corpus.tsv` | seed list + CPython stdlib words |

Via make:

```sh
make regen UPSTREAM=/tmp/upstream   # all four
make rules UPSTREAM=/tmp/upstream   # just the rule tables
make unicode-data                   # just the Unicode tables
make cases UPSTREAM=/tmp/upstream   # just the recorded assertions
make golden                         # just the differential corpus
```

Always run `make test` afterwards.

## Determinism

Every generator must be reproducible. CI regenerates all four files twice under
different `PYTHONHASHSEED` values and fails if the two passes disagree, then
fails again if the result differs from what is committed. Two rules follow.

**Do not record anything environment specific in a generated file.**
`gen_unicode_data.py` writes the CPython *minor* version and the Unicode
database version into the header of `data.lua`, never the patch level. Two
builds of CPython 3.14 produce identical tables, so recording `3.14.7` would
make the committed file unreproducible from any machine whose patch level
differs - which is what CI's `setup-python` resolves to.

**Do not let set or dict iteration order reach the output.**
`gen_upstream_cases.py` sorts its rows for exactly this reason. Upstream
parametrizes `test_uncountability` over `inflection.UNCOUNTABLES`, a set, whose
iteration order moves with `PYTHONHASHSEED`, and CPython randomises that per
process. Recording order therefore differed between runs, and CI reported the
committed file as stale whenever the runner drew a different seed than the
machine that generated it.

## Notes for maintainers

**`gen_rules.py`** emits the patterns verbatim, in their original Python regex
form, so `lua/inflection/rules.lua` can be diffed against upstream. Translation
to Lua patterns happens at load time in `inflection.regex`. If upstream adds a
construct the compiler does not support, this shows up as a load-time error
naming the offending pattern rather than as a wrong answer.

**`gen_unicode_data.py`** snapshots the Unicode Character Database that ships
with the interpreter running it, so its output depends on the Python version:
CPython 3.12 carries Unicode 15.0.0, 3.13 carries 15.1.0 and 3.14 carries
16.0.0. The version used is recorded in the header of `data.lua`, and CI
compares it against the runner's own `unicodedata.unidata_version` before
regenerating. When you bump the Python pin in `.github/workflows/test.yml`, run
`make unicode-data` under that interpreter and commit the result.

It scans the whole code point range (0x80–0x10FFFF) and
keeps only entries whose value differs from the input, which is why the tables
stay at a few thousand rows. The three tables are stored as parallel strings
(a UTF-8 sequence of code points, plus newline-separated values) rather than as
a Lua table literal; that keeps the file at 32 KB instead of roughly 120 KB.
`inflection.utf8` expands them into hash tables once at load time.

**`gen_upstream_cases.py`** does not parse upstream's tests — it runs them.
Every public function is wrapped, the suite is executed through
`pytest_stub.py`, and each `(arguments -> return value)` pair is recorded. The
script aborts rather than writing output if any upstream case fails, so a
silently wrong golden file is not possible. Rows also carry the entries that
`UNCOUNTABLES` gained during the run, which is how
`test_uncountable_word_is_not_greedy` is reproduced.

**`gen_corpus.py --build-corpus`** rebuilds the word list from a hand-written
seed list (irregular nouns, uncountables, identifier shapes, separator edge
cases, Latin-1 and CJK samples) expanded with case variants, plus words
harvested from the local CPython standard library under a fixed random seed.
Pass `--upstream-src` to also fold in the literals from upstream's test suite.
Rebuilding the word list invalidates the golden file, so run it without
arguments afterwards. In normal maintenance you only regenerate the golden:
`make golden`.

CI re-runs all four generators and fails if the committed files differ, so a
stale generated file cannot slip in.
