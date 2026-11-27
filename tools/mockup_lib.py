"""HTML building blocks of tools/make_mockups.py: the design previews of the Azeroth Threatwarden interface.

Pure string helpers: no browser; the only files read are the addon's own. The colours are read from
AzerothThreatwarden/UI/Theme.lua and every interface text from AzerothThreatwarden/Locales/, so a preview never
disagrees with the addon; the pieces (title bar, tabs, cards, switches, segmented, slider, copy box) draw what the
widget kit draws, with the sizes of docs/specs/ui-style.md.

Adapted from Azeroth Accord (tools/mockup_lib.py, itself from Finland Dragon Credit Points), same owner, GPL-3.0
(ADR 0012). Original art only (ADR 0013): CSS shapes and inline SVG; the pictures are the addon's logo and the NEBULA
logos of assets/; the fonts are the ones the addon ships (SIL OFL 1.1); nothing is loaded from the network; no game art.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "AzerothThreatwarden")
ASSETS = "{ASSETS}"   # replaced by the URL of assets/ when a page is rendered
FONTS = "{FONTS}"     # replaced by the URL of AzerothThreatwarden/Media/Fonts/

LANG = ["enUS"]
_cache = {}


def _read(*parts):
    with open(os.path.join(ADDON, *parts), encoding="utf-8") as f:
        return f.read()


_LINE = re.compile(r'^\s*([A-Z][A-Z0-9_]*)\s*=\s*"((?:[^"\\]|\\.)*)"\s*,', re.M)


def strings(lang):
    if lang not in _cache:
        text = _read("Locales", lang + ".lua")
        _cache[lang] = {k: v.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\") for k, v in _LINE.findall(text)}
    return _cache[lang]


def set_lang(lang):
    LANG[0] = lang


def T(key, *args):
    """The interface text of `key` in the current language, formatted like Lua's string.format."""
    text = strings(LANG[0])[key]
    return text % args if args else text


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ---- the themes: the tokens of UI/Theme.lua ---------------------------------------------------------------------------

def themes():
    """{theme id: {token: CSS colour}} read from Theme.themes of UI/Theme.lua."""
    if "themes" in _cache:
        return _cache["themes"]
    source = _read("UI", "Theme.lua")
    out = {}
    for theme in ("nebula", "aurora", "warden"):
        block = re.search(r"^\t%s = \{(.*?)^\t\}," % theme, source, re.M | re.S).group(1)
        tokens = {}
        pattern = r'(?:\["([\w-]+)"\]|\b(\w+))\s*=\s*(?:hex\("(#[0-9A-Fa-f]{6})"\)|rgba\(([\d.,\s]+)\))'
        for quoted, bare, colour, rgba in re.findall(pattern, block):
            tokens[quoted or bare] = colour or "rgba(%s)" % rgba.replace(" ", "")
        out[theme] = tokens
    # the light theme builds its borders from its ink: lightBorders(r, g, b) with the alphas of that function
    ink = re.search(r"lightBorders\((\d+), (\d+), (\d+)\)\n", source.split("Theme.themes = {", 1)[1])
    alphas = re.search(r"function lightBorders\(r, g, b\) return rgba\(r, g, b, ([\d.]+)\), rgba\(r, g, b, ([\d.]+)\), "
                       r"rgba\(r, g, b, ([\d.]+)\)", source).groups()
    for token, alpha in zip(("border-subtle", "border", "border-strong"), alphas):
        out["aurora"][token] = "rgba(%s,%s,%s,%s)" % (*ink.groups(), alpha)
    # the four state colours and their ink, the same in every theme (Theme.STATE)
    state = re.search(r"^Theme\.STATE = \{(.*?)^\}", source, re.M | re.S).group(1)
    for token, colour in re.findall(r'\["([\w-]+)"\]\s*=\s*hex\("(#[0-9A-Fa-f]{6})"\)', state):
        for theme in out:
            out[theme][token] = colour
    _cache["themes"] = out
    return out


# the drawing behind the window (an original gradient, the game world is not imitated)
STAGE = {
    "nebula": "radial-gradient(circle at 30% 20%, #1A1030, #05030A 70%)",
    "aurora": "radial-gradient(circle at 30% 20%, #DCE6EE, #B9C6D1)",
    "warden": "radial-gradient(circle at 30% 20%, #0B3036, #020C0E 70%)",
}


