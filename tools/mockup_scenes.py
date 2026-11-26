"""The scenes of the design previews (tools/make_mockups.py): the window of M1 (the empty Monitor tab), the Settings
page and the Info page, each in English and Italian and in the three themes. The layout follows UI/Window.lua,
UI/Settings.lua and UI/About.lua; every text comes from the addon's locale files.

Adapted from Azeroth Accord (tools/mockup_scenes.py), same owner, GPL-3.0 (ADR 0012). The made-up values are the state
of the controls (the defaults of Core/Config.lua) and, in the monitor scenes, an invented fight: no player, mob or
number comes from a real game.
"""
import mockup_lib as lib
from mockup_lib import T, button, card, esc, note, row, seg, select, switch, window

THEMES = ["nebula", "aurora", "warden"]
THEME_NAMES = {"nebula": "Nebula", "aurora": "Aurora", "warden": "Warden"}
# where the two wide windows of a scene stand, and how far the second one is scrolled
LEFT, RIGHT, TOP = 24, 616, 100


def monitor(theme):
    body = (f'<div class="empty">{lib.logo()}<p>{esc(T("MONITOR_COMING"))}</p></div>')
    return window(theme, "monitor", body, 300, 140, 2.0)


# ---- the threat monitor (UI/ThreatList.lua). Invented data: the mob and the players do not exist. ----------------------

ICONS = {
    "state-safe": '<path d="M12 2 21 6v7c0 5-4 8-9 9-5-1-9-4-9-9V6z" fill="currentColor" stroke="none"/><path d="M8 12l3 3 5-6" stroke="var(--state-safe)"/>',
    "state-warning": '<path d="M12 2 23 21H1z" fill="currentColor" stroke="none"/><path d="M12 9v5M12 17.5v.01" stroke="var(--state-warning)"/>',
    "state-danger": '<path d="M7.5 2h9L22 7.5v9L16.5 22h-9L2 16.5v-9z" fill="currentColor" stroke="none"/><path d="M9 7v7M15 7v7M9 17.5v.01M15 17.5v.01" stroke="var(--state-danger)"/>',
    "state-unknown": '<circle cx="12" cy="12" r="10"/><path d="M9 9a3 3 0 1 1 4 3c-1 .5-1 1-1 2M12 17.5v.01"/>',
    "tank": '<path d="M12 2 21 5v8c0 4-4 7-9 9-5-2-9-5-9-9V5z"/><path d="M12 6l5 2v5c0 2-2 4-5 5z" fill="currentColor" stroke="none"/>',
    "role-tank": '<path d="M12 2 21 5v8c0 4-4 7-9 9-5-2-9-5-9-9V5z" fill="currentColor" stroke="none"/>',
    "role-healer": '<path d="M9 3h6v6h6v6h-6v6H9v-6H3V9h6z" fill="currentColor" stroke="none"/>',
    "role-dps": '<path d="M6 18 20 4M4 12l8 8M4 20l3-3" stroke-width="3"/>',
    "trend-up": '<path d="M3 19l7-7 4 3 6-8M14 6h6v6"/>',
    "trend-flat": '<path d="M3 12h17M15 7l5 5-5 5"/>',
    "predict": '<path d="M2 12h.01M8 12h.01"/><path d="M14 6l8 6-8 6z" fill="currentColor" stroke="none"/>',
    "check": '<path d="M4 12l5 5L20 6"/>', "minus": '<path d="M5 12h14"/>',
    "mute": '<path d="M6 9a6 6 0 0 1 12 0c0 6 2 7 2 8H4c0-1 2-2 2-8zM10 21h4"/><path d="M3 3l18 18"/>',
    "coach": '<path d="M4 4h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-9l-6 5v-5H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z"/><circle cx="12" cy="10.5" r="2" fill="currentColor"/>',
}
CLASS = {"warrior": "#C69B6D", "mage": "#3FC7EB", "priest": "#FFFFFF", "rogue": "#FFF468"}
STATE_KEY = {"safe": "STATE_SAFE", "warning": "STATE_WARNING", "danger": "STATE_DANGER", "unknown": "STATE_UNKNOWN"}


def icon(name, size=10):
    return lib._svg(ICONS[name], size)


