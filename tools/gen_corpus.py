#!/usr/bin/env python3
"""Build the differential-test corpus and its golden output.

The corpus is a plain word list committed at spec/data/corpus.txt. The golden
file records what CPython `inflection` 0.5.1 returns for every function in the
public API, so the Lua port can be compared byte for byte.

    # regenerate the golden file from the committed word list
    ./tools/gen_corpus.py

    # rebuild the word list itself from neutral sources (rarely needed)
    ./tools/gen_corpus.py --build-corpus [--upstream-src PATH]

Requires the reference implementation:  pip install inflection==0.5.1
"""
import argparse
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ROOT, reference  # noqa: E402

CORPUS = os.path.join(ROOT, "spec", "data", "corpus.txt")
GOLDEN = os.path.join(ROOT, "spec", "data", "golden_corpus.tsv")

# (column name, callable) for every string -> string function in the public API
def _build_functions(inflection):
    return [
        ("underscore", inflection.underscore),
        ("camelize", lambda s: inflection.camelize(s, True)),
        ("camelize_lower", lambda s: inflection.camelize(s, False)),
        ("dasherize", inflection.dasherize),
        ("humanize", inflection.humanize),
        ("pluralize", inflection.pluralize),
        ("singularize", inflection.singularize),
        ("tableize", inflection.tableize),
        ("titleize", inflection.titleize),
        ("parameterize", inflection.parameterize),
        ("transliterate", inflection.transliterate),
    ]

# Hand-written seeds: irregular nouns, uncountables, code-identifier shapes and
# the awkward edges (empty-ish, leading/trailing separators, mixed scripts).
SEEDS = """
person people man men woman women child children ox oxen mouse mice louse lice
goose geese tooth teeth foot feet deer sheep fish species series crisis thesis
analysis basis diagnosis prognosis synopsis parenthesis axis test quiz status
alias matrix vertex index appendix bus octopus virus radius nucleus syllabus
focus fungus cactus alumnus curriculum datum medium criterion phenomenon
church box dish switch fix process address case stack wish archive wife safe
half knife wolf life leaf shelf calf elf move sex zombie cow kine
search category query ability agency movie potato tomato buffalo hero echo
passerby database news information equipment money rice jeans
DeviceType device_type DEVICE_TYPE deviceType ApplicationController
RawScaledScorer IOError HTTPRequest XMLHttpRequest XMLHttpRequest area51
_RecipeIngredient ChildToy Country person_street_address employee_salary
author_id employee_id active_record action_web_service underground
free_bsd FreeBSD HTML CSS JSON snake_case camelCase PascalCase kebab-case
TrainCase SCREAMING_SNAKE __init__ __private _leading trailing_ double__under
x a A ab AB aB ABCd a1_B2 9lives _9lives foo bar baz qux quux
Malmö Garçons OpsÙ Ærøskøbing Aßlar Ünïcödé ünïcödé Ångström café naïve résumé
日本語 中文テスト Ünïcödé_mixed café_au_lait
Donald_E._Knuth Random text with *(bad)* characters Trailing bad characters
Squeeze   separators Test with + sign Allow_Under_Scores With-some-dashes
Retain_underscore man_from_the_boondocks x-men_the_last_stand
raiders_of_the_lost_ark TheManWithoutAPast david's_code Ana_Índia
""".split()

# Case variants exercised for every seed; the reference implementation is
# case-sensitive in several rules, so these catch ordering/folding mistakes.
def case_variants(word):
    return {word, word.lower(), word.upper(), word.capitalize(), word.title()}


def harvest_stdlib_words(limit):
    """Deterministic-ish English words and identifiers from the CPython stdlib."""
    import glob
    stdlib = os.path.dirname(os.__file__)
    words = set()
    for path in glob.glob(os.path.join(stdlib, "*.py")):
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        words.update(re.findall(r"\b[A-Za-z][A-Za-z_\-]{1,28}\b", text))
    return sorted(words)


def build_corpus(upstream_src, limit=2500):
    words = set(w for w in SEEDS if w.strip())
    for seed in list(words):
        words |= case_variants(seed)

    if upstream_src:
        test_file = os.path.join(upstream_src, "test_inflection.py")
        if os.path.exists(test_file):
            text = open(test_file, encoding="utf-8", errors="ignore").read()
            for lit in re.findall(r"""['"]([A-Za-z][A-Za-z0-9_'\- ]{0,30})['"]""", text):
                words.add(lit)
                words |= case_variants(lit)

    harvested = harvest_stdlib_words(limit)
    random.seed(20250101)
    if harvested:
        words |= set(random.sample(harvested, min(len(harvested), limit)))

    # Keep it filesystem- and TSV-safe: no tabs/newlines, non-empty.
    words = sorted(w for w in words if w and "\t" not in w and "\n" not in w)
    with open(CORPUS, "w", encoding="utf-8") as fh:
        fh.write("\n".join(words) + "\n")
    print("wrote %s: %d words" % (CORPUS, len(words)))


def write_golden():
    inflection = reference()
    version = getattr(inflection, "__version__", "?")
    fns = _build_functions(inflection)
    words = [l.rstrip("\n") for l in open(CORPUS, encoding="utf-8") if l.strip()]
    with open(GOLDEN, "w", encoding="utf-8") as fh:
        fh.write("# generated by tools/gen_corpus.py from spec/data/corpus.txt\n")
        fh.write("# reference: CPython inflection %s\n" % version)
        fh.write("# columns: word\t" + "\t".join(name for name, _ in fns) + "\n")
        for word in words:
            cells = [word]
            for _, fn in fns:
                try:
                    out = fn(word)
                except Exception as exc:                      # noqa: BLE001
                    out = "<ERR:%s>" % type(exc).__name__
                cells.append(str(out).replace("\t", " ").replace("\n", "\\n"))
            fh.write("\t".join(cells) + "\n")
    print("wrote %s: %d rows x %d functions" % (GOLDEN, len(words), len(fns)))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build-corpus", action="store_true",
                    help="rebuild spec/data/corpus.txt instead of the golden file")
    ap.add_argument("--upstream-src", metavar="PATH",
                    help="path to a jpvanhal/inflection source checkout; its test "
                         "literals are folded into the corpus")
    args = ap.parse_args()
    if args.build_corpus:
        build_corpus(args.upstream_src)
    write_golden()


if __name__ == "__main__":
    main()