def css(theme):
    faces = "".join(
        f"@font-face {{ font-family: '{family}'; font-weight: {weight}; src: url('{FONTS}/{file}') format('truetype'); }}\n"
        for family, weight, file in [
            ("Outfit", 400, "Outfit-Regular.ttf"), ("Outfit", 500, "Outfit-Medium.ttf"),
            ("Outfit", 600, "Outfit-SemiBold.ttf"), ("JetBrains Mono", 400, "JetBrainsMono-Regular.ttf"),
            ("JetBrains Mono", 500, "JetBrainsMono-Medium.ttf"), ("Orbitron", 700, "Orbitron-Bold.ttf")])
    tokens = "".join(f"--{name}: {value}; " for name, value in themes()[theme].items())
    return faces + ":root { " + tokens + f"--stage: {STAGE[theme]}; }}\n" + RULES


RULES = """
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 1200px; }
body { font: 400 13px/1.35 'Outfit', 'Segoe UI', sans-serif; color: var(--text-1); background: #000; }
.stage { position: relative; width: 1200px; height: 720px; overflow: hidden; background: var(--stage); }
.dp { width: 1200px; height: 34px; display: flex; align-items: center; gap: 14px; padding: 0 16px; background: #000; color: #bbb; font: 12px/1 'Segoe UI', sans-serif; white-space: nowrap; }
.dp b { color: #fff; letter-spacing: .12em; }
.dp .r { margin-left: auto; color: #999; }
.win { position: absolute; border: 1px solid var(--border); overflow: hidden; box-shadow: inset 0 1px 0 var(--highlight), 0 24px 60px -20px rgba(0,0,0,.7); }
.win.wide { width: 560px; height: 520px; border-radius: 12px; background: var(--bg); }
.win.compact { width: 300px; height: 220px; border-radius: 8px; background: var(--surface-1); }
.bar { position: relative; height: 52px; background: var(--surface-1); display: flex; align-items: center; border-radius: 12px 12px 0 0; }
.bar::after { content: ""; position: absolute; left: 12px; right: 12px; bottom: 0; height: 1px; background: var(--border-subtle); }
.bar img { width: 24px; height: 24px; border-radius: 50%; margin: 0 12px 0 20px; box-shadow: 0 0 22px color-mix(in srgb, var(--neon) 55%, transparent); }
.bar .name { font: 700 20px/1 'Orbitron', sans-serif; text-shadow: 0 0 10px color-mix(in srgb, var(--neon) 60%, transparent); white-space: nowrap; }
.win.aurora .bar .name { text-shadow: none; }
.bar .state { display: flex; align-items: center; gap: 4px; margin-top: 4px; font: 400 11px/1 'JetBrains Mono', monospace; color: var(--text-3); }
.bar .icons { margin-left: auto; display: flex; gap: 6px; padding-right: 14px; }
.bar .icons span { width: 28px; height: 28px; display: grid; place-items: center; color: var(--text-2); }
.compact .bar { height: 28px; border-radius: 8px 8px 0 0; }
.compact .bar::after { left: 8px; right: 8px; }
.compact .bar img { width: 18px; height: 18px; margin: 0 6px 0 8px; box-shadow: none; }
.compact .bar .name { font-size: 12px; text-shadow: none; }
.compact .bar .state { margin: 0 0 0 auto; height: 18px; padding: 0 5px; border-radius: 8px; background: color-mix(in srgb, var(--text-3) 16%, transparent); font: 600 10px/1 'Outfit', sans-serif; }
.compact .bar .icons { margin-left: 6px; gap: 4px; padding-right: 6px; }
.compact .bar .icons span { width: 18px; height: 18px; }
.tabs { height: 36px; display: flex; gap: 4px; border-bottom: 1px solid var(--border-subtle); }
.tabs span { display: grid; place-items: center; padding: 0 16px; font: 500 14px/1 'Outfit', sans-serif; color: var(--text-3); position: relative; }
.tabs span.on { color: var(--text-1); }
.tabs span.on::after { content: ""; position: absolute; left: 4px; right: 4px; bottom: -1px; height: 2px; background: var(--accent); }
.compact .tabs { height: 24px; }
.compact .tabs span { padding: 0 8px; font-size: 11px; }
.empty { position: absolute; left: 12px; right: 12px; top: 52px; bottom: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; text-align: center; }
.empty img { width: 32px; height: 32px; border-radius: 50%; opacity: .35; }
.empty p { font: 500 13px/1.35 'Outfit', sans-serif; color: var(--text-2); }
.grip { position: absolute; right: 3px; bottom: 3px; width: 14px; height: 14px; color: var(--text-3); }
.page { position: absolute; left: 20px; right: 20px; top: 98px; bottom: 20px; overflow: hidden; }
.pager { position: absolute; left: 0; top: 0; }
.scroll { position: absolute; left: 0; right: 0; top: 44px; bottom: 0; overflow: hidden; }
.column { display: flex; flex-direction: column; gap: 12px; }
.card { background: var(--surface-1); border: 1px solid var(--border-subtle); border-radius: 18px; padding: 20px; box-shadow: inset 0 1px 0 var(--highlight); display: flex; flex-direction: column; align-items: stretch; }
.card h2 { font: 600 14px/17px 'Outfit', sans-serif; }
.row { display: flex; align-items: center; justify-content: space-between; gap: 12px; height: 32px; margin-top: 8px; }
.row b { font-weight: 500; }
.note { font: 400 11px/14px 'Outfit', sans-serif; color: var(--text-3); margin-top: 2px; }
.body { color: var(--text-2); margin-top: 8px; }
.sw { width: 44px; height: 26px; border-radius: 13px; background: var(--surface-3); border: 1px solid var(--border); position: relative; flex: none; }
.sw::after { content: ""; position: absolute; top: 3px; left: 3px; width: 18px; height: 18px; border-radius: 50%; background: var(--text-2); }
.sw.on { background: var(--accent); border-color: var(--accent); }
.sw.on::after { left: 21px; background: var(--on-accent); }
.seg { display: inline-flex; align-self: flex-start; gap: 2px; height: 32px; padding: 3px; border-radius: 12px; background: var(--surface-2); border: 1px solid var(--border); flex: none; }
.seg span { display: grid; place-items: center; height: 24px; padding: 0 12px; border-radius: 10px; font: 500 13px/1 'Outfit', sans-serif; color: var(--text-3); white-space: nowrap; }
.seg span.on { background: var(--raised); color: var(--text-1); box-shadow: inset 0 1px 0 var(--highlight), 0 1px 2px rgba(0,0,0,.3); }
.slider { display: flex; align-items: center; gap: 8px; }
.track { position: relative; width: 180px; height: 4px; border-radius: 2px; background: var(--border); }
.track i { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 2px; background: linear-gradient(90deg, var(--accent), var(--accent-2)); }
.track u { position: absolute; top: -6px; width: 16px; height: 16px; margin-left: -8px; border-radius: 50%; background: var(--text-1); box-shadow: 0 1px 3px rgba(0,0,0,.5); }
.slider em { width: 48px; text-align: right; font: normal 400 13px/1 'JetBrains Mono', monospace; }
.btn { display: inline-grid; place-items: center; align-self: flex-start; height: 32px; padding: 0 16px; margin-top: 12px; border-radius: 8px; background: var(--surface-3); border: 1px solid var(--border); font: 500 13px/1 'Outfit', sans-serif; }
.btn.primary { border: 0; background: linear-gradient(90deg, var(--accent), var(--accent-2)); color: var(--on-accent); }
.btn.off { opacity: .45; }
.btn.wide { width: 240px; }
.btn.mid { width: 200px; }
.select { display: inline-flex; justify-content: space-between; align-items: center; width: 200px; height: 28px; padding: 0 8px 0 10px; border-radius: 8px; background: var(--surface-2); border: 1px solid var(--border); font: 400 13px/1 'Outfit', sans-serif; flex: none; }
.select svg { color: var(--text-3); }
.head { display: flex; gap: 16px; align-items: flex-start; }
.head img { width: 64px; height: 64px; border-radius: 50%; flex: none; }
.head img.square { border-radius: 0; object-fit: contain; }
.head .texts { padding-top: 4px; display: flex; flex-direction: column; gap: 6px; }
.title { font: 700 12px/15px 'Orbitron', sans-serif; color: var(--accent-text); }
.mono { font: 400 11px/14px 'JetBrains Mono', monospace; color: var(--text-3); }
.url { height: 28px; margin-top: 4px; display: flex; align-items: center; padding: 0 10px; border-radius: 8px; background: var(--surface-2); border: 1px solid var(--border); white-space: nowrap; overflow: hidden; }
.label { font: 400 11px/14px 'Outfit', sans-serif; color: var(--text-2); margin-top: 12px; }
.mon { position: absolute; left: 8px; right: 8px; top: 56px; bottom: 2px; font: 500 11px/14px 'Outfit', sans-serif; }
.mhead { position: relative; height: 34px; }
.mhead.tall { height: 46px; }
.mhead .mob { position: absolute; left: 0; top: 1px; display: flex; gap: 4px; align-items: baseline; font: 500 13px/16px 'Outfit', sans-serif; }
.mhead .mob small { font: 400 11px/14px 'Outfit', sans-serif; color: var(--text-3); }
.mhead .tankline { position: absolute; left: 0; top: 20px; display: flex; gap: 4px; align-items: center; color: var(--text-2); }
.mhead .margin { position: absolute; right: 0; top: 20px; font: 500 11px/14px 'JetBrains Mono', monospace; color: var(--text-2); }
.badge { display: inline-flex; align-items: center; gap: 3px; height: 14px; padding: 0 7px 0 5px; border-radius: 8px; color: var(--on-state); font: 600 9px/1 'Outfit', sans-serif; white-space: nowrap; }
.badge.large { position: absolute; right: 0; top: 0; height: 18px; }
.strip { position: relative; display: flex; align-items: center; gap: 4px; height: 18px; padding: 0 4px 0 8px; background: var(--surface-2); border-radius: 4px; overflow: hidden; }
.strip .stripe { position: absolute; left: 0; top: 0; bottom: 0; width: 3px; }
.strip .coachicon { display: grid; color: var(--accent-text); }
.strip .text { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.strip .pred { display: grid; color: var(--text-2); }
.strip .pill { height: 14px; padding: 0 5px; border-radius: 8px; background: var(--surface-3); color: var(--text-2); font: 600 9px/14px 'Outfit', sans-serif; }
.win.flash { border: 1px solid var(--state-danger); }
.mlisthead { height: 14px; display: flex; justify-content: space-between; align-items: center; font: 600 10px/1 'Outfit', sans-serif; color: var(--text-3); }
.mlisthead span { display: flex; gap: 3px; align-items: center; padding: 0 2px; }
.mrow { position: relative; display: flex; align-items: center; height: 20px; padding-left: 8px; }
.mrow.self { box-shadow: inset 0 0 0 1px var(--accent); border-radius: 4px; }
.mrow .stripe { position: absolute; left: 0; top: 0; bottom: 0; width: 3px; }
.mrow .mark { position: absolute; left: 4px; top: 5px; width: 2px; height: 10px; }
.mrow .cell { width: 12px; flex: none; display: grid; place-items: center start; color: var(--text-3); }
.mrow .name { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mrow .barbox { display: flex; align-items: center; gap: 2px; flex: none; margin-left: 4px; }
.mrow .tr { position: relative; height: 10px; border-radius: 4px; background: var(--surface-3); }
.mrow .tr i { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 4px; }
.mrow .tr u { position: absolute; top: 0; bottom: 0; width: 1px; background: var(--border-strong); }
.mrow .tr.unknown { background: var(--surface-3); border: 1px dashed var(--state-unknown); }
.mrow .pred { width: 10px; display: grid; place-items: center; color: var(--text-2); }
.mrow .num { width: 36px; text-align: right; font: 500 11px/14px 'JetBrains Mono', monospace; }
.mrow .trend { width: 28px; margin-left: 2px; display: grid; place-items: center; white-space: nowrap; letter-spacing: -.04em; font: 500 10px/14px 'JetBrains Mono', monospace; color: var(--text-2); }
.mrow .badgebox { margin-left: 2px; margin-right: 2px; flex: none; display: flex; justify-content: flex-end; }
.mmsg { position: absolute; left: 4px; right: 4px; top: 48px; bottom: 16px; display: flex; flex-direction: column; justify-content: center; align-items: center; gap: 4px; text-align: center; font: 500 13px/1.35 'Outfit', sans-serif; color: var(--text-2); }
.mmsg small { font: 400 11px/14px 'Outfit', sans-serif; color: var(--text-3); }
.mfoot { position: absolute; left: 0; right: 12px; bottom: 0; height: 16px; font: 400 10px/16px 'JetBrains Mono', monospace; color: var(--text-3); white-space: nowrap; overflow: hidden; }
.mfoot.warn { color: var(--warn); }
.pull { display: flex; align-items: center; gap: 4px; height: 20px; padding: 0 4px; background: var(--surface-2); border-radius: 4px; color: var(--text-2); font: 400 11px/14px 'Outfit', sans-serif; white-space: nowrap; }
.pull .word { flex: 1; min-width: 0; margin-left: 2px; overflow: hidden; text-overflow: ellipsis; }
.frow { position: relative; display: flex; align-items: center; gap: 4px; height: 20px; padding-left: 6px; white-space: nowrap; }
.frow.self { box-shadow: inset 0 0 0 1px var(--accent); border-radius: 4px; }
.frow.unknown { border-top: 1px dashed var(--state-unknown); border-bottom: 1px dashed var(--state-unknown); }
.frow .stripe { position: absolute; left: 0; top: 0; bottom: 0; width: 3px; }
.frow .badgebox { display: flex; flex: none; }
.frow .fname { flex: 1.3; min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.frow .fname small { font: 400 10px/14px 'Outfit', sans-serif; color: var(--text-3); }
.frow .fholder, .frow .fclose { flex: .8; min-width: 0; overflow: hidden; text-overflow: ellipsis; color: var(--text-2); }
.frow .fwhy { flex: 2; min-width: 0; overflow: hidden; text-overflow: ellipsis; color: var(--text-3); }
.frow .fpct { width: 36px; flex: none; text-align: right; font: 500 11px/14px 'JetBrains Mono', monospace; }
.frow .fmargin { width: 28px; flex: none; text-align: right; font: 500 11px/14px 'JetBrains Mono', monospace; color: var(--text-3); margin-right: 4px; }
.usage { display: flex; align-items: center; gap: 8px; height: 20px; font: 500 13px/16px 'Outfit', sans-serif; }
.cat { display: inline-block; height: 16px; padding: 0 6px; border-radius: 8px; color: var(--text-2); background: color-mix(in srgb, var(--text-2) 16%, transparent); font: 600 9px/16px 'Outfit', sans-serif; white-space: nowrap; }
.cat.estimated, .cat.warn { color: var(--warn); background: color-mix(in srgb, var(--warn) 16%, transparent); }
.cat.unknown { color: var(--text-3); background: color-mix(in srgb, var(--text-3) 16%, transparent); }
.cat.live { color: var(--accent-text); background: color-mix(in srgb, var(--accent-text) 16%, transparent); }
.rrow { position: relative; height: 44px; margin-bottom: 2px; padding: 5px 8px 0; }
.rrow.on { background: var(--raised); }
.rrow .line { display: flex; justify-content: space-between; align-items: center; gap: 8px; height: 18px; }
.rrow .line b { font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.rrow .line em { font: normal 400 13px/1 'JetBrains Mono', monospace; }
.rrow .line.low { color: var(--text-2); font-size: 11px; margin-top: 2px; }
.rrow .right { display: flex; gap: 4px; align-items: center; }
.metric { margin-top: 10px; }
.metric .head2 { display: flex; justify-content: space-between; align-items: center; height: 16px; font-weight: 500; }
.metric .val { color: var(--text-2); margin-top: 3px; white-space: pre-line; }
.metric .val.off { color: var(--text-3); }
.buttons { display: flex; gap: 8px; }
.empty2 { text-align: center; margin-top: 70px; }
.empty2 h2 { font: 600 14px/17px 'Outfit', sans-serif; }
.empty2 p { color: var(--text-2); margin-top: 8px; }
.win.replay { width: 820px; height: 520px; border-radius: 12px; background: var(--bg); }
.win.replay .bar .state { margin-top: 3px; }
.rbody { position: absolute; left: 12px; right: 12px; top: 60px; bottom: 12px; display: flex; flex-direction: column; gap: 8px; }
.tl { display: block; flex: none; }
.tl text { font: 400 11px 'JetBrains Mono', monospace; fill: var(--text-3); }
.tl text.lg { font: 400 11px 'Outfit', sans-serif; fill: var(--text-1); }
.tl text.gap { font: 400 11px 'Outfit', sans-serif; fill: var(--text-2); }
.onote { font: 400 11px/15px 'Outfit', sans-serif; color: var(--text-2); text-align: center; }
.controls { display: flex; align-items: center; gap: 4px; height: 28px; flex: none; }
.controls .ctl { width: 28px; height: 28px; display: flex; align-items: center; justify-content: center; border-radius: 8px; background: var(--surface-3); border: 1px solid var(--border); flex: none; }
.controls .ctl > span + span { margin-left: -2px; }
.controls .seg { margin-left: 8px; align-self: center; }
.controls .seg span { padding: 0 10px; min-width: 40px; }
.controls .time { margin-left: 8px; color: var(--text-1); white-space: nowrap; }
.zoombtns { margin-left: auto; display: flex; gap: 6px; }
.zoombtns .btn { margin-top: 0; height: 28px; padding: 0 9px; white-space: nowrap; font-size: 11px; }
.panels { flex: 1; min-height: 0; display: flex; gap: 8px; }
.panel { flex: 1; min-width: 0; background: var(--surface-1); border: 1px solid var(--border-subtle); border-radius: 8px; padding: 4px; overflow: hidden; }
.panel.detail { padding: 8px 10px; }
.ph { display: flex; justify-content: space-between; align-items: center; height: 32px; padding: 0 4px; }
.ph h2 { font: 600 14px/17px 'Outfit', sans-serif; padding-left: 4px; }
.ph .seg { height: 28px; align-self: center; margin-left: auto; }
.ph .seg span { height: 20px; font-size: 11px; padding: 0 9px; }
.erow { display: flex; align-items: center; gap: 6px; height: 20px; padding: 0 4px 0 6px; font-size: 11px; }
.erow em { width: 40px; font: normal 400 11px/1 'JetBrains Mono', monospace; color: var(--text-3); flex: none; }
.erow > span:not(.cat):not([style]) { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.erow.focus { background: var(--raised); box-shadow: inset 2px 0 0 var(--accent); }
.dline { font-size: 11px; line-height: 14px; color: var(--text-2); margin-top: 3px; }
.dline.head { font-weight: 500; font-size: 13px; line-height: 16px; color: var(--text-1); margin-top: 6px; }
.dline.head:first-child { margin-top: 0; }
.dline.off { color: var(--text-3); }
.unit { margin-top: 5px; }
.unit .top { display: flex; align-items: center; gap: 6px; height: 15px; }
.unit .top i { width: 12px; height: 2px; flex: none; }
.unit .top b { flex: 1; font-weight: 500; font-size: 12px; }
.unit .reading { margin-left: 18px; font: 400 11px/14px 'JetBrains Mono', monospace; color: var(--text-1); }
.unit .reading.warn { color: var(--warn); }
.tip { position: absolute; width: 440px; padding: 14px 18px; border-radius: 14px; background: var(--text-1); color: var(--bg); font: 400 18px/1.55 'Outfit', sans-serif; box-shadow: 0 20px 40px -16px rgba(0,0,0,.6); }
.tip b { display: block; font-weight: 500; font-size: 20px; }
"""