def badge(state, large=False):
    return (f'<span class="badge{" large" if large else ""}" style="background:var(--state-{state})">'
            f'{icon("state-" + state)}{esc(T(STATE_KEY[state]))}</span>')


def mon_head(title, kind=None, state=None, tank=None, margin=None, holder=True):
    mob = f'<div class="mob">{esc(title)}' + (f'<small>{esc(kind)}</small>' if kind else "") + "</div>"
    out = mob + (badge(state, True) if state else "")
    if tank:
        mark = f'<span style="color:var(--text-2);display:grid">{icon("tank")}</span>' if holder else ""
        out += f'<div class="tankline">{mark}{esc(tank)}</div>'
    if margin:
        out += f'<div class="margin">{esc(T("MON_MARGIN", margin))}</div>'
    return f'<div class="mhead">{out}</div>'


def mon_row(theme, name, cls, role, state, percent=None, holder=False, me=False, trend=None, eta=None,
            state_only=False):
    # on the light theme the name is text-1 and the class colour is the mark before the role icon
    light = theme == "aurora"
    ink = "var(--text-1)" if light else CLASS[cls]
    mark = f'<span class="mark" style="background:{CLASS[cls]}"></span>' if light else ""
    track = 26 if lib.LANG[0] == "itIT" else 38
    if state_only:
        bar = f'<span class="barbox" style="width:{track + 48}px;justify-content:flex-end"><span class="num" style="color:var(--text-2)">{esc(T("MON_DASH"))}</span></span>'
    else:
        ticks = '<u style="left:80%"></u><u style="left:95%"></u>'
        fill = f'<i style="width:{min(percent, 100)}%;background:var(--state-{state})"></i>'
        pred = icon("predict") if eta else ""
        bar = (f'<span class="barbox"><span class="tr" style="width:{track}px">{fill}{ticks}</span>'
               f'<span class="pred">{pred}</span><span class="num">{percent} %</span></span>')
    cell = esc(T("MON_TIME", eta)) if eta else (icon("trend-" + trend) if trend else "")
    width = 82 if lib.LANG[0] == "itIT" else 66
    return (f'<div class="mrow{" self" if me else ""}"><span class="stripe" style="background:var(--state-{state})"></span>'
            f'{mark}<span class="cell">{icon("role-" + role)}</span>'
            f'<span class="cell" style="color:var(--text-2)">{icon("tank") if holder else ""}</span>'
            f'<span class="name" style="color:{ink}">{esc(name)}</span>{bar}<span class="trend">{cell}</span>'
            f'<span class="badgebox" style="width:{width}px">{badge(state)}</span></div>')


def mon_list(rows):
    head = (f'<div class="mlisthead"><span>{esc(T("MON_SORT", T("SORT_RELATIVE")))}</span>'
            f'<span>{icon("minus")}{esc(T("MON_PIN_OFF"))}</span></div>')
    return head + "".join(rows)


def tip(lines, top):
    return (f'<div class="tip" style="left:700px;top:{top}px"><b>{esc(lines[0])}</b>'
            + "".join(f"<div>{esc(line)}</div>" for line in lines[1:]) + "</div>")


def mon_window(theme, module, body, footer="", warn=False):
    foot = f'<div class="mfoot{" warn" if warn else ""}">{esc(footer)}</div>'
    # the compact bar gives up its title before the state loses its word (UI/Window.lua)
    hidden = len(T(lib.MODULE[module][0])) > 12
    return lib.window(theme, "monitor", f'<div class="mon">{body}{foot}</div>', 60, 110, 2.0, module, hidden)


def quality(valid):
    return T("MON_QUALITY", 0.2, valid)


def category(value, key):
    return T("TIP_TAGGED", value, T(key))


# ---- the Coach strip (UI/CoachStrip.lua, SPEC-04 §3.1) --------------------------------------------------------------

def strip(text, alert=None, pill=None, predicted=False):
    token = f"var(--state-{alert})" if alert else "var(--accent)"
    lead = badge(alert) if alert else f'<span class="coachicon">{icon("coach", 12)}</span>'
    extra = f'<span class="pred">{icon("predict")}</span>' if predicted else ""
    extra += f'<span class="pill">{esc(T(pill))}</span>' if pill else ""
    return (f'<div class="strip"><span class="stripe" style="background:{token}"></span>{lead}'
            f'<span class="text">{esc(text)}</span>{extra}</div>')


