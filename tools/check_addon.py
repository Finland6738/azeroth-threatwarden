"""Offline checks of the addon folder: TOC fields, listed files, embeds.xml (Libs only when fetched), the locale tables,
colours and media.

Adapted from Azeroth Accord (tools/check_addon.py), same owner, GPL-3.0 (ADR 0012).

  * TOC: Interface 16001, the required fields (SPEC-01, ADR 0011), every listed file exists, every Lua file of the addon
    is loaded, the Addon Compartment functions named by the TOC are defined.
  * embeds.xml loads only libraries pinned in .pkgmeta (their files are checked once tools/fetch_libs.py fetched them).
  * Locales (ADR 0009): every file of Locales/ registers the table of its own language, one `KEY = "text"` per line,
    with exactly the keys of enUS; every L["KEY"] or L.KEY used in the code exists in enUS.
  * No colour outside UI/Theme.lua (a line that must write one says `theme-ok`).
  * Media: every media path used exists, every file of Media/ is described in docs/third-party.md, every font folder has
    its licence text, and once the logo texture exists (M1.6) the TOC shows it as IconTexture.

Usage: python -I -X utf8 tools/check_addon.py (also called by tools/check_docs.py, with a self-test on made-up addons)
"""
import os
import re
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import fetch_libs  # noqa: E402  (the one parser of the externals block)

NAME = "AzerothThreatwarden"
INTERFACE = "16001"
REQUIRED_TOC_KEYS = ("Title", "Notes", "Notes-itIT", "Author", "Version", "X-Credits")
EXACT_TOC = {
    "SavedVariables": NAME + "DB",
    "SavedVariablesPerCharacter": NAME + "CharDB",
    "AddonCompartmentFunc": NAME + "_OnAddonCompartmentClick",
    "AddonCompartmentFuncOnEnter": NAME + "_OnAddonCompartmentEnter",
    "AddonCompartmentFuncOnLeave": NAME + "_OnAddonCompartmentLeave",
    "X-License": "GPL-3.0",
}
COMPARTMENT_KEYS = ("AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave")
ICON = "Interface\\AddOns\\" + NAME + "\\Media\\logo_64"
BASE_LOCALE = "enUS"


def _path(base, rel):
    return os.path.join(base, *re.split(r"[\\/]", rel.strip()))


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def read_toc(text):
    meta, files = {}, []
    for line in text.splitlines():
        m = re.match(r"^##\s*([\w-]+)\s*:\s*(.*)$", line)
        if m:
            meta[m.group(1)] = m.group(2).strip()
        elif line.strip() and not line.startswith("#"):
            files.append(line.strip())
    return meta, files


class Addon:
    """The paths of one repository (the real one, or a made-up one in the self-test)."""

    def __init__(self, root):
        self.root = root
        self.dir = os.path.join(root, NAME)
        self.toc = os.path.join(self.dir, NAME + ".toc")

    def rel(self, path):
        return os.path.relpath(path, self.root).replace(os.sep, "/")

    def lua_files(self):
        """Every Lua file of the addon except the libraries."""
        for folder, subfolders, names in os.walk(self.dir):
            if folder == self.dir and "Libs" in subfolders:
                subfolders.remove("Libs")
            subfolders.sort()
            for name in sorted(names):
                if name.endswith(".lua"):
                    yield os.path.join(folder, name)


# --- TOC and embeds ------------------------------------------------------------------------------------------------

def check_embeds(addon, embeds, externals, loaded, problems):
    base = os.path.dirname(embeds)
    for kind, rel in re.findall(r'<(Script|Include)\s+file="([^"]+)"', _read(embeds)):
        target = os.path.normpath(_path(base, rel))
        inside = os.path.relpath(target, addon.dir).replace(os.sep, "/")
        loaded.add(inside)
        if inside.startswith("Libs/"):
            pinned = any((NAME + "/" + inside).startswith(e + "/") for e in externals)
            if not pinned:
                problems.append(f"{addon.rel(embeds)}: {rel} is not under an external pinned in .pkgmeta")
            if not os.path.isdir(os.path.join(addon.dir, "Libs")):
                continue   # libraries are fetched, not committed
        if not os.path.isfile(target):
            problems.append(f"{addon.rel(embeds)}: missing {rel}")
        elif kind == "Include" and rel.lower().endswith(".xml"):
            check_embeds(addon, target, externals, loaded, problems)


