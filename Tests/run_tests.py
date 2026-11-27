"""Offline tests of Azeroth Threatwarden: the addon runs in Lua 5.1 (through lupa) on a mock WoW client.

Adapted from Azeroth Accord (Tests/run_tests.py), same owner, GPL-3.0 (ADR 0012).

Usage: python -X utf8 Tests/run_tests.py [filter] [-v] [--long]
  filter   run only the tests whose "file > group > test" name contains this text (case-insensitive)
  -v       print a traceback under every failure
  --long   also run the long scenarios of Tests/long/ (the same as the environment variable AZTW_LONG=1; the
           "Long tests" workflow runs them, .github/workflows/long-tests.yml)
Exit code: 0 all tests passed, 1 a test failed or none ran, 2 the harness could not start (lupa or libraries missing,
bad TOC).

What it does (ADR 0010): reads AzerothThreatwarden.toc, follows every embeds.xml / Include / Script, loads the mock
client (Tests/mock/*.lua), then the files of the addon in TOC order exactly like the client (each file gets the addon
name and one private table), restores the SavedVariables, fires ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD
and runs every Tests/test_*.lua, each test on a freshly built client. The Ace3, LibDataBroker and LibDBIcon libraries
are the real ones from AzerothThreatwarden/Libs/ (tools/fetch_libs.py downloads them; this script runs it when they are
missing).
"""
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDON_NAME = "AzerothThreatwarden"
ADDON_DIR = os.path.join(ROOT, ADDON_NAME)
LUPA_PINNED = "2.8"
# The Forever API dump is optional: with it the mock rejects event names the client does not have (ADR 0002).
API_DUMP = os.environ.get("AZTW_API_DUMP") or os.path.join(os.path.dirname(ROOT), "WoW-Addons", "docs", "api.json")


def die(message, code=2):
    sys.stderr.write(message + "\n")
    sys.exit(code)


try:
    from lupa import lua51
    import lupa
except ImportError:
    die(f"lupa is required: python -m pip install --user lupa=={LUPA_PINNED}")


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def split_path(value):
    return re.split(r"[\\/]", value.strip())


def read_toc(path):
    """Returns ({field: value}, [file lines in order])."""
    fields, files = {}, []
    with open(path, encoding="utf-8-sig") as f:
        for raw in f.read().splitlines():
            line = raw.strip()
            m = re.match(r"^##\s*([^:]+?)\s*:\s*(.*)$", line)
            if m:
                fields[m.group(1)] = m.group(2)
            elif line and not line.startswith("#"):
                files.append(re.sub(r"\s*\[[^\]]*\]\s*$", "", line))   # [AllowLoadGameMode ...] and similar
    return fields, files


def local_name(element):
    return element.tag.rsplit("}", 1)[-1]


def exact_case(path):
    """True when every component of `path` below the repository root has exactly the case on disk (the client is
    case-insensitive and CI is not: a TOC line that works on Windows must still work on Linux)."""
    current = ROOT
    for part in os.path.relpath(path, ROOT).split(os.sep):
        if part not in os.listdir(current):
            return False
        current = os.path.join(current, part)
    return True


def expand(files, base, plan, missing):
    """Appends {path, name | code} entries for every Lua file, following XML files in document order."""
    for entry in files:
        path = os.path.normpath(os.path.join(base, *split_path(entry)))
        if not os.path.isfile(path) or not exact_case(path):
            missing.append(path)
            continue
        if path.lower().endswith(".xml"):
            expand_xml(path, plan, missing)
        else:
            plan.append({"path": path, "name": rel(path)})


def expand_xml(path, plan, missing):
    base = os.path.dirname(path)
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        die(f"{rel(path)}: not valid XML ({e})")
    for element in tree.getroot().iter():
        kind = local_name(element)
        target = element.get("file")
        if kind in ("Script", "Include") and target:
            expand([target], base, plan, missing)
        elif kind == "Script" and (element.text or "").strip():
            plan.append({"code": element.text, "name": rel(path) + " (inline script)"})


def build_plan():
    toc = os.path.join(ADDON_DIR, ADDON_NAME + ".toc")
    if not os.path.isfile(toc):
        die(f"{rel(toc)} is missing")
    fields, files = read_toc(toc)
    plan, missing = [], []
    expand(files, ADDON_DIR, plan, missing)
    return fields, plan, missing


def load_events():
    """Names of the events of the Forever client, or None when the API dump is not available."""
    if not os.path.isfile(API_DUMP):
        return None
    with open(API_DUMP, encoding="utf-8") as f:
        dump = json.load(f)
    names = set()
    for system in dump.get("systems", []):
        for event in system.get("events", []):
            names.add(event.get("literalName") or event.get("name"))
    return sorted(n for n in names if n) or None