def coach_dps(theme):
    rows = [mon_row(theme, "Bram", "warrior", "tank", "danger", 100, holder=True),
            mon_row(theme, T("UNIT_YOU"), "mage", "dps", "warning", 84, me=True, eta=4),
            mon_row(theme, "Kor", "rogue", "dps", "safe", 49, trend="up"),
            mon_row(theme, "Sela", "priest", "healer", "safe", 12, trend="flat")]
    body = (mon_head("Gorrak", T("MON_CLASS_BOSS"), "warning", T("MON_TANK", "Bram"), "+16")
            + strip(T("COACH_RISING"), pill="CONF_PILL_MEDIUM", predicted=True) + mon_list(rows))
    lines = [T("COACH_RISING"), T("STRIP_WHY", T("COACH_WHY_TREND", 95, 4, T("CONF_MEDIUM"))),
             T("STRIP_BASIS", T("CAT_PREDICTED"), T("CONF_MEDIUM")), T("STRIP_ADVICE"), T("STRIP_SINCE", 1)]
    return mon_window(theme, "live", body, quality(100)) + tip(lines, 190)


def coach_tank(theme):
    rows = [mon_row(theme, T("UNIT_YOU"), "warrior", "tank", "safe", 100, holder=True, me=True),
            mon_row(theme, "Kor", "rogue", "dps", "safe", 71, eta=6),
            mon_row(theme, "Sela", "priest", "healer", "safe", 15, trend="flat")]
    body = (mon_head("Gorrak", T("MON_CLASS_BOSS"), "safe", T("MON_TANK", T("UNIT_YOU")), "+29")
            + strip(T("COACH_TANK_OVERTAKE", "Kor", 6), pill="CONF_PILL_HIGH", predicted=True) + mon_list(rows))
    lines = [T("COACH_TANK_OVERTAKE", "Kor", 6), T("STRIP_WHY", T("COACH_WHY_TREND_OTHER", 4.8, T("CONF_HIGH"))),
             T("STRIP_BASIS", T("CAT_PREDICTED"), T("CONF_HIGH")), T("STRIP_ADVICE"), T("STRIP_SINCE", 2)]
    return mon_window(theme, "live", body, quality(100)) + tip(lines, 190)


def coach_unknown(theme):
    body = (mon_head("Gorrak", T("MON_CLASS_BOSS"), "unknown", T("MON_TANK_UNKNOWN"), holder=False)
            + strip(T("COACH_INSUFFICIENT"))
            + f'<div class="mmsg">{esc(T("MON_UNAVAILABLE"))}<small>{esc(T("WHY_SECRET"))}</small></div>')
    lines = [T("COACH_INSUFFICIENT"), T("STRIP_WHY", T("WHY_SECRET")), T("STRIP_ADVICE"), T("STRIP_SINCE", 3)]
    return mon_window(theme, "unavailable", body, quality(0), True) + tip(lines, 190)


def alert_danger(theme):
    rows = [mon_row(theme, "Bram", "warrior", "tank", "danger", 100, holder=True),
            mon_row(theme, T("UNIT_YOU"), "mage", "dps", "danger", 97, me=True, trend="up"),
            mon_row(theme, "Kor", "rogue", "dps", "safe", 49, trend="up"),
            mon_row(theme, "Sela", "priest", "healer", "safe", 12, trend="flat")]
    body = (mon_head("Gorrak", T("MON_CLASS_BOSS"), "danger", T("MON_TANK", "Bram"), "+3")
            + strip(T("ALERT_DANGER", 97), alert="danger") + mon_list(rows))
    lines = [T("ALERT_DANGER", 97), T("STRIP_WHY", T("ALERT_WHY_P_DANGER", 95)),
             T("STRIP_BASIS", T("CAT_DETECTED"), T("CONF_HIGH")), T("STRIP_ALERT"), T("STRIP_SINCE", 0)]
    window_html = mon_window(theme, "live", body, quality(100)).replace('<div class="win compact',
                                                                       '<div class="win flash compact', 1)
    return window_html + tip(lines, 190)


