"""Offline checks of the probe addon (tools/probe/AzTw_Probe), run by tools/check_docs.py.

  1. Every Lua file of the probe compiles as Lua 5.1: with lupa (lupa.lua51) or with a Lua 5.1 `luac`. When neither is
     installed the syntax check is skipped with a notice (CI installs lupa and uses --require, so it never skips).
  2. The TOC declares "## Interface: 16001" and AzTw_ProbeDB, and lists exactly the Lua files of the folder.
  3. The probe is never distributed: .pkgmeta ignores tools/.

Usage: python -I -X utf8 tools/check_probe.py [--require]
  --require   fail, instead of skipping, when no Lua 5.1 compiler is available.
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBE = os.path.join(ROOT, "tools", "probe", "AzTw_Probe")


def lupa_compiler():
    try:
        from lupa import lua51
    except ImportError:
        return None
    load = lua51.LuaRuntime().eval(
        "function(source, name) local fn, err = loadstring(source, name) if fn then return nil end return err end")
    return lambda path, name: load(read(path), "@" + name)


def luac_compiler():
    for exe in ("luac5.1", "luac"):
        found = shutil.which(exe)
        if not found:
            continue
        version = subprocess.run([found, "-v"], capture_output=True, text=True)
        if "Lua 5.1" not in version.stdout + version.stderr:   # a newer luac accepts syntax the game refuses
            continue

        def compile_file(path, name, luac=found):
            proc = subprocess.run([luac, "-p", path], capture_output=True, text=True)
            return None if proc.returncode == 0 else proc.stderr.strip()
        return compile_file
    return None


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def check(problems, require=False):
    if not os.path.isdir(PROBE):
        problems.append("tools/probe/AzTw_Probe/ is missing")
        return
    lua_files = sorted(f for f in os.listdir(PROBE) if f.endswith(".lua"))

    toc = read(os.path.join(PROBE, "AzTw_Probe.toc")).splitlines()
    for line in ("## Interface: 16001", "## SavedVariables: AzTw_ProbeDB"):
        if line not in toc:
            problems.append(f"AzTw_Probe.toc: missing line '{line}'")
    listed = [line.strip() for line in toc if line.strip() and not line.startswith("#")]
    if sorted(listed) != lua_files:
        problems.append(f"AzTw_Probe.toc lists {sorted(listed)}, the folder has {lua_files}")

    if not re.search(r"^ignore:\n(?:[ \t]+-.*\n)*?[ \t]+- tools[ \t]*$", read(os.path.join(ROOT, ".pkgmeta")), re.M):
        problems.append(".pkgmeta: 'tools' is not in the ignore list (the probe must never be distributed)")

    compile_file = lupa_compiler() or luac_compiler()
    if compile_file is None:
        # Isolated mode (-I) hides the user's site-packages, where lupa may live: try once without it.
        if sys.flags.isolated:
            proc = subprocess.run([sys.executable, "-X", "utf8", os.path.abspath(__file__), "--require"],
                                  capture_output=True, text=True)
            if proc.returncode == 0:
                return
            if "no Lua 5.1 compiler" not in proc.stdout:
                problems.extend((proc.stdout + proc.stderr).strip().splitlines()[:-1])
                return
        if require:
            problems.append("probe syntax check: no Lua 5.1 compiler (pip install lupa)")
        else:
            print("probe syntax check skipped: no Lua 5.1 compiler (lupa or luac 5.1).")
        return
    for name in lua_files:
        error = compile_file(os.path.join(PROBE, name), "tools/probe/AzTw_Probe/" + name)
        if error:
            problems.append(f"Lua syntax: {error}")


def main(argv):
    problems = []
    check(problems, require="--require" in argv)
    for p in problems:
        print(p)
    print(f"probe checked, {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