def check_toc(addon, problems):
    if not os.path.isfile(addon.toc):
        problems.append(f"{NAME}/{NAME}.toc is missing")
        return None
    meta, files = read_toc(_read(addon.toc))
    if meta.get("Interface") != INTERFACE:
        problems.append(f"TOC Interface is {meta.get('Interface')!r}, expected {INTERFACE}")
    for key in REQUIRED_TOC_KEYS:
        if not meta.get(key):
            problems.append(f"TOC is missing ## {key}")
    for key, value in EXACT_TOC.items():
        if meta.get(key) != value:
            problems.append(f"TOC ## {key} is {meta.get(key)!r}, expected {value!r}")
    if not files:
        problems.append("TOC lists no files")
    pkgmeta = os.path.join(addon.root, ".pkgmeta")
    externals = fetch_libs.parse_externals(_read(pkgmeta)) if os.path.isfile(pkgmeta) else {}
    loaded = set()
    for rel in files:
        target = _path(addon.dir, rel)
        loaded.add(rel.replace("\\", "/"))
        if not os.path.isfile(target):
            problems.append(f"TOC lists a missing file: {rel}")
        elif rel.lower().endswith(".xml"):
            check_embeds(addon, target, externals, loaded, problems)
    code = []
    for path in addon.lua_files():
        inside = os.path.relpath(path, addon.dir).replace(os.sep, "/")
        if inside not in loaded:
            problems.append(f"{NAME}/{inside} is not listed in the TOC")
        code.append(_read(path))
    code = "\n".join(code)
    for key in COMPARTMENT_KEYS:
        function = meta.get(key)
        if function and not re.search(r"^function\s+" + re.escape(function) + r"\s*\(", code, re.M):
            problems.append(f"TOC ## {key} names {function}, which no file defines")
    return meta


# --- locales -------------------------------------------------------------------------------------------------------

REGISTER = re.compile(r'^ns\.Locale\.Register\(\s*"(\w+)"\s*,\s*\{[ \t]*\n(.*?)^\}\)', re.M | re.S)
LOCALE_LINE = re.compile(r'^\s*([A-Z][A-Z0-9_]*)\s*=\s*"(?:[^"\\]|\\.)*"\s*,?\s*(?:--.*)?$')
KEY_USE = re.compile(r'(?<![\w.])(?:ns\.)?L(?:\[\s*"(\w+)"\s*\]|\.([A-Z][A-Z0-9_]*)\b)')


def locale_keys(addon, path, problems):
    """The keys of one file of Locales/, None when it has no table."""
    code = os.path.splitext(os.path.basename(path))[0]
    m = REGISTER.search(_read(path))
    if not m:
        problems.append(f"{addon.rel(path)}: no ns.Locale.Register(\"{code}\", {{ ... }}) table")
        return None
    if m.group(1) != code:
        problems.append(f"{addon.rel(path)}: registers {m.group(1)!r}, the file name says {code!r}")
    keys = set()
    for line in m.group(2).splitlines():
        if not line.strip() or line.strip().startswith("--"):
            continue
        entry = LOCALE_LINE.match(line)
        if not entry:
            problems.append(f"{addon.rel(path)}: a line that is not one KEY = \"text\": {line.strip()[:60]}")
        elif entry.group(1) in keys:
            problems.append(f"{addon.rel(path)}: {entry.group(1)} is defined twice")
        else:
            keys.add(entry.group(1))
    return keys


def check_locales(addon, problems):
    folder = os.path.join(addon.dir, "Locales")
    names = sorted(f for f in os.listdir(folder) if f.endswith(".lua")) if os.path.isdir(folder) else []
    for required in (BASE_LOCALE + ".lua", "itIT.lua"):
        if required not in names:
            problems.append(f"{NAME}/Locales/{required} is missing (ADR 0009)")
    if BASE_LOCALE + ".lua" not in names:
        return
    base = locale_keys(addon, os.path.join(folder, BASE_LOCALE + ".lua"), problems) or set()
    for name in names:
        if name == BASE_LOCALE + ".lua":
            continue
        keys = locale_keys(addon, os.path.join(folder, name), problems)
        if keys is None:
            continue
        for key in sorted(keys - base):
            problems.append(f"Locales/{name}: {key} is not an English key (typo?)")
        for key in sorted(base - keys):
            problems.append(f"Locales/{name}: {key} is missing (ADR 0009)")
    for path in addon.lua_files():
        if os.path.dirname(path) == folder:
            continue
        code = "\n".join(line.split("--", 1)[0] for line in _read(path).splitlines())
        used = {a or b for a, b in KEY_USE.findall(code)} | set(re.findall(r'labelKey\s*=\s*"(\w+)"', code))
        for key in sorted(used - base):
            problems.append(f"{addon.rel(path)}: L[\"{key}\"] has no string in Locales/{BASE_LOCALE}.lua")