def alert_muted(theme):
    rows = [mon_row(theme, "Bram", "warrior", "tank", "danger", 100, holder=True),
            mon_row(theme, T("UNIT_YOU"), "mage", "dps", "warning", 84, me=True, trend="up"),
            mon_row(theme, "Kor", "rogue", "dps", "safe", 49, trend="up"),
            mon_row(theme, "Sela", "priest", "healer", "safe", 12, trend="flat")]
    note_strip = (f'<div class="strip"><span class="text" style="color:var(--text-2)">{esc(T("STRIP_MUTED"))}</span>'
                  f'<span class="pred">{icon("mute")}</span></div>')
    body = (mon_head("Gorrak", T("MON_CLASS_BOSS"), "warning", T("MON_TANK", "Bram"), "+16")
            + note_strip + mon_list(rows))
    return mon_window(theme, "live", body, quality(100)) + tip([T("STRIP_TIP_MUTED")], 190)


def monitor_values(theme):
    rows = [mon_row(theme, "Bram", "warrior", "tank", "danger", 100, holder=True),
            mon_row(theme, "Kor", "rogue", "dps", "danger", 97, trend="up"),
            mon_row(theme, T("UNIT_YOU"), "mage", "dps", "warning", 84, me=True, eta=2),
            mon_row(theme, "Sela", "priest", "healer", "safe", 12, trend="flat")]
    body = (mon_head("Gorrak", T("MON_CLASS_BOSS"), "warning", T("MON_TANK", "Bram"), "+16")
            + mon_list(rows))
    lines = [T("UNIT_YOU"), T("TIP_STATE", T("STATE_WARNING"), T("CAT_CALCULATED")),
             T("TIP_SCALED", category("84 %", "CAT_DETECTED")), T("TIP_MARGIN", category("+16", "CAT_CALCULATED")),
             T("TIP_TREND", category(T("TIP_TREND_VALUE", 6.2, T("CONF_MEDIUM"), 9), "CAT_ESTIMATED")),
             T("TIP_PREDICTION", category(T("TIP_PREDICTED_AGGRO", 2), "CAT_PREDICTED")),
             T("TIP_READ", 0.2), T("TIP_MODE", T("MODULE_LIVE"))]
    return mon_window(theme, "live", body, quality(100)) + tip(lines, 170)


def monitor_tank(theme):
    rows = [mon_row(theme, T("UNIT_YOU"), "warrior", "tank", "safe", 100, holder=True, me=True),
            mon_row(theme, "Kor", "rogue", "dps", "safe", 70, trend="up"),
            mon_row(theme, "Sela", "priest", "healer", "safe", 15, trend="flat")]
    body = mon_head("Gorrak", T("MON_CLASS_BOSS"), "safe", T("MON_TANK", T("UNIT_YOU")), "+30") + mon_list(rows)
    return mon_window(theme, "live", body, quality(100))


def monitor_state(theme):
    rows = [mon_row(theme, "Bram", "warrior", "tank", "safe", holder=True, state_only=True),
            mon_row(theme, "Kor", "rogue", "dps", "warning", state_only=True),
            mon_row(theme, T("UNIT_YOU"), "mage", "dps", "safe", me=True, state_only=True),
            mon_row(theme, "Sela", "priest", "healer", "safe", state_only=True)]
    body = (mon_head("Gorrak", T("MON_CLASS_BOSS"), "safe", T("MON_TANK", "Bram"), T("MON_DASH"))
            + mon_list(rows))
    lines = ["Kor", T("TIP_STATE", T("STATE_WARNING"), T("CAT_DETECTED")), T("TIP_STATE_ONLY"),
             T("TIP_GAME_STATE"), T("TIP_SCALED", T("WHY_STATE_ONLY")), T("TIP_MODE", T("MODULE_STATE"))]
    return mon_window(theme, "state", body, T("MON_QUALITY_STATE", 0.2, 100)) + tip(lines, 220)


def monitor_unknown(theme):
    body = (mon_head("Gorrak", T("MON_CLASS_BOSS"), "unknown", T("MON_TANK_UNKNOWN"), holder=False)
            + f'<div class="mmsg">{esc(T("MON_UNAVAILABLE"))}<small>{esc(T("WHY_SECRET"))}</small></div>')
    lines = ["Gorrak", T("TIP_STATE_UNKNOWN", T("STATE_UNKNOWN")), T("WHY_SECRET"), T("MON_TANK_UNKNOWN"),
             T("WHY_TANK_UNKNOWN")]
    return mon_window(theme, "unavailable", body, quality(0), True) + tip(lines, 190)


