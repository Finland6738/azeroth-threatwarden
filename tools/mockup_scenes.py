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
# The default thresholds (Core/Config.lua MONITOR_DEFAULTS, SPEC-09 Q7, decided by the owner on 2026-11-26).
WARNING, DANGER = 82, 91
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
        ticks = f'<u style="left:{WARNING}%"></u><u style="left:{DANGER}%"></u>'
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
    lines = [T("COACH_RISING"), T("STRIP_WHY", T("COACH_WHY_TREND", DANGER, 4, T("CONF_MEDIUM"))),
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
    lines = [T("ALERT_DANGER", 97), T("STRIP_WHY", T("ALERT_WHY_P_DANGER", DANGER)),
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


def page(theme, selected, cards, x, scroll=0, module="off", reports=False):
    body = (f'<div class="page">{pager(selected)}<div class="scroll"><div class="column" style="margin-top:-{scroll}px">'
            f'{"".join(cards)}</div></div></div>')
    return window(theme, "settings", body, x, TOP, module=module, reports=reports)


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

    inner = (slide("SET_WARNING", 50, 95, WARNING, T("SET_PERCENT", WARNING))
             + slide("SET_DANGER", 60, 100, DANGER, T("SET_PERCENT", DANGER)) + note(T("SET_THRESHOLDS_NOTE", 5))
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
             + note(T("SET_ALERTS_THRESHOLDS", WARNING, DANGER), "margin-top:12px;color:var(--text-2)")
             + button(T("SET_ALERTS_TO_MONITOR"), "wide", "margin-top:8px")
             + note(T("SET_ALERTS_NATIVE"), "margin-top:12px;color:var(--warn)")
             + row(T("SET_COACH"), switch(True)))
    return card(T("SET_ALERTS"), inner)


def settings_alerts(theme):
    reset = card(T("SET_RESET"), f'<div class="body">{esc(T("SET_RESET_TEXT_ALERTS"))}</div>'
                 + button(T("SET_RESET_BUTTON"), "wide"))
    cards = [alerts_card(), reset]
    return page(theme, 0, cards, LEFT, module="idle") + page(theme, 0, cards, RIGHT, 330, "idle")


# ---- the Reports tab (UI/Reports.lua). Invented data: the places, the players and the fights do not exist. -----------

def cat(kind, label=None):
    return f'<span class="cat {kind}">{esc(label or T("CAT_" + kind.upper()))}</span>'


def report_date(day, hour):
    pattern = T("REPORTS_DATE_FORMAT")
    return (pattern.replace("{Y}", "2026").replace("{m}", "11").replace("{d}", day).replace("{H}", hour[:2])
            .replace("{M}", hour[3:]))


def report_row(day, hour, zone, mob, length, state, badges=(), on=False):
    pills = "".join(cat(kind, T(key)) for key, kind in badges)
    return (f'<div class="rrow{" on" if on else ""}"><div class="line"><b>{esc(report_date(day, hour))} · {esc(zone)}</b>'
            f'<em>{esc(length)}</em></div><div class="line low"><span>{esc(mob)}</span>'
            f'<span class="right">{pills}{badge(state)}</span></div></div>')


def report_list(count=4, selected=None):
    rows = [("26", "21:14", "Gloomhold", "Gorrak", "1:42", "warning", ()),
            ("26", "21:09", "Gloomhold", "Gloom whelp", "0:31", "safe", (("REPORTS_BADGE_CONTINUES", "detected"),)),
            ("26", "21:05", "Gloomhold", "Gloom whelp", T("REPORT_AT_LEAST", "0:18"), "unknown",
             (("REPORTS_BADGE_INTERRUPTED", "warn"),)),
            ("25", "22:40", "Frostpeak", "Old Skarn", "6:03", "danger", (("REPORTS_BADGE_LIMIT", "warn"),))]
    return "".join(report_row(*r, on=(i == selected)) for i, r in enumerate(rows[:count]))


def usage_line():
    text = T("REPORTS_USAGE", T("REPORTS_COUNT", 12), T("REPORTS_KB", 640), T("REPORTS_MB_WHOLE", 2))
    return f'<div class="usage">{esc(text)}{cat("estimated")}</div>'


def metric(key, kind, value, off=False):
    return (f'<div class="metric"><div class="head2"><span>{esc(T(key))}</span>{cat(kind)}</div>'
            f'<div class="val{" off" if off else ""}">{esc(value)}</div></div>')


def report_head(mob, headline=None):
    extra = f'<div class="body" style="color:var(--warn)">{esc(headline)}</div>' if headline else ""
    return card(None, f'<h2>{esc(mob)}</h2><div class="note">{esc(report_date("26", "21:14"))} · Gloomhold</div>{extra}'
                f'<div class="buttons">{button(T("REPORTS_DELETE"))}{button(T("REPORTS_CLOSE"), "ghost")}</div>')


def report_page(theme, cards, x, scroll, module):
    body = (f'<div class="page">{usage_line()}<div style="margin-top:6px">{report_list(3, 0)}</div>'
            f'<div style="position:absolute;left:0;right:0;top:172px;bottom:0;overflow:hidden">'
            f'<div class="column" style="margin-top:-{scroll}px">{"".join(cards)}</div></div></div>')
    return window(theme, "reports", body, x, TOP, module=module, reports=True)


def reports_list(theme):
    full = f'<div class="page">{usage_line()}<div style="margin-top:6px">{report_list()}</div></div>'
    empty = (f'<div class="page"><div class="empty2"><h2>{esc(T("REPORTS_EMPTY"))}</h2>'
             f'<p>{esc(T("REPORTS_EMPTY_GROUP"))}</p></div></div>')
    return (window(theme, "reports", full, LEFT, TOP, module="idle", reports=True)
            + window(theme, "reports", empty, RIGHT, TOP, module="idle", reports=True))


def report_scene(theme, kind):
    na = T("REPORT_NA")
    quality = {"values": (96, 0, 4), "state": (0, 93, 7), "unknown": (0, 0, 100)}[kind]
    fight = [metric("REPORT_METRIC_DURATION", "detected", "1:42 · " + T("REPORT_IN_COMBAT", "1:38"))]
    if kind == "unknown":
        fight += [metric("REPORT_METRIC_TANKS", "unknown", T("REPORT_NA_TANKS"), True),
                  metric("REPORT_METRIC_AGGRO_LOSSES", "unknown", na, True),
                  metric("REPORT_METRIC_QUALITY", "calculated", T("REPORT_QUALITY", *quality)),
                  metric("REPORT_METRIC_DEATHS", "detected", T("REPORT_NO_DEATH"))]
    else:
        held = T("REPORT_DESIGNATED", T("REPORT_HELD", "Bram", T("REPORT_SECONDS", 84.0)))
        loss = T("REPORT_AGGRO_FROM", "1:02", "Kor", "Bram")
        if kind == "values":
            loss = T("REPORT_WITH_POINTS", loss, T("REPORT_POINTS", 24))
        fight += [metric("REPORT_METRIC_TANKS", "detected", held),
                  metric("REPORT_METRIC_AGGRO_LOSSES", "detected", loss),
                  metric("REPORT_METRIC_QUALITY", "calculated", T("REPORT_QUALITY", *quality))]
    cards = [report_head("Gorrak · " + T("MON_CLASS_BOSS")), card(T("REPORTS_SECTION_FIGHT"), "".join(fight))]
    sub = f'<div class="note">{esc(T("ROLE_DAMAGER"))}</div>'
    if kind == "unknown":
        mine = (f'<div class="body" style="color:var(--text-3)">{esc(na)} · {esc(T("REPORT_WHY_SECRET"))}</div>'
                + metric("REPORT_METRIC_QUALITY", "calculated", T("REPORT_QUALITY", *quality)))
    else:
        warning = T("REPORT_AT_LEAST", T("REPORT_SECONDS", 12.0)) + " · " + T("REPORT_UNKNOWN_TIME",
                                                                              T("REPORT_SECONDS", 4.0))
        mine = (metric("REPORT_METRIC_WARNING_CROSS", "estimated", T("REPORT_AT_LEAST", "2"))
                + metric("REPORT_METRIC_WARNING_TIME", "estimated", warning))
        if kind == "values":
            mine += metric("REPORT_METRIC_MAX", "detected", T("REPORT_MAX", 96, "1:01"))
        else:
            mine += metric("REPORT_METRIC_MAX", "unknown", na, True)
    cards.append(card(T("UNIT_YOU"), sub + mine))
    scroll = 300 if kind == "unknown" else 360
    return report_page(theme, cards, LEFT, 0, "idle") + report_page(theme, cards, RIGHT, scroll, "idle")


def report_values(theme):
    return report_scene(theme, "values")


def report_state(theme):
    return report_scene(theme, "state")


def report_unknown(theme):
    return report_scene(theme, "unknown")


# ---- the timeline card and the replay window (UI/Timeline.lua, UI/ReplayWindow.lua). Invented data. -----------------

REPLAY_ICONS = {
    "skip-back": '<path d="M5 5h3v14H5z" fill="currentColor" stroke="none"/><path d="M20 4 9 12l11 8z" fill="currentColor" stroke="none"/>',
    "skip-forward": '<path d="M16 5h3v14h-3z" fill="currentColor" stroke="none"/><path d="M4 4l11 8-11 8z" fill="currentColor" stroke="none"/>',
    "step-back": '<path d="M15 5 8 12l7 7" stroke-width="3.4"/>', "step-forward": '<path d="M9 5l7 7-7 7" stroke-width="3.4"/>',
    "play": '<path d="M6 4l15 8-15 8z" fill="currentColor" stroke="none"/>',
    "flag": '<path d="M5 22V3M5 4h13l-3 4 3 4H5"/>', "skull": '<path d="M12 3a8 8 0 0 0-5 14v3h10v-3a8 8 0 0 0-5-14z"/><path d="M9 11h.01M15 11h.01" stroke-width="3.5"/>',
    "bell": '<path d="M6 9a6 6 0 0 1 12 0c0 6 2 7 2 8H4c0-1 2-2 2-8zM10 21h4"/>',
    "warn": '<path d="M12 3 22 20H2z"/><path d="M12 10v4M12 17v.01"/>', "dot": '<circle cx="12" cy="12" r="5" fill="currentColor" stroke="none"/>',
}
SERIES = ("series-1", "series-3", "series-2")
SPAN = 220.0   # seconds of the invented fight


def ricon(name, size=10, token=None):
    colour = f' style="color:var(--{token});display:grid"' if token else ' style="display:grid"'
    return f'<span{colour}>{lib._svg(REPLAY_ICONS.get(name) or ICONS[name], size)}</span>'


def clock(seconds, tenths=True):
    m, s = int(seconds // 60), seconds % 60
    return f"{m}:{s:04.1f}" if tenths else f"{m}:{int(s):02d}"


def names():
    return (T("UNIT_YOU"), "Bram", "Kor")


def chart(kind, width, height, cursor=None, selection=None, legend=True, lanes=True, view=None):
    """The widget of the timeline as an SVG: legend, chart or note, lanes, event track and time axis. `view` (a, b)
    in seconds: zoomed on the window of an event."""
    left, right = 30, width - 6
    va, vb = view or (0.0, SPAN)
    x = lambda t: left + (right - left) * (min(max(t, va), vb) - va) / (vb - va)
    out, y = [], 0
    who = names()
    show_chart = kind == "values"
    if legend and show_chart:
        lx = left
        for name, token, peak in zip(who, SERIES, ("94.0 %", "100.0 %", "88.5 %")):
            out.append(f'<rect x="{lx}" y="7" width="12" height="2" fill="var(--{token})"/>'
                       f'<text x="{lx + 17}" y="12" class="lg">{esc(name)}</text>'
                       f'<text x="{lx + 17 + len(name) * 6.5 + 8}" y="12" class="mn">{peak}</text>')
            lx += 17 + len(name) * 6.5 + 70
        y = 20
    lanes_h = (12 + 3 * 8) if lanes else 12
    if kind == "unknown":
        lanes_h = 0
    chart_h = height - y - lanes_h - 2 - 16 - 14 if show_chart else 44
    bottom = y + chart_h
    py = lambda p: bottom - chart_h * min(p, 110) / 110
    if show_chart:
        for p, label in ((0, "0"), (50, "50"), (100, "100")):
            out.append(f'<line x1="{left}" x2="{right}" y1="{py(p):.1f}" y2="{py(p):.1f}" stroke="var(--border-'
                       f'{"strong" if p == 100 else "subtle"})"/><text x="{left - 5}" y="{py(p) + 4:.1f}" class="ax" '
                       f'text-anchor="end">{label}</text>')
        for p, token in ((WARNING, "state-warning"), (DANGER, "state-danger")):
            out.append(f'<line x1="{left}" x2="{right}" y1="{py(p):.1f}" y2="{py(p):.1f}" stroke="var(--{token})" '
                       f'opacity=".8"/>')
            # labels only where they do not run into each other
            if p == DANGER or py(WARNING) - py(DANGER) >= 12:
                out.append(f'<text x="{right - 2}" y="{py(p) - 3:.1f}" class="ax" text-anchor="end">{p}</text>')
        # a gap: hatched band with its reason, never crossed by a line (zoomed: a pause of the recording)
        gap_a, gap_b = (132, 133.4) if view else (96, 118)
        gx, gw = x(gap_a), x(gap_b) - x(gap_a)
        out.append(f'<rect x="{gx:.1f}" y="{y}" width="{gw:.1f}" height="{chart_h}" fill="url(#hatch)"/>'
                   f'<text x="{gx + gw / 2:.1f}" y="{y + 14}" class="gap" text-anchor="middle">'
                   f'{esc(T("TIMELINE_GAP_TICK", T("REPORT_SECONDS", 1.4)) if view else T("TIMELINE_WHY_SECRET"))}</text>')

        def line(points, token, width_=1.6, dash=False):
            path = " ".join(f"{x(t):.1f},{py(p):.1f}" for t, p in points)
            extra = ' stroke-dasharray="4 3"' if dash else ""
            out.append(f'<polyline points="{path}" fill="none" stroke="var(--{token})" stroke-width="{width_}"{extra}/>')

        if view:
            line([(129, 100), (130.5, 100), (132, 100)], "series-3")
            line([(133.4, 100), (136, 100), (139, 100)], "series-3")
            line([(129, 76), (129.5, 78), (130, 81), (130.5, 82), (131, 85), (131.5, 87), (132, 88)], "series-1", 2)
            line([(133.4, 92), (134, 94), (135, 86), (136, 79)], "series-1", 2)
            line([(136, 79), (137.5, 70)], "series-1", 2, True)
            line([(137.5, 70), (138, 66), (139, 61)], "series-1", 2)
            line([(131.5, 58), (132, 59)], "series-2")
            line([(133.4, 62), (135, 66), (137, 72), (139, 78)], "series-2")
        else:
            line([(0, 100), (30, 100), (60, 100), (92, 100)], "series-3")
            line([(120, 100), (150, 100), (190, 100), (220, 100)], "series-3")
            line([(2, 18), (10, 34), (18, 41), (26, 55), (34, 58), (42, 69), (50, 66), (58, 74), (66, 79), (74, 84),
                  (82, 82), (92, 86)], "series-1", 2)
            line([(120, 70), (128, 78), (136, 94), (146, 76), (156, 61)], "series-1", 2)
            line([(156, 61), (166, 64)], "series-1", 2, True)
            line([(166, 64), (176, 57), (188, 66), (198, 72), (208, 70), (220, 75)], "series-1", 2)
            line([(2, 8), (14, 22), (28, 30), (40, 29), (54, 47), (68, 52), (80, 63), (92, 61)], "series-2")
            line([(120, 44), (134, 55), (150, 88), (162, 70), (180, 73), (200, 60), (220, 66)], "series-2")
        top = bottom + 2
    else:
        text = T("TIMELINE_OUTCOME_STATE") if kind == "state" else T("TIMELINE_OUTCOME_NONE", T("TIMELINE_WHY_SECRET"))
        out.append(f'<foreignObject x="{left}" y="{y}" width="{right - left}" height="40"><div '
                   f'xmlns="http://www.w3.org/1999/xhtml" class="onote">{esc(text)}</div></foreignObject>')
        top = bottom + 2
    # lanes: who holds the enemy, then the states
    if lanes_h:
        holder = [(0, 150, "series-3"), (150, 156, "series-2"), (156, 220, "series-3")]
        for a, b, token in (h for h in holder if h[1] > va and h[0] < vb):
            out.append(f'<rect x="{x(a):.1f}" y="{top}" width="{x(b) - x(a):.1f}" height="10" fill="var(--{token})"/>')
        top += 12
        rows = [[(0, 66, "safe"), (66, 96, "warning"), (96, 120, "unknown"), (120, 134, "safe"),
                 (134, 142, "danger"), (142, 220, "safe")],
                [(0, 220, "safe")],
                [(0, 78, "safe"), (96, 120, "unknown"), (78, 96, "safe"), (120, 148, "safe"), (148, 160, "warning"),
                 (160, 220, "safe")]]
        for lane in rows if lanes else []:
            for a, b, state in (p for p in lane if p[1] > va and p[0] < vb):
                fill = "url(#hatch)" if state == "unknown" else f"var(--state-{state})"
                out.append(f'<rect x="{x(a):.1f}" y="{top}" width="{x(b) - x(a):.1f}" height="6" fill="{fill}"/>')
            top += 8
    events = [(0, "flag", "text-2"), (66, "state-warning", "state-warning"), (72.4, "bell", "state-warning"),
              (134, "state-danger", "state-danger"), (150, "warn", "state-danger"), (156, "tank", "text-2"),
              (178, "skull", "text-1")]
    if kind == "unknown":
        events = [(0, "flag", "text-2"), (96, "warn", "text-2"), (178, "skull", "text-1")]
    for t, name, token in (e for e in events if va <= e[0] <= vb):
        out.append(f'<g transform="translate({x(t) - 5:.1f},{top + 3})" style="color:var(--{token})">'
                   f'{lib._svg(REPLAY_ICONS.get(name) or ICONS[name], 10)}</g>')
    axis = top + 16
    for t in (range(int(va) + 1, int(vb) + 1, 2) if view else range(0, 221, 30)):
        anchor = "start" if t == 0 else "middle"
        out.append(f'<rect x="{x(t):.1f}" y="{axis}" width="1" height="3" fill="var(--border-strong)"/>'
                   f'<text x="{x(t):.1f}" y="{axis + 13}" class="ax" text-anchor="{anchor}">{clock(t, False)}</text>')
    if selection:
        a, b = selection
        out.append(f'<rect x="{x(a):.1f}" y="{y}" width="{x(b) - x(a):.1f}" height="{axis - y}" fill="var(--accent)" '
                   f'opacity=".15"/>')
    if cursor is not None:
        out.append(f'<rect x="{x(cursor):.1f}" y="{y}" width="1.5" height="{axis - y}" fill="var(--accent)"/>')
    total = axis + 15
    hatch = ('<defs><pattern id="hatch" width="8" height="8" patternUnits="userSpaceOnUse"><rect width="8" height="8" '
             'fill="var(--surface-2)"/><rect width="4" height="8" fill="var(--state-unknown)" opacity=".5"/></pattern></defs>')
    return f'<svg class="tl" width="{width}" height="{total}" viewBox="0 0 {width} {total}">{hatch}{"".join(out)}</svg>'


def report_timeline(theme):
    head = report_head("Gorrak · " + T("MON_CLASS_BOSS"))
    timeline = (f'<div class="card"><h2>{esc(T("TIMELINE_TITLE"))}</h2><div style="margin-top:8px">'
                f'{chart("values", 478, 140, legend=False, lanes=False)}</div>'
                f'<div class="note" style="margin-top:6px">{esc(T("TIMELINE_CARD_HINT"))}</div></div>')
    buttons = (f'<div class="buttons">{button(T("REPORTS_DELETE"))}{button(T("REPORTS_REPLAY"), "primary")}'
               f'{button(T("REPORTS_CLOSE"), "ghost")}</div>')
    head = head.replace(f'<div class="buttons">{button(T("REPORTS_DELETE"))}{button(T("REPORTS_CLOSE"), "ghost")}</div>',
                        buttons)
    fight = card(T("REPORTS_SECTION_FIGHT"), metric("REPORT_METRIC_DURATION", "detected",
                                                    "3:40 · " + T("REPORT_IN_COMBAT", "3:36")))
    cards = [head, timeline, fight]
    return report_page(theme, cards, LEFT, 0, "idle") + report_page(theme, cards, RIGHT, 150, "idle")


def event_row(time, icon_name, token, text, kind="detected", state=""):
    return (f'<div class="erow{" " + state if state else ""}"><em>{time}</em>{ricon(icon_name, 10, token)}'
            f'<span>{esc(text)}</span>{cat(kind)}</div>')


def event_rows(kind, focus=None):
    who = names()
    warning = T("TIMELINE_WITH", T("TIMELINE_STATE", who[0], T("TIMELINE_STATE_WARNING")),
                T("TIMELINE_THRESHOLDS", WARNING, DANGER))
    game = T("TIMELINE_WITH", T("TIMELINE_STATE", who[0], T("TIMELINE_STATE_WARNING")), T("TIMELINE_GAME_STATE"))
    rows = [("0:00.0", "flag", "text-2", T("TIMELINE_COMBAT_STARTED"), "detected")]
    if kind == "values":
        rows += [("1:06.0", "state-warning", "state-warning", warning, "calculated"),
                 ("1:12.4", "bell", "state-warning", T("TIMELINE_ALERT", T("REPORT_ALERT_WARNING")), "calculated"),
                 ("2:14.0", "state-danger", "state-danger",
                  T("TIMELINE_STATE", who[0], T("TIMELINE_STATE_DANGER")), "calculated"),
                 ("2:30.0", "warn", "state-danger", T("TIMELINE_TOOK_FROM", "Kor", "Bram"), "detected"),
                 ("2:36.0", "tank", "text-2", T("TIMELINE_HOLDS", "Bram"), "detected"),
                 ("2:58.0", "skull", "text-1", T("TIMELINE_DIED", "Kor"), "detected")]
    elif kind == "state":
        rows += [("1:06.0", "state-warning", "state-warning", game, "detected"),
                 ("2:30.0", "warn", "state-danger", T("TIMELINE_TOOK_FROM", "Kor", "Bram"), "detected"),
                 ("2:58.0", "skull", "text-1", T("TIMELINE_DIED", "Kor"), "detected")]
    else:
        rows += [("1:36.0", "warn", "text-2", T("TIMELINE_MODE_NONE", T("TIMELINE_WHY_SECRET")), "unknown"),
                 ("2:58.0", "skull", "text-1", T("TIMELINE_DIED", "Kor"), "detected")]
    return "".join(event_row(*r, state=("focus" if focus == i else "")) for i, r in enumerate(rows[:6]))


def dline(text, tone="", style=""):
    return f'<div class="dline {tone}" style="{style}">{esc(text)}</div>'


def unit_row(name, state, reading, token=None, tone=""):
    dash = f'<i style="background:var(--{token})"></i>' if token else "<i></i>"
    return (f'<div class="unit"><div class="top">{dash}<b>{esc(name)}</b>{badge(state)}</div>'
            f'<div class="reading {tone}">{esc(reading)}</div></div>')


def moment(kind, time):
    who = names()
    mob = "Gorrak"
    mode = {"values": "REPLAY_MODE_VALUES", "state": "REPLAY_MODE_STATE"}.get(kind)
    mode = T(mode) if mode else T("REPLAY_MODE_NONE", T("TIMELINE_WHY_SECRET"))
    out = [f'<div class="dline head">{esc(T("REPLAY_AT", time))}</div>',
           dline(" · ".join((mob, mode, T("REPLAY_COMBAT"))), "off" if kind == "unknown" else "")]
    if kind != "unknown":
        out.append(dline(T("REPLAY_HOLDS_TANK", "Bram")))
    if kind == "values":
        out += [unit_row(who[0], "warning", "84.2 %", "series-1"),
                unit_row("Bram", "safe", "100.0 %", "series-3"),
                unit_row("Kor", "safe", T("REPLAY_ESTIMATE", "61.0 %", 1.8), "series-2", "warn")]
    elif kind == "state":
        out += [unit_row(who[0], "warning", T("REPLAY_SITUATION_1")),
                unit_row("Bram", "safe", T("REPLAY_SITUATION_3")),
                unit_row("Kor", "safe", T("REPLAY_SITUATION_0"))]
    return "".join(out)


def replay_window(theme, kind, focus=False):
    cursor = {"values": 72.4, "state": 72.4, "unknown": 120.0}[kind]
    focused = None
    selection = view = None
    if focus:                      # a focused event of a long fight: its window is selected and in view
        cursor, focused, selection = 134.0, 3, (129, 139)
        view = selection
    head = (f'<div class="bar">{lib.logo()}<span><span class="name">{esc(T("REPLAY_TITLE"))}</span>'
            f'<span class="state">{esc(report_date("26", "21:14"))} · Gloomhold · Gorrak · 3:40</span></span>'
            f'<span class="icons"><span>{lib.icon_cross()}</span></span></div>')
    heights = {"values": 236, "state": 150, "unknown": 90}
    graph = chart(kind, 796, heights[kind], cursor=cursor, selection=selection, view=view)
    buttons = ['skip-back', ('step-back', 'step-back'), 'step-back', 'play', 'step-forward',
               ('step-forward', 'step-forward'), 'skip-forward']
    controls = "".join(
        f'<span class="ctl">{"".join(ricon(n, 10) for n in b) if isinstance(b, tuple) else ricon(b, 14)}</span>'
        for b in buttons)
    speed = seg([T("REPLAY_SPEED_ITEM", s) for s in (1, 2, 4, 8)], 0)
    zoom = (f'<span class="zoombtns">{button(T("REPLAY_ZOOM_SELECTION"), "" if focus else "off")}'
            f'{button(T("REPLAY_WHOLE"), "" if focus else "off")}</span>')
    controls = (f'<div class="controls">{controls}{speed}<span class="mono time">{clock(cursor)} / 3:40</span>{zoom}</div>')
    tabs = seg([T("REPLAY_FILTER_KEY"), T("REPLAY_FILTER_ALERTS"), T("REPLAY_FILTER_ALL")], 0)
    events = (f'<div class="panel"><div class="ph">{"" if len(T("REPLAY_FILTER_ALERTS")) > 14 else "<h2>" + esc(T("REPLAY_EVENTS")) + "</h2>"}'
              f'{tabs}</div>{event_rows(kind, focused)}</div>')
    if focus:
        who = names()
        detail = (f'<div class="dline head">{esc(T("REPLAY_SELECTED_EVENT"))}</div>'
                  + dline(T("TIMELINE_STATE", who[0], T("TIMELINE_STATE_DANGER")))
                  + dline(T("REPLAY_EVENT_READINGS", who[0], 14, "76.0 %", "61.0 %", "94.0 %"))
                  + f'<div class="dline head">{esc(T("REPLAY_MISSING_TITLE"))}</div>'
                  + dline(T("REPLAY_MISSING_UNIT", "Kor", "2:09.0", "2:11.5", T("TIMELINE_WHY_SECRET")), "off")
                  + dline(T("REPLAY_MISSING_TICK", "2:12.0", "2:13.4"), "off") + moment("values", clock(cursor)))
    else:
        detail = moment(kind, clock(cursor))
    body = (f'<div class="rbody">{graph}{controls}<div class="panels">{events}<div class="panel detail">{detail}</div>'
            f'</div></div>')
    return (f'<div class="win replay {theme}" style="left:48px;top:9px;transform:scale(1.35);transform-origin:0 0">'
            f'{head}{body}{lib.GRIP}</div>')


def replay_values(theme):
    return replay_window(theme, "values")


def replay_state(theme):
    return replay_window(theme, "state")


def replay_unknown(theme):
    return replay_window(theme, "unknown")


def replay_event(theme):
    return replay_window(theme, "values", focus=True)


# The Recording card of Settings (M4.5, with the `recording` switch on) and the Reset card below it.
def recording_card():
    def slide(label, fraction, value):
        return row(T(label), lib.slider(fraction, value))

    usage = T("SET_RECORDING_USAGE", T("REPORTS_USAGE", T("REPORTS_COUNT", 12), T("REPORTS_KB", 640),
                                       T("REPORTS_MB_WHOLE", 2)))
    inner = (row(T("SET_RECORDING_ENABLED"), switch(True))
             + f'<div class="row"><b>{esc(T("SET_RECORDING_WHEN"))}</b></div>'
             + seg([T("SET_WHEN_GROUP"), T("SET_WHEN_INSTANCE"), T("SET_WHEN_ALWAYS")], 0, "margin-top:4px")
             + slide("SET_RECORDING_RATE", (2 - 1) / 4, T("SET_HERTZ", 2)) + note(T("SET_RECORDING_RATE_NOTE"))
             + slide("SET_RECORDING_SESSIONS", (25 - 5) / 95, "25")
             + slide("SET_RECORDING_SIZE", (2048 - 512) / 7680, T("REPORTS_MB_WHOLE", 2))
             + note(T("SET_RECORDING_LIMITS_NOTE")) + row(T("SET_RECORDING_NOTICE"), switch(False))
             + note(T("SET_RECORDING_NOTICE_NOTE")) + note(usage, "margin-top:12px;color:var(--text-2)")
             + button(T("SET_RECORDING_DELETE"), "wide", "margin-top:12px;width:300px")
             + note(T("SET_RECORDING_NAMES"), "margin-top:12px"))
    return card(T("SET_RECORDING"), inner)


def settings_recording(theme):
    reset = card(T("SET_RESET"), f'<div class="body">{esc(T("SET_RESET_TEXT_RECORDING"))}</div>'
                 + button(T("SET_RESET_BUTTON"), "wide"))
    cards = [recording_card(), reset]
    return (page(theme, 0, cards, LEFT, module="idle", reports=True)
            + page(theme, 0, cards, RIGHT, 300, "idle", reports=True))


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

REPORT_KINDS = [
    ("reports-list", reports_list, ["nebula", "warden"],
     "The Reports tab: the list of recordings, and the empty list with its reason",
     "La scheda Report: l'elenco delle registrazioni, e l'elenco vuoto con il motivo"),
    ("report-values", report_values, ["nebula", "warden"],
     "A report with threat values, each metric with its category",
     "Un report con i valori di threat, ogni metrica con la sua categoria"),
    ("report-state", report_state, ["nebula", "warden"],
     "A report when only the state is readable: no percentages", "Un report quando si legge solo lo stato: niente percentuali"),
    ("report-unknown", report_unknown, ["nebula", "warden"], "A report when nothing was readable, and why",
     "Un report quando nulla era leggibile, e perché"),
    ("settings-recording", settings_recording, ["nebula", "warden"],
     "Settings: the Recording card, its top and the page scrolled down",
     "Impostazioni: la card Registrazione, la parte alta e la pagina scorsa in basso"),
]

REPLAY_KINDS = [
    ("replay-values", replay_values, THEMES,
     "The replay of a fight with threat values: the chart, the controls, the events and the detail at the cursor",
     "Il replay di uno scontro con i valori di threat: grafico, comandi, eventi e dettaglio al cursore"),
    ("replay-state", replay_state, ["nebula"],
     "The replay when only the state is readable: lanes and states, no percentages",
     "Il replay quando si legge solo lo stato: corsie e stati, niente percentuali"),
    ("replay-unknown", replay_unknown, ["nebula"], "The replay when nothing was readable, and why",
     "Il replay quando nulla era leggibile, e perché"),
    ("replay-event", replay_event, ["nebula"],
     "A selected event: the window of 5 s around it and its missing data",
     "Un evento selezionato: la finestra di 5 s intorno e i dati mancanti"),
    ("report-timeline", report_timeline, ["nebula"],
     "The report with the Timeline card and the Replay button",
     "Il report con la card Timeline e il pulsante Replay"),
]

# ---- Analytics (UI/Analytics.lua, M6.4). Invented data: the places, the players and the fights do not exist. --------

def analytics_head(on, reports=True):
    selector = seg([T("ANALYTICS_PAGE_RECORDINGS"), T("ANALYTICS_PAGE")], on)
    if on:
        text = T("ANALYTICS_HEADER", T("REPORTS_COUNT", 12), T("ANALYTICS_ENEMIES_COUNT", 3))
        side = f'<span style="color:var(--text-1);font-weight:500">{esc(text)}</span>'
    else:
        text = T("REPORTS_USAGE", T("REPORTS_COUNT", 12), T("REPORTS_KB", 640), T("REPORTS_MB_WHOLE", 2))
        side = f'<span style="color:var(--text-1);font-weight:500">{esc(text)}</span>{cat("estimated")}'
    return (f'<div style="display:flex;flex-wrap:wrap;gap:4px 12px;align-items:center;margin-bottom:8px">{selector}'
            f'<span style="display:flex;gap:8px;align-items:center">{side}</span></div>')


MONO = "font:500 11px/13px 'JetBrains Mono',monospace"


def enemy_row(name, group, numbers, on=False):
    back = "background:var(--surface-2);box-shadow:inset 2px 0 0 var(--accent);" if on else ""
    right = f'<span style="color:var(--text-2);font-size:11px">{esc(group)}</span>' if group else ""
    low = f'<div style="{MONO};color:var(--text-2);white-space:nowrap;overflow:hidden">{esc(numbers)}</div>'
    return (f'<div style="height:32px;padding:1px 8px;{back}"><div style="display:flex;justify-content:space-between">'
            f'<span>{esc(name)}</span>{right}</div>{low}</div>')


def enemies_card(selected):
    def numbers(count, combat, day, hour, low, high):
        return " · ".join([T("ANALYTICS_FIGHTS", count), T("ANALYTICS_IN_COMBAT", combat), report_date(day, hour),
                           T("ANALYTICS_READABLE_RANGE", low, high)])
    rows = (enemy_row(T("ANALYTICS_ENEMY_CLASS", "Gorrak", T("MON_CLASS_ELITE")), T("ANALYTICS_GROUP_PARTY"),
                      numbers(5, "8:12", "26", "21:14", 62, 100), selected)
            + enemy_row("Old Skarn", T("ANALYTICS_GROUP_RAID"), numbers(3, "17:40", "25", "22:40", 88, 97))
            + enemy_row(T("ANALYTICS_UNKNOWN_ENEMIES"), "", T("ANALYTICS_FIGHTS", 2)))
    return card(T("ANALYTICS_ENEMIES"), f'<div style="margin-top:8px">{rows}</div>')


def mark(kind):
    colour = "var(--warn)" if kind == "ESTIMATED" else "var(--text-2)"
    return f'<span style="color:{colour};font-size:11px;margin-right:3px">{esc(T("ANALYTICS_MARK_" + kind))}</span>'


def table_cell(value, kind):
    if kind is None:
        return f'<span style="color:var(--text-3)">{esc(value)}</span>'
    colour = "var(--warn)" if kind == "ESTIMATED" else "var(--text-1)"
    return f'{mark(kind)}<span style="color:{colour}">{esc(value)}</span>'


def compare_table(columns):
    keys = ["DATE", "LENGTH", "READABLE", "CROSSINGS", "DANGER", "HOLDERS", "UNSTABLE", "RISK", "HIGHEST",
            "CLOSEST"][:columns]
    c, d, e = "CALCULATED", "DETECTED", "ESTIMATED"
    na, nc = T("REPORT_INSUFFICIENT"), T("ANALYTICS_NOT_COMPARABLE")

    def pct(v):
        return T("TIMELINE_PERCENT", v)

    rows = [
        (T("ANALYTICS_ALL_FIGHTS"), [("1:42", c), (T("ANALYTICS_PCT_WHOLE", 94), c), ("3 / 1", c), ("0:06", c),
                                     ("2", c), ("1 · 0:08", c), ("1.4", c), (pct(88.0), c), (pct(96.4), c)]),
        (report_date("26", "21:14"), [("1:42", d), (T("ANALYTICS_PCT_WHOLE", 98), c), ("4 / 1", c), ("0:06", c),
                                      ("2", d), ("1 · 0:08", c), ("1.8", c), (pct(91.0), d), (pct(96.4), d)]),
        (report_date("26", "20:51"), [(T("REPORT_AT_LEAST", "2:31"), e), (T("ANALYTICS_PCT_WHOLE", 38), c), (na, None),
                                      (na, None), (na, None), (na, None), (na, None), (na, None), (na, None)]),
        (report_date("25", "23:02"), [("1:30", d), (T("ANALYTICS_PCT_WHOLE", 91), c), (nc, None), (nc, None),
                                      ("1", d), (nc, None), (nc, None), (pct(84.2), d), (pct(90.1), d)]),
    ]
    head = "".join(f'<th style="text-align:{"left" if i == 0 else "right"};padding:0 4px;white-space:nowrap">'
                   f'{esc(T("ANALYTICS_COL_" + k))}</th>' for i, k in enumerate(keys))
    body = ""
    for i, (date, cells) in enumerate(rows):
        back = "background:var(--surface-2);" if i == 0 else ""
        tds = "".join(f'<td style="text-align:right;padding:0 4px;white-space:nowrap">{table_cell(v, k)}</td>'
                      for v, k in cells[:columns - 1])
        body += (f'<tr style="{back}height:22px"><td style="padding:0 4px;white-space:nowrap">{esc(date)}</td>'
                 f'{tds}</tr>')
    return (f'<table style="width:100%;border-collapse:collapse;margin-top:10px;{MONO}">'
            f'<tr style="height:22px;color:var(--text-3);font:600 11px/1 \'Outfit\',sans-serif">{head}</tr>{body}</table>')


def compare_card(columns):
    filters = "".join(
        f'<span style="display:inline-flex;gap:6px;align-items:center;margin-right:16px">'
        f'<span class="sw on" style="zoom:.7"></span><span style="font-size:11px;color:var(--text-2)">{esc(t)}</span></span>'
        for t in (T("ANALYTICS_FILTER_GROUP"), T("ANALYTICS_FILTER_DIFF"),
                  T("ANALYTICS_FILTER_ROLE_NAMED", T("ROLE_DAMAGER"))))
    context = " · ".join([T("ANALYTICS_FIGHTS", 3), T("ANALYTICS_CONTEXT_MEDIAN", "1:42"),
                          T("ANALYTICS_READABLE_RANGE", 38, 98)])
    inner = (f'<div style="margin-top:8px">{filters}</div><div class="body">{esc(context)}</div>'
             f'<div class="note" style="color:var(--warn);margin-top:6px">{esc(T("ANALYTICS_EXCLUDED_ONE"))}</div>'
             + compare_table(columns) + note(T("ANALYTICS_LEGEND"), "margin-top:6px"))
    return card(T("ANALYTICS_COMPARE_OF", "Gorrak"), inner)


def analytics_window(theme, cards, x, style="", module="idle", scroll=0):
    body = (f'<div class="page">{analytics_head(1)}<div class="column" style="margin-top:-{scroll}px">'
            f'{"".join(cards)}</div></div>')
    html = window(theme, "reports", body, x, TOP, module=module, reports=True)
    return html.replace('style="left:', f'style="{style}left:', 1)


def analytics_overview(theme):
    choose = card(T("ANALYTICS_COMPARE"), f'<div class="body" style="font-weight:500">{esc(T("ANALYTICS_CHOOSE"))}</div>')
    return (analytics_window(theme, [enemies_card(False), choose], LEFT)
            + analytics_window(theme, [compare_card(4)], RIGHT))


def analytics_compare(theme):
    return analytics_window(theme, [enemies_card(True), compare_card(9)], LEFT, "width:1152px;height:600px;")


def report_analytics(theme):
    def line(key, kind, value, off=False):
        return metric(key, kind, value, off)

    first = (line("ANALYTICS_METRIC_VALID", "calculated",
                  T("REPORT_QUALITY", 82, 0, 18) + " · " + T("ANALYTICS_COVERAGE", 96))
             + line("ANALYTICS_METRIC_CROSSINGS", "calculated",
                    T("ANALYTICS_CROSSINGS", "7", "2") + " · " + T("REPORT_BASIS_THRESHOLDS", WARNING, DANGER))
             + line("ANALYTICS_METRIC_STATE_TIME", "calculated", T("ANALYTICS_STATE_TIME", "0:24", "0:06"))
             + line("ANALYTICS_METRIC_HOLDERS", "detected", T("ANALYTICS_HOLDERS", "3", 1, 1, 1))
             + line("ANALYTICS_METRIC_AGGRO_TAKEN", "detected", "1"))
    intervals = "".join(
        f'<div style="color:var(--accent-text);font-size:11px;margin:3px 0 0 0">{esc(T("ANALYTICS_INTERVAL", a, b, n))}</div>'
        for a, b, n in (("0:12", "0:19", 3), ("0:51", "0:58", 4)))
    second = (line("ANALYTICS_METRIC_UNSTABLE", "calculated", T("ANALYTICS_UNSTABLE", "2", "0:14"))
              + intervals + note(T("ANALYTICS_REPLAY_HINT"))
              + line("ANALYTICS_METRIC_RISK", "unknown",
                     T("REPORT_INSUFFICIENT") + " · " + T("ANALYTICS_WHY_SHORT_KNOWN"), True)
              + line("ANALYTICS_METRIC_CLOSEST", "detected", T("ANALYTICS_CLOSEST", "Kor", T("TIMELINE_PERCENT", 96.4),
                                                               "1:12"))
              + f'<div style="color:var(--accent-text);font-size:11px;margin-top:10px">'
                f'{esc(T("ANALYTICS_COMPARE_WITH", 4, "Gorrak"))}</div>')
    cards = [report_head("Gorrak · " + T("MON_CLASS_BOSS")), card(T("ANALYTICS_PAGE"), first + second)]

    def shot(x, scroll):
        body = (f'<div class="page">{analytics_head(0)}<div style="position:absolute;left:0;right:0;top:44px;bottom:0;'
                f'overflow:hidden"><div class="column" style="margin-top:-{scroll}px">{"".join(cards)}</div></div></div>')
        return window(theme, "reports", body, x, TOP, module="idle", reports=True)

    return shot(LEFT, 90) + shot(RIGHT, 390)


ANALYTICS_KINDS = [
    ("analytics-overview", analytics_overview, ["nebula"],
     "The Analytics page: the enemies, and a comparison in a narrow window with the last columns left out",
     "La pagina Analytics: i nemici, e un confronto in una finestra stretta con le ultime colonne fuori"),
    ("analytics-compare", analytics_compare, THEMES,
     "A comparison of fights: the All fights row, Insufficient data and Not comparable",
     "Un confronto di scontri: la riga Tutti gli scontri, Dati insufficienti e Non confrontabile"),
    ("report-analytics", report_analytics, ["nebula"],
     "The report's Analytics card, with the unstable intervals and the link to the comparison",
     "La card Analytics del report, con gli intervalli instabili e il collegamento al confronto"),
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
    for _kind, _fn, _themes, _en, _it in MONITOR_KINDS + COACH_KINDS + REPORT_KINDS + REPLAY_KINDS + ANALYTICS_KINDS:
        for _theme in _themes:
            _name = f"{_kind}-{_theme}" + ("-it" if _lang == "itIT" else "")
            _caption = f"{_en if _lang == 'enUS' else _it} ({THEME_NAMES[_theme]})"
            SCENES.append((_name, _caption, (lambda f=_fn, t=_theme: f(t)), _lang, _theme))