# --- colours -------------------------------------------------------------------------------------------------------

# Colours written as values: a hex colour, a |c escape, or numbers given to a colour setter or to a GameTooltip line.
# Only the code part of a line is read (not the comment).
HARD_COLOURS = (
    (re.compile(r"#[0-9A-Fa-f]{6}\b"), "a hex colour"),
    (re.compile(r"\|c[0-9A-Fa-f]{8}"), "a |c colour escape"),
    (re.compile(r"\b(?:SetColorTexture|SetVertexColor|SetTextColor|SetShadowColor|SetGradient|CreateColor)\s*\(\s*-?\.?[0-9]"),
     "a colour given as numbers"),
    (re.compile(r"\bAdd(?:Double)?Line\s*\(.*,\s*-?\.?[0-9][0-9.]*\s*,\s*-?\.?[0-9][0-9.]*\s*,\s*-?\.?[0-9]"),
     "a tooltip line coloured with numbers"),
)


def check_colours(addon, problems):
    theme = os.path.join(addon.dir, "UI", "Theme.lua")
    for path in addon.lua_files():
        if path == theme:
            continue
        for number, line in enumerate(_read(path).splitlines(), 1):
            if "theme-ok" in line:
                continue
            code = line.split("--", 1)[0]
            for pattern, what in HARD_COLOURS:
                if pattern.search(code):
                    problems.append(f"{addon.rel(path)}:{number}: {what} outside UI/Theme.lua "
                                    "(use a theme token, or mark the line theme-ok)")


# --- media ---------------------------------------------------------------------------------------------------------

MEDIA_PATH = re.compile(r"Media[\\/]+([A-Za-z0-9_.\\/-]+?)(?=[\"'\s]|$)", re.M)


def check_media(addon, meta, problems):
    media = os.path.join(addon.dir, "Media")
    files = sorted(os.path.relpath(os.path.join(folder, name), media).replace(os.sep, "/")
                   for folder, _, names in os.walk(media) for name in names)
    have = {os.path.splitext(f)[0] for f in files}
    for path in [addon.toc] + list(addon.lua_files()):
        if not os.path.isfile(path):
            continue
        for m in MEDIA_PATH.finditer(_read(path)):
            rel = os.path.splitext(re.sub(r"[\\/]+", "/", m.group(1)).strip("/"))[0]
            if rel and rel not in have:
                problems.append(f"{addon.rel(path)} uses Media/{rel} but the file is missing")
    third = os.path.join(addon.root, "docs", "third-party.md")
    if not os.path.isfile(third):
        problems.append("docs/third-party.md is missing")
    text = _read(third) if os.path.isfile(third) else ""
    for rel in files:
        if os.path.basename(rel) not in text:
            problems.append(f"Media/{rel} is not described in docs/third-party.md (its source and licence)")
    families = {os.path.basename(f).split("-")[0] for f in files if f.startswith("Fonts/") and f.endswith(".ttf")}
    for family in sorted(families):
        if f"Fonts/{family}-OFL.txt" not in files:
            problems.append(f"Media/Fonts/{family}-OFL.txt (the licence) is missing")
    if "logo_64" in have and meta.get("IconTexture") != ICON:
        problems.append(f"TOC ## IconTexture must be the addon's logo ({ICON}): Media/logo_64 exists")


def run(root):
    problems = []
    addon = Addon(root)
    meta = check_toc(addon, problems)
    if meta is None:
        return problems
    check_locales(addon, problems)
    check_colours(addon, problems)
    check_media(addon, meta, problems)
    return problems


# --- self-test -----------------------------------------------------------------------------------------------------