# ---- icons (original SVG, the shapes of the addon's icon sheet) -------------------------------------------------------

def _svg(paths, size):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">{paths}</svg>')


def icon_cross(size=16):
    return _svg('<path d="M18 6 6 18M6 6l12 12"/>', size)


def icon_unlock(size=16):
    return _svg('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.5-2"/>', size)


def icon_minus(size=10):
    return _svg('<path d="M5 12h14"/>', size)


GRIP = ('<svg class="grip" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" '
        'stroke-linecap="round" stroke-dasharray="2.5 3"><path d="M13 2 2 13M13 8 8 13"/></svg>')


# ---- pieces -----------------------------------------------------------------------------------------------------------

def logo(cls=""):
    return f'<img class="{cls}" src="{ASSETS}/logo-source.webp" alt="">'


def seg(options, on, extra=""):
    items = "".join(f'<span class="{"on" if i == on else ""}">{esc(o)}</span>' for i, o in enumerate(options))
    return f'<span class="seg" style="{extra}">{items}</span>'


def switch(on=True):
    return f'<span class="sw{" on" if on else ""}"></span>'


def row(label, control):
    return f'<div class="row"><b>{esc(label)}</b>{control}</div>'


def note(text, style=""):
    return f'<div class="note" style="{style}">{esc(text)}</div>'


