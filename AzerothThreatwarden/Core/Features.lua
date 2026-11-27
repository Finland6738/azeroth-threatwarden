-- Features: the switches that keep an unfinished part out of a release (ADR 0014, SPEC-01 §3.4). Lua 5.1.
-- Adapted from Azeroth Accord (Core/Features.lua), same owner, GPL-3.0 (ADR 0012).
-- While a switch is off nothing of the part is visible, it registers no game event and it writes no data; a command of
-- it answers that it arrives in a later version. Modules ask Features.On(name) when they act, never once at load.
-- Each switch is turned on by the release step of its milestone: `monitor` is on since v0.2.0, `alerts` and `coach`
-- since v0.3.0, `recording` and `reports` since v0.4.0, `timeline` and `replay` since v0.5.0,
-- `analytics` and `export` since v0.6.0, the others are off.
--
--   monitor          threat reading, threat list, states, demo      M2.R
--   alerts, coach    alerts; Threat Coach                            M3.R
--   recording        recording of fights                             M4.R
--   reports          combat report and the Reports tab               M4.R
--   timeline, replay threat timeline; replay                         M5.R
--   analytics, export metrics and comparison; text and CSV export    M6.R (the export needs analytics and reports)
--   multitarget      several mobs and dungeon focus (only if the probe allows it)   M7.R
--   profiles, heatmap role profiles; heatmap                         M8.R
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Features = {
	monitor = true,
	alerts = true,
	coach = true,
	recording = true,
	reports = true,
	timeline = true,
	replay = true,
	analytics = true,
	export = true,
	multitarget = false,
	profiles = false,
	heatmap = false,
}
ns.Features, ns.modules.Features = Features, Features

-- True while the switch `name` is on; false for a name without a switch.
function Features.On(name)
	return Features[name] == true
end

if ns.addon then ns.addon.Features = Features end