def lua_files(folder, label, pattern=r"^.*\.lua$"):
    """[{path, name}] for the Lua files of a folder, sorted by name; empty when the folder does not exist."""
    if not os.path.isdir(folder):
        return []
    return [{"path": os.path.join(folder, n), "name": label + n}
            for n in sorted(os.listdir(folder)) if re.match(pattern, n) and n.endswith(".lua")]


def b(text):
    return text.encode("utf-8")


def main(argv):
    flt, verbose, long_runs = "", False, os.environ.get("AZTW_LONG") == "1"
    for arg in argv:
        if arg == "-v":
            verbose = True
        elif arg == "--long":
            long_runs = True
        elif arg.startswith("-"):
            die(f"unknown option {arg}")
        else:
            flt = arg
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if lupa.__version__ != LUPA_PINNED:
        print(f"note: lupa {lupa.__version__} is installed, the project pins {LUPA_PINNED}")

    fields, plan, missing = build_plan()
    if missing and any("Libs" in split_path(rel(m)) for m in missing):
        print("Libraries are missing: running tools/fetch_libs.py")
        sys.stdout.flush()
        result = subprocess.run([sys.executable, "-I", "-X", "utf8", os.path.join(ROOT, "tools", "fetch_libs.py")])
        if result.returncode != 0:
            die("Could not fetch the libraries. Run: python -I -X utf8 tools/fetch_libs.py")
        fields, plan, missing = build_plan()
    if missing:
        die("Files listed by the TOC or embeds.xml are missing:\n  " + "\n  ".join(rel(m) for m in missing))

    mock_files = lua_files(os.path.join(HERE, "mock"), "Tests/mock/")
    test_files = lua_files(HERE, "", r"^test_")
    if not test_files:
        die("No Tests/test_*.lua files found")
    if long_runs:
        test_files += lua_files(os.path.join(HERE, "long"), "long/", r"^test_")
    saved_vars = [v.strip() for key in ("SavedVariables", "SavedVariablesPerCharacter")
                  for v in fields.get(key, "").split(",") if v.strip()]
    events = load_events()

    # encoding=None: Lua strings are bytes, so accented text passes through untouched.
    lua = lua51.LuaRuntime(encoding=None, unpack_returned_tuples=True, register_eval=False, register_builtins=False)

    def read_file(path):
        with open(path.decode("utf-8"), "rb") as f:
            return f.read()

    def log(text):
        sys.stdout.write(text.decode("utf-8", "replace"))
        sys.stdout.flush()

    def file_table(files):
        return lua.table_from([lua.table_from({b"path": b(f["path"]), b"name": b(f["name"])}) for f in files])

    cfg = lua.table_from({
        b"addonName": b(ADDON_NAME),
        b"root": b(ROOT),
        b"assertPath": b(os.path.join(HERE, "lib", "assert.lua")),
        b"fightPath": b(os.path.join(HERE, "lib", "fight.lua")),
        b"raidPath": b(os.path.join(HERE, "lib", "raid.lua")),
        b"csvPath": b(os.path.join(HERE, "lib", "csv.lua")),
        b"csvPath": b(os.path.join(HERE, "lib", "csv.lua")),
        b"tocFields": lua.table_from({b(k): b(v) for k, v in fields.items()}),
        b"savedVars": lua.table_from([b(v) for v in saved_vars]),
        b"plan": lua.table_from([lua.table_from({(b"code" if "code" in p else b"path"): b(p.get("code") or p["path"]),
                                                  b"name": b(p["name"])}) for p in plan]),
        b"mockFiles": file_table(mock_files),
        b"testFiles": file_table(test_files),
        b"events": lua.table_from({b(e): True for e in events}) if events else None,
        b"filter": b(flt),
        b"verbose": verbose,
        b"long": long_runs,
        b"readfile": read_file,
        b"log": log,
    })

    compile_chunk = lua.eval(b"function(src, name) local c, e = loadstring(src, name); if not c then error(e) end; return c end")
    chunk = compile_chunk(read_file(b(os.path.join(HERE, "lib", "harness.lua"))), b"@Tests/lib/harness.lua")
    H = chunk(cfg)
    print(f"Azeroth Threatwarden offline tests: {len(plan)} addon and library files, {len(mock_files)} mock files"
          + (", long scenarios included" if long_runs else "")
          + ("" if events else ", API dump not found (event names are not validated)"))
    passed, failed, files = H.run()
    print(f"\n{passed + failed} tests in {files} files: {passed} passed, {failed} failed.")
    return 1 if failed or passed == 0 else 0   # running nothing is not a pass


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