def button(text, kind="", style=""):
    return f'<span class="btn {kind}" style="{style}">{esc(text)}</span>'


def slider(fraction, value):
    return (f'<span class="slider"><span class="track"><i style="width:{fraction * 100:.0f}%"></i>'
            f'<u style="left:{fraction * 100:.0f}%"></u></span><em>{esc(value)}</em></span>')


def select(value):
    return f'<span class="select">{esc(value)}{_svg(CHEVRON, 14)}</span>'


CHEVRON = '<path d="M6 9l6 6 6-6"/>'


def card(title, inner):
    heading = f"<h2>{esc(title)}</h2>" if title else ""
    return f'<div class="card">{heading}{inner}</div>'


# the pill of the module state (UI/Window.lua, Window.STATES): the icon, the word's key and the colour token
MODULE = {"off": ("MODULE_OFF", "text-3"), "idle": ("MODULE_IDLE", "text-3"), "live": ("MODULE_LIVE", "ok"),
          "state": ("MODULE_STATE", "warn"), "unavailable": ("MODULE_UNAVAILABLE", "err"),
          "demo": ("MODULE_DEMO", "warn")}
MODULE_ICONS = {
    "off": '<path d="M5 12h14"/>', "idle": '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    "live": '<path d="M4 12l5 5L20 6"/>', "state": '<path d="M12 3 22 20H2z"/><path d="M12 10v4M12 17v.01"/>',
    "unavailable": '<path d="M18 6 6 18M6 6l12 12"/>',
    "demo": '<path d="M2 12h.01M8 12h.01"/><path d="M14 6l8 6-8 6z" fill="currentColor" stroke="none"/>',
}