def monitor_no_target(theme):
    body = (mon_head(T("MON_NO_TARGET"))
            + f'<div class="mmsg">{esc(T("MON_NO_TARGET_HINT"))}</div>')
    return mon_window(theme, "idle", body)


def monitor_demo(theme):
    rows = [mon_row(theme, "Brannok", "warrior", "tank", "safe", 100, holder=True),
            mon_row(theme, T("UNIT_YOU"), "mage", "dps", "warning", 78, me=True, eta=4),
            mon_row(theme, "Kor", "rogue", "dps", "safe", 49, trend="up"),
            mon_row(theme, "Sela", "priest", "healer", "safe", 12, trend="flat")]
    body = (mon_head(T("DEMO_MOB"), T("MON_CLASS_ELITE"), "warning", T("MON_TANK", "Brannok"), "+22")
            + mon_list(rows))
    lines = ["Brannok", T("MON_DEMO_TIP"), T("TIP_STATE", T("STATE_SAFE"), T("CAT_CALCULATED")), T("TIP_HOLDS")]
    return mon_window(theme, "demo", body, T("MON_DEMO"), True) + tip(lines, 170)


def pager(on):
    return f'<div class="pager">{seg([T("PAGE_SETTINGS"), T("PAGE_ABOUT")], on)}</div>'


def page(theme, selected, cards, x, scroll=0, module="off"):
    body = (f'<div class="page">{pager(selected)}<div class="scroll"><div class="column" style="margin-top:-{scroll}px">'
            f'{"".join(cards)}</div></div></div>')
    return window(theme, "settings", body, x, TOP, module=module)


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


# The Monitor card of Settings (M2.6, with the `monitor` switch on) and the Reset card below it.
def monitor_card():
    def slide(label, low, high, value, text, first=False):
        return row(T(label), lib.slider((value - low) / (high - low), text))

    inner = (slide("SET_WARNING", 50, 95, 80, T("SET_PERCENT", 80))
             + slide("SET_DANGER", 60, 100, 95, T("SET_PERCENT", 95)) + note(T("SET_THRESHOLDS_NOTE", 5))
             + slide("SET_RATE", 2, 10, 5, T("SET_HERTZ", 5)) + note(T("SET_RATE_NOTE"))
             + slide("SET_MAX_UNITS", 5, 40, 40, "40") + note(T("SET_MAX_UNITS_NOTE"))
             + f'<div class="row"><b>{esc(T("SET_SHOW"))}</b></div>'
             + seg([T("SHOW_AUTO"), T("SHOW_ALWAYS"), T("SHOW_MANUAL")], 0, "margin-top:4px")
             + note(T("SET_SHOW_NOTE", 10), "margin-top:8px")
             + row(T("SET_SORT"), select(T("SORT_RELATIVE"))) + row(T("SET_PIN_SELF"), switch(False))
             + row(T("SET_FOLLOW"), switch(True)) + note(T("SET_FOLLOW_NOTE"))
             + note(T("SET_DEMO_NOTE"), "margin-top:12px;color:var(--text-2)")
             + button(T("SET_DEMO_START"), "mid", "margin-top:8px"))
    return card(T("SET_MONITOR"), inner)


def settings_monitor(theme):
    reset = card(T("SET_RESET"), f'<div class="body">{esc(T("SET_RESET_TEXT_MONITOR"))}</div>'
                 + button(T("SET_RESET_BUTTON"), "wide"))
    cards = [monitor_card(), reset]
    return page(theme, 0, cards, LEFT, module="idle") + page(theme, 0, cards, RIGHT, 330, "idle")