def _good_files():
    toc = "\n".join(
        [f"## Interface: {INTERFACE}"] + [f"## {k}: x" for k in REQUIRED_TOC_KEYS] +
        [f"## {k}: {v}" for k, v in EXACT_TOC.items()] +
        ["", "embeds.xml", "Locales\\enUS.lua", "Locales\\itIT.lua", "Core\\Init.lua", ""])
    functions = "".join(f"function {EXACT_TOC[k]}() end\n" for k in COMPARTMENT_KEYS)
    locale = 'local _, ns = ...\nns.Locale.Register("%s", {\n\tHELLO = "%s",   -- a greeting\n})\n'
    return {
        ".pkgmeta": f"externals:\n  {NAME}/Libs/Lib:\n    url: https://github.com/a/b\n    tag: v1\n",
        "docs/third-party.md": "# Third party\n",
        f"{NAME}/{NAME}.toc": toc,
        f"{NAME}/embeds.xml": '<Ui><Script file="Libs\\Lib\\Lib.lua"/></Ui>\n',
        f"{NAME}/Locales/enUS.lua": locale % ("enUS", "Hello"),
        f"{NAME}/Locales/itIT.lua": locale % ("itIT", "Ciao"),
        f"{NAME}/Core/Init.lua": 'local _, ns = ...\nlocal L = ns.L\nprint(L["HELLO"], L.HELLO)\n' + functions,
    }


def _run_files(files):
    with tempfile.TemporaryDirectory() as root:
        for name, text in files.items():
            path = _path(root, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
        return run(root)


def self_test(problems):
    """The rules must accept a good addon and refuse each kind of bad one."""
    good = _good_files()
    found = _run_files(good)
    if found:
        problems.append(f"tools/check_addon.py: the good test addon was refused: {found}")
        return
    toc, init, it = f"{NAME}/{NAME}.toc", f"{NAME}/Core/Init.lua", f"{NAME}/Locales/itIT.lua"

    def change(name, old, new):
        return {**good, name: good[name].replace(old, new)}

    cases = {
        "a wrong Interface": (change(toc, INTERFACE, "11500"), "Interface"),
        "a wrong SavedVariables": (change(toc, NAME + "CharDB", "OtherDB"), "SavedVariablesPerCharacter"),
        "a missing file": (change(toc, "Core\\Init.lua", "Core\\Init.lua\nCore\\Gone.lua"), "missing file"),
        "an unlisted file": ({**good, f"{NAME}/Core/Extra.lua": ""}, "not listed in the TOC"),
        "an undefined Compartment function": (change(init, "function " + NAME + "_OnAddonCompartmentLeave", "local function x"),
                                              "no file defines"),
        "an unpinned library": (change(f"{NAME}/embeds.xml", "Libs\\Lib\\", "Libs\\Other\\"), "not under an external"),
        "a fetched Libs folder without the file": ({**good, f"{NAME}/Libs/Lib/Readme.txt": ""}, "missing Libs"),
        "a key without English": (change(init, 'L["HELLO"]', 'L["NOPE"]'), 'L["NOPE"]'),
        "a missing Italian key": (change(it, "HELLO", "OTHER"), "HELLO is missing"),
        "an unreadable locale line": (change(it, '\tHELLO = "Ciao",', '\tHELLO = "Ci" .. "ao",'), "not one KEY"),
        "a wrong locale code": (change(it, '"itIT"', '"frFR"'), "file name says"),
        "a colour escape": (change(init, "print(", 'print("|cff00ff00", '), "colour escape"),
        "missing media": (change(init, "print(", 'print("Media\\\\gone", '), "file is missing"),
        "undescribed media": ({**good, f"{NAME}/Media/dot.tga": ""}, "not described"),
        "a logo without IconTexture": ({**good, f"{NAME}/Media/logo_64.tga": "",
                                        "docs/third-party.md": "logo_64.tga"}, "IconTexture"),
    }
    for label, (files, expect) in cases.items():
        found = _run_files(files)
        if not any(expect in p for p in found):
            problems.append(f"tools/check_addon.py: {label} was not caught (got {found})")


def check(problems):
    problems.extend(f"addon: {p}" for p in run(ROOT))
    self_test(problems)


def main():
    problems = []
    check(problems)
    for p in problems:
        print(p)
    print(f"Addon check: {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