def window(theme, tab, body, x, y, scale=1.0, module="off", title_hidden=False, reports=False):
    """The window: wide (Settings, Info) or compact (Monitor); `x`, `y` its top-left corner on the stage."""
    compact = tab == "monitor"
    layout = "compact" if compact else "wide"
    key, token = MODULE[module]
    tone = (f' style="color:var(--{token});background:color-mix(in srgb,var(--{token}) 16%,transparent)"'
            if compact and module != "off" else (f' style="color:var(--{token})"' if module != "off" else ""))
    state = f'<span class="state"{tone}>{_svg(MODULE_ICONS[module], 10)}{esc(T(key))}</span>'
    icons = (f'<span class="icons"><span>{icon_unlock(12 if compact else 16)}</span>'
             f'<span>{icon_cross(12 if compact else 16)}</span></span>')
    if compact:
        name = "" if title_hidden else f'<span class="name">{esc(T("WINDOW_TITLE_COMPACT"))}</span>'
        title = f'{name}{state}'
    else:
        title = f'<span><span class="name">{esc(T("WINDOW_TITLE"))}</span>{state}</span>'
    tabs = "".join(f'<span class="{"on" if t == tab else ""}">{esc(T("TAB_" + t.upper()))}</span>'
                   for t in (("monitor", "reports", "settings") if reports else ("monitor", "settings")))
    return (f'<div class="win {layout} {theme}" style="left:{x}px;top:{y}px;transform:scale({scale});transform-origin:0 0">'
            f'<div class="bar">{logo()}{title}{icons}</div><div class="tabs">{tabs}</div>{body}{GRIP}</div>')
