"""Shared helpers for the code generators in tools/.

Every generator derives its paths from this file's location, so the repository
can live anywhere, and imports the *installed* reference implementation:

    pip install inflection==0.5.1
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA_DIR = os.path.join(ROOT, "lua", "inflection")
SPEC_DATA_DIR = os.path.join(ROOT, "spec", "data")
TOOLS_DIR = os.path.join(ROOT, "tools")

REFERENCE_VERSION = "0.5.1"


def reference(upstream_src=None):
    """Import the reference `inflection` module.

    `upstream_src` optionally points at a source checkout, which is only needed
    by tools that read upstream's test_inflection.py (the wheel does not ship
    tests). A checkout also takes precedence over the installed copy.
    """
    if upstream_src:
        upstream_src = os.path.abspath(os.path.expanduser(upstream_src))
        if not os.path.isdir(upstream_src):
            sys.exit("no such directory: %s" % upstream_src)
        sys.path.insert(0, upstream_src)
    try:
        import inflection
    except ImportError:
        sys.exit("reference implementation missing: pip install inflection==%s"
                 % REFERENCE_VERSION)

    version = getattr(inflection, "__version__", None)
    if version and version != REFERENCE_VERSION:
        print("WARNING: reference inflection is %s, this port targets %s"
              % (version, REFERENCE_VERSION), file=sys.stderr)
    return inflection


def lua_string(text):
    """Render a Python str as a Lua double-quoted literal, keeping UTF-8 as is."""
    out = ['"']
    for ch in text:
        code = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code < 0x20 or code == 0x7F:
            out.append("\\%d" % code)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_long_string(text):
    """Render a Python str as a Lua long bracket literal."""
    assert "]]" not in text, "value contains ]], needs a longer bracket level"
    return "[==[" + text + "]==]"


def write(path, body):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(body)
    print("wrote %s (%.1f KB)" % (os.path.relpath(path, ROOT), os.path.getsize(path) / 1024))