# The Alerts card of Settings (M3.5, with the `alerts` and `coach` switches on), with the note of the game's own threat
# warning, and the Reset card below it.
def alerts_card():
    inner = (row(T("SET_ALERTS_ENABLED"), switch(True)) + row(T("SET_ALERTS_WINDOW"), switch(True))
             + row(T("SET_ALERTS_VISUAL"), switch(True)) + row(T("SET_ALERTS_SOUND"), switch(False))
             + note(T("SET_ALERTS_SOUND_NOTE"))
             + row(T("SET_ALERTS_COOLDOWN"), lib.slider((8 - 3) / 27, T("SET_SECONDS", 8)))
             + note(T("SET_ALERTS_COOLDOWN_NOTE"))
             + f'<div class="row"><b>{esc(T("SET_ALERTS_OTHERS"))}</b></div>'
             + seg([T("SET_OTHERS_TANK"), T("SET_OTHERS_ALWAYS"), T("SET_OTHERS_NEVER")], 0, "margin-top:4px")
             + row(T("SET_ALERTS_PET"), switch(True))
             + note(T("SET_ALERTS_THRESHOLDS", 80, 95), "margin-top:12px;color:var(--text-2)")
             + button(T("SET_ALERTS_TO_MONITOR"), "wide", "margin-top:8px")
             + note(T("SET_ALERTS_NATIVE"), "margin-top:12px;color:var(--warn)")
             + row(T("SET_COACH"), switch(True)))
    return card(T("SET_ALERTS"), inner)


def settings_alerts(theme):
    reset = card(T("SET_RESET"), f'<div class="body">{esc(T("SET_RESET_TEXT_ALERTS"))}</div>'
                 + button(T("SET_RESET_BUTTON"), "wide"))
    cards = [alerts_card(), reset]
    return page(theme, 0, cards, LEFT, module="idle") + page(theme, 0, cards, RIGHT, 330, "idle")


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


COACH_KINDS = [
    ("coach-dps", coach_dps, ["nebula", "warden"],
     "The Coach strip of a damage dealer: a predicted rise with its confidence",
     "La striscia del Coach per un DPS: un aumento previsto con la sua affidabilità"),
    ("coach-tank", coach_tank, ["nebula", "warden"],
     "The Coach strip of a tank: the second may overtake, with the margin",
     "La striscia del Coach per un tank: il secondo potrebbe superarti, con il margine"),
    ("coach-unknown", coach_unknown, ["nebula", "warden"], "Not enough data for advice, and why",
     "Dati insufficienti per un consiglio, e perché"),
    ("alert-danger", alert_danger, ["nebula", "warden"],
     "An alert in the strip, with the border in the colour of its state",
     "Un avviso nella striscia, con il bordo nel colore del suo stato"),
    ("alert-muted", alert_muted, ["nebula", "warden"], "Alerts muted until the end of the fight",
     "Avvisi silenziati fino alla fine del combattimento"),
]

MONITOR_KINDS = [
    ("monitor-values", monitor_values, THEMES,
     "The monitor with threat values: a damage dealer in WARNING with a prediction, one in DANGER",
     "Il monitor con i valori di threat: un DPS in ATTENZIONE con la previsione, uno in PERICOLO"),
    ("monitor-tank", monitor_tank, ["nebula", "warden"], "The tank's view, with the margin over the second",
     "La vista del tank, con il margine sul secondo"),
    ("monitor-state", monitor_state, ["nebula", "warden"],
     "State only: the client hides the values, the monitor shows the game's state",
     "Solo stato: il client nasconde i valori, il monitor mostra lo stato del gioco"),
    ("monitor-unknown", monitor_unknown, ["nebula", "warden"], "Nothing readable: threat data unavailable",
     "Nulla di leggibile: dati di threat non disponibili"),
    ("monitor-no-target", monitor_no_target, ["nebula", "warden"], "No target", "Nessun bersaglio"),
    ("monitor-demo", monitor_demo, ["nebula", "warden"], "Demo mode: an invented fight, said to be one",
     "Modalità demo: uno scontro inventato, dichiarato tale"),
    ("settings-monitor", settings_monitor, ["nebula", "warden"],
     "Settings: the Monitor card, its top and the page scrolled down",
     "Impostazioni: la card Monitor, la parte alta e la pagina scorsa in basso"),
    ("settings-alerts", settings_alerts, ["nebula", "warden"],
     "Settings: the Alerts card with the note of the game's own threat warning",
     "Impostazioni: la card Avvisi con la nota dell'avviso della threat del gioco"),
]

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
    for _kind, _fn, _themes, _en, _it in MONITOR_KINDS + COACH_KINDS:
        for _theme in _themes:
            _name = f"{_kind}-{_theme}" + ("-it" if _lang == "itIT" else "")
            _caption = f"{_en if _lang == 'enUS' else _it} ({THEME_NAMES[_theme]})"
            SCENES.append((_name, _caption, (lambda f=_fn, t=_theme: f(t)), _lang, _theme))
