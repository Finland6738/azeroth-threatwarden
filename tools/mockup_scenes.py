"""The scenes of the design previews (tools/make_mockups.py): the window of M1 (the empty Monitor tab), the Settings
page and the Info page, each in English and Italian and in the three themes. The layout follows UI/Window.lua,
UI/Settings.lua and UI/About.lua; every text comes from the addon's locale files.

Adapted from Azeroth Accord (tools/mockup_scenes.py), same owner, GPL-3.0 (ADR 0012). Nothing here is invented data
about players: the only made-up values are the state of the controls (the defaults of Core/Config.lua).
"""
import mockup_lib as lib
from mockup_lib import T, button, card, esc, note, row, seg, switch, window

THEMES = ["nebula", "aurora", "warden"]
THEME_NAMES = {"nebula": "Nebula", "aurora": "Aurora", "warden": "Warden"}
# where the two wide windows of a scene stand, and how far the second one is scrolled
LEFT, RIGHT, TOP = 24, 616, 100


def monitor(theme):
    body = (f'<div class="empty">{lib.logo()}<p>{esc(T("MONITOR_COMING"))}</p></div>')
    return window(theme, "monitor", body, 300, 140, 2.0)


def pager(on):
    return f'<div class="pager">{seg([T("PAGE_SETTINGS"), T("PAGE_ABOUT")], on)}</div>'


def page(theme, selected, cards, x, scroll=0):
    body = (f'<div class="page">{pager(selected)}<div class="scroll"><div class="column" style="margin-top:-{scroll}px">'
            f'{"".join(cards)}</div></div></div>')
    return window(theme, "settings", body, x, TOP)


def settings_cards(theme):
    appearance = card(T("SET_APPEARANCE"),
                      row(T("SET_THEME"), seg([T("THEME_NEBULA"), T("THEME_AURORA"), T("THEME_WARDEN")],
                                              THEMES.index(theme)))
                      + row(T("SET_EFFECTS"), switch(True)) + note(T("SET_EFFECTS_NOTE"))
                      + row(T("SET_ANIMATIONS"), switch(True))
                      + row(T("SET_FONT"), seg([T("SET_FONT_ADDON"), T("SET_FONT_GAME")], 0))
                      + note(T("SET_FONT_NOTE")))
    language = card(T("SET_LANGUAGE"),
                    seg([T("LANGUAGE_AUTO"), T("LANGUAGE_ENUS"), T("LANGUAGE_ITIT")], 0, "margin-top:12px")
                    + note(T("SET_LANGUAGE_NOTE"), "margin-top:8px") + button(T("SET_RELOAD"), "primary off"))
    window_card = card(T("SET_WINDOW"),
                       row(T("SET_LOCK"), switch(False))
                       + row(T("SET_SCALE"), lib.slider((100 - 50) / 150, T("SET_PERCENT", 100)))
                       + row(T("SET_MINIMAP"), switch(True)) + button(T("SET_RESET_WINDOW")))
    reset = card(T("SET_RESET"), f'<div class="body">{esc(T("SET_RESET_TEXT"))}</div>'
                 + button(T("SET_RESET_BUTTON"), "wide"))
    return [appearance, language, window_card, reset]


def about_cards(theme):
    def picture(src, cls, title, title_class, line, line_class):
        return (f'<div class="head"><img class="{cls}" src="{lib.ASSETS}/{src}" alt=""><div class="texts">'
                f'<div class="{title_class}">{esc(title)}</div><div class="{line_class}">{esc(line)}</div></div></div>')

    addon = card(None, picture("logo-source.webp", "", T("ADDON_TITLE"), "title", T("TOOLTIP_VERSION", "0.1.0"), "mono")
                 + f'<div class="body" style="margin-top:12px">{esc(T("ABOUT_PURPOSE"))}</div>'
                 + f'<div class="body" style="margin-top:6px">{esc(T("ABOUT_PURPOSE2"))}</div>')
    nebula = "nebula-logo-light.png" if theme == "aurora" else "nebula-logo-dark.png"
    credits = card(T("ABOUT_CREDITS"), '<div style="margin-top:12px">'
                   + picture(nebula, "square", T("ABOUT_CREDITS_LINE", "Finland", "NEBULA"), "",
                             T("ABOUT_PERMISSION", "NEBULA"), "note") + "</div>")
    links = card(T("ABOUT_LINKS"), note(T("ABOUT_LINKS_HINT"), "margin-top:4px")
                 + f'<div class="label">{esc(T("ABOUT_LINK_REPO"))}</div>'
                 + '<div class="url">https://github.com/Finland6738/azeroth-threatwarden</div>'
                 + f'<div class="label">{esc(T("ABOUT_LINK_KOFI"))}</div>'
                 + '<div class="url">https://ko-fi.com/finland6738</div>')
    legal = card(T("ABOUT_LEGAL"), f'<div class="body">{esc(T("ABOUT_LICENSE", "GPL-3.0"))}</div>'
                 + f'<div class="body" style="margin-top:6px">{esc(T("ABOUT_THIRD"))}</div>'
                 + note(T("ABOUT_DISCLAIMER"), "margin-top:12px"))
    return [addon, credits, links, legal]


# The window at its default size shows the top of a page: the second one of a scene is the same page scrolled down.
def settings(theme):
    cards = settings_cards(theme)
    return page(theme, 0, cards, LEFT) + page(theme, 0, cards, RIGHT, 466)


def about(theme):
    cards = about_cards(theme)
    return page(theme, 1, cards, LEFT) + page(theme, 1, cards, RIGHT, 316)


KINDS = [
    ("window", monitor, "The window of v0.1.0: the Monitor tab before threat monitoring arrives",
     "La finestra della v0.1.0: la scheda Monitor prima che arrivi il monitor della threat"),
    ("settings", settings, "Settings: the top of the page and the page scrolled down",
     "Impostazioni: la parte alta della pagina e la pagina scorsa in basso"),
    ("about", about, "Info and credits: the top of the page and the page scrolled down",
     "Info e crediti: la parte alta della pagina e la pagina scorsa in basso"),
]

# (name, caption, function building the stage, language, theme)
SCENES = []
for _lang in ("enUS", "itIT"):
    for _kind, _fn, _en, _it in KINDS:
        for _theme in THEMES:
            _name = f"{_kind}-{_theme}" + ("-it" if _lang == "itIT" else "")
            _caption = f"{_en if _lang == 'enUS' else _it} ({THEME_NAMES[_theme]})"
            SCENES.append((_name, _caption, (lambda f=_fn, t=_theme: f(t)), _lang, _theme))
