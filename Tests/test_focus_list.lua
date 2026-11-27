-- UI/FocusList.lua (SPEC-07 §2.1-§2.4, §2.8; ui-style 3.7; ADR 0003): the pull bar and the list in every situation (the
-- four reaches, the three outcomes, All safe, +N more, unknown mobs with their reason, the demo), the order recomputed
-- at most once a second and at once on DANGER, the click that pins and closes, the rows that cannot be pinned, the pin
-- icon of the header, the tooltips with categories, age and source, both languages, nothing with the switch or the
-- setting off. Fight scripts: Tests/lib/fight.lua.

before_boot(function(M) M.features = { monitor = true, multitarget = true, recording = false } end)

local function FL() return Mock.ns.FocusList end
local function V() return Mock.ns.ThreatList.view end
local function F() return V().focus end
local function MT() return Mock.ns.MobTracker end
local function TT() return Mock.ns.TargetTracker end
local function L() return Mock.ns.L end
local function Config() return Mock.ns.Config end
local function Tip() return Mock.ns.Widgets.Tooltip end
local function keyOf(unit) return "mob:" .. Mock.units.Get(unit).guid end

local PARTY = {
	{ key = "tank", class = "WARRIOR", role = "TANK", name = "Bram" },
	{ key = "rogue", class = "ROGUE", role = "DAMAGER", name = "Kor" },
	{ key = "healer", class = "PRIEST", role = "HEALER", name = "Sela" },
}

local function newPull(mobs, def)
	def = def or {}
	return Fight.new{
		player = def.player or { class = "MAGE", role = "DAMAGER" },
		party = def.party or PARTY,
		mobs = mobs or {
			{ key = "boss", tokens = { "target" }, name = "Gorrak" },
			{ key = "loose", tokens = { "nameplate1" }, name = "Loose imp" },
			{ key = "close", tokens = { "nameplate2" }, name = "Close brute" },
			{ key = "calm", tokens = { "nameplate3" }, name = "Calm rat" },
		},
	}
end

-- The tank holds the boss and the calm one, the rogue holds the loose one and nears the close one.
local function standard(outcome)
	local pull = newPull()
	if outcome then pull:outcome(outcome) end
	pull:at(0):start()
		:threat("boss", "tank", 1000):threat("boss", "player", { raw = 300, scaled = 30 })
		:threat("loose", "rogue", 500):threat("loose", "tank", { raw = 100, scaled = 20 })
		:threat("close", "tank", 1000):threat("close", "rogue", { raw = 950, scaled = 95 })
		:threat("calm", "tank", 1000):threat("calm", "healer", { raw = 100, scaled = 8 })
	pull:to(4)
	return pull
end

-- Opens the list in a window tall enough for every mob of the small pulls.
local function open()
	truthy(FL().SetOpen(true))
	V():Layout(380, 320)
end

local function shownRows()
	local out = {}
	for _, w in ipairs(F().rows) do
		if w:IsShown() and w.key then out[#out + 1] = w end
	end
	return out
end

local function row(unit)
	local key = keyOf(unit)
	for _, w in ipairs(shownRows()) do if w.key == key then return w end end
end

local function names()
	local out = {}
	for _, w in ipairs(shownRows()) do out[#out + 1] = w.name:GetText() end
	return out
end

local function hover(frame)
	Mock.RunScript(frame, "OnEnter")
	return table.concat(Tip().Lines(), "\n")
end

local function text(fs) return fs:IsShown() and fs:GetText() or nil end
local function click(w) Mock.RunScript(w, "OnMouseUp", "LeftButton") end

describe("the pull bar", function()
	it("shows the count and the riskiest other mob, never the monitored one", function()
		standard()
		truthy(F().bar:IsShown())
		eq(F().barLabel:GetText(), "Pull · 4")
		eq(F().barBadge:GetState(), "danger")
		eq(F().barWord:GetText(), "On Kor", "a loose mob comes before one about to be pulled")
		contains(hover(F().bar), "Loose imp")
		contains(hover(F().bar), "It is on a unit that is not a tank.")
		eq(#Mock.errors, 0)
	end)

	it("says Close when a mob is about to be pulled", function()
		local pull = standard()
		pull:taunt("loose", "tank"):to(7)
		eq(F().barWord:GetText(), "Close")
	end)

	it("says No tank when no tank is on a mob's list", function()
		Mock.units.Add("stranger", { name = "Stranger" })
		local pull = newPull{ { key = "boss", tokens = { "target" } }, { key = "free", tokens = { "nameplate1" }, name = "Hound" } }
		pull:at(0):start():threat("boss", "tank", 100):threat("free", "stranger", 500)
			:threat("free", "healer", { raw = 50, scaled = 10 })
		pull:to(3)
		eq(F().barBadge:GetState(), "warning")
		eq(F().barWord:GetText(), "No tank")
		open()
		eq(row("free").holder:GetText(), "Stranger (not in the list)")
	end)

	it("says All safe when every other mob is safe", function()
		local pull = newPull{ { key = "boss", tokens = { "target" } }, { key = "calm", tokens = { "nameplate1" } } }
		pull:at(0):start():threat("boss", "tank", 1000):threat("calm", "tank", 1000)
		pull:to(3)
		eq(F().barBadge:GetState(), "safe")
		eq(F().barWord:GetText(), "All safe")
	end)

	it("never says All safe while some mob is unknown", function()
		local pull = newPull{ { key = "boss", tokens = { "target" } }, { key = "calm", tokens = { "nameplate1" } },
			{ key = "hidden", tokens = { "nameplate2" } } }
		pull:at(0):start():threat("boss", "tank", 1000):threat("calm", "tank", 1000):threat("hidden", "tank", 1000)
		pull:answer("UnitDetailedThreatSituation", nil, "nameplate2", Mock.threat.SECRET)
		pull:answer("UnitThreatSituation", nil, "nameplate2", Mock.threat.SECRET)
		pull:to(3)
		eq(F().barBadge:GetState(), "unknown")
		eq(F().barWord:GetText(), "All safe · 1 unknown")
	end)

	it("says why when the other mobs of a readable pull are all unknown", function()
		local pull = newPull{ { key = "boss", tokens = { "target" } }, { key = "far", tokens = { "nameplate1" } } }
		pull:at(0):start():threat("boss", "tank", 1000):threat("far", "tank", 1000)
		pull:to(3)
		eq(F().barWord:GetText(), "All safe")
		pull:token("nameplate1", nil):to(6)
		eq(F().barBadge:GetState(), "unknown")
		eq(F().barWord:GetText(), "No unit")
	end)

	it("says the reach, not All safe, when the other mobs' threat is secret", function()
		local pull = newPull{ { key = "boss", tokens = { "target" } }, { key = "hidden", tokens = { "nameplate1" } } }
		pull:at(0):start():threat("boss", "tank", 1000):threat("hidden", "tank", 1000)
		pull:answer("UnitDetailedThreatSituation", nil, "nameplate1", Mock.threat.SECRET)
		pull:answer("UnitThreatSituation", nil, "nameplate1", Mock.threat.SECRET)
		pull:to(3)
		eq(F().barWord:GetText(), "Only your target can be read here")
		contains(hover(F().bar), "The threat of the other mobs is secret.")
		open()
		local w = row("hidden")
		eq(w.why:GetText(), "Secret value")
		eq(w.percent:GetText(), "?")
	end)

	it("is absent with only the monitored mob when the reach has no reason", function()
		local pull = newPull{ { key = "boss", tokens = { "target", "nameplate1" } } }
		pull:at(0):start():threat("boss", "tank", 100)
		pull:to(3)
		falsy(F().bar:IsShown())
		falsy(FL().SetOpen(true))
		eq(#shownRows(), 0)
	end)

	it("says the reduced reach in a group, with the reason in the tooltip, and the footer in warn", function()
		local pull = newPull{ { key = "boss", tokens = { "target" } } }
		pull:at(0):start():threat("boss", "tank", 100)
		pull:to(3)
		truthy(F().bar:IsShown())
		eq(F().barLabel:GetText(), "Pull")
		eq(F().barWord:GetText(), "Only your target can be read here")
		eq(F().barWord.token, "text-3")
		contains(hover(F().bar), "Enemy nameplates are off")
		open()
		contains(V().quality:GetText(), "Reach: target only · 1 of 8")
		eq(V().quality.token, "warn")
	end)

	it("says focus and boss only when only those answer", function()
		truthy(Config():Set("account.settings.mobs.nameplates", false))
		local pull = newPull{ { key = "boss", tokens = { "target" } }, { key = "foc", tokens = { "focus" } } }
		pull:at(0):start():threat("boss", "tank", 100):threat("foc", "tank", 100)
		pull:to(3)
		eq(F().barWord:GetText(), "Focus and boss only")
	end)

	it("says that threat cannot be read when nothing answers", function()
		local pull = newPull{ { key = "boss", tokens = { "target" } } }
		pull:outcome("none")
		pull:at(0):start():threat("boss", "tank", 100)
		pull:to(3)
		eq(F().barWord:GetText(), "Threat cannot be read here")
	end)

	it("is not there alone out of a group with a reduced reach", function()
		local pull = newPull({ { key = "boss", tokens = { "target" } } }, { party = {} })
		pull:at(0):start():threat("boss", "player", 100)
		pull:to(3)
		falsy(F().bar:IsShown())
	end)

	it("goes at the end of the fight, and the open list with it", function()
		local pull = standard()
		open()
		truthy(F().list:IsShown())
		falsy(V().list:IsShown())
		pull:stop():to(5)
		falsy(F().bar:IsShown())
		falsy(F().list:IsShown())
		falsy(F().open)
		truthy(V().list:IsShown())
	end)

	it("opens the list in place of the threat list and closes it again", function()
		standard()
		click(F().bar)
		truthy(F().list:IsShown())
		falsy(V().list:IsShown())
		falsy(V().listHead:IsShown())
		click(F().bar)
		falsy(F().list:IsShown())
		truthy(V().list:IsShown())
		truthy(V().listHead:IsShown())
	end)
end)

describe("the list", function()
	it("orders the mobs by risk, rings the monitored one and shows holder, closest, percentage and margin", function()
		standard()
		open()
		deepEq(names(), { "Loose imp", "Close brute", "Gorrak", "Calm rat" })
		truthy(row("boss").ring:IsShown())
		falsy(row("loose").ring:IsShown())
		local loose, near = row("loose"), row("close")
		eq(loose.badge:GetState(), "danger")
		eq(loose.holderIcon.name, "state-warning", "a holder that is not a tank")
		eq(near.holderIcon.name, "tank")
		eq(near.percent:GetText(), "95 %")
		contains(near.closest:GetText(), "Kor")
		eq(near.margin:GetText(), "+5")
		eq(#Mock.errors, 0)
	end)

	it("shows the footer with the reach, the mobs followed and the age", function()
		standard()
		open()
		matches(V().quality:GetText(), "^Reach: all · 4 of 8 · %d+%.%d s ago$")
		eq(V().quality.token, "text-3")
	end)

	it("gives the categories, the source and the age in the tooltip, and the click it offers", function()
		standard()
		open()
		local tip = hover(row("close"))
		contains(tip, "Close brute")
		contains(tip, "State: DANGER (calculated)")
		contains(tip, "Someone is about to pull it.")
		contains(tip, "Held by: Bram (detected)")
		contains(tip, "Closest: Kor, 95 % (detected)")
		contains(tip, "Margin: +5 (calculated)")
		contains(tip, "Seen from: Nameplate")
		contains(tip, "Click to follow this mob")
		contains(hover(row("boss")), "Seen from: Your target")
		contains(hover(row("boss")), "This is the monitored mob")
	end)

	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("never gives a number to what it cannot read, in " .. outcome, function()
			standard(outcome)
			if outcome == "none" then
				eq(F().barWord:GetText(), "Threat cannot be read here")
			end
			open()
			for _, w in ipairs(shownRows()) do
				if outcome == "values" then
					matches(w.percent:GetText(), "^%d+ %%$")
				elseif outcome == "state" and w.badge:GetState() ~= "unknown" then
					eq(w.percent:GetText(), "—")
					falsy(w.margin:IsShown() and w.margin:GetText():match("%d"))
				else
					eq(w.badge:GetState(), "unknown")
					eq(w.percent:GetText(), "?")
					falsy(w.margin:IsShown())
					truthy(w.dashes[1]:IsShown())
					notNil(text(w.why))
					falsy(w.closest:IsShown())
					falsy(w.holder:IsShown())
				end
			end
			eq(#Mock.errors, 0)
		end)
	end

	it("says the reason of an unknown mob and its last values with their age only in the tooltip", function()
		local pull = standard()
		open()
		pull:token("nameplate2", nil):to(6.5)
		local w = row("close")
		eq(w.badge:GetState(), "unknown")
		eq(w.percent:GetText(), "?")
		eq(w.why:GetText(), "No unit")
		local tip = hover(w)
		contains(tip, "No unit names this mob now")
		contains(tip, "Last reading")
		contains(tip, "95 %")
		contains(tip, "Cannot be followed: no unit names it now")
		click(w)
		truthy(F().open, "the list stays when the mob cannot be followed")
		isNil(TT().Pinned())
	end)

	it("writes *Unknown mob* for a secret name", function()
		local pull = standard()
		local real = UnitName
		UnitName = function(unit)
			if unit == "nameplate1" then return Mock.Secret("string") end
			return real(unit)
		end
		pull:to(6)
		open()
		contains(table.concat(names(), "|"), "Unknown mob")
		UnitName = real
	end)

	it("sums up what does not fit as +N more", function()
		local mobs = { { key = "boss", tokens = { "target" } } }
		for i = 1, 11 do mobs[#mobs + 1] = { key = "m" .. i, tokens = { "nameplate" .. i } } end
		local pull = newPull(mobs)
		pull:at(0):start():threat("boss", "tank", 1000)
		for i = 1, 11 do pull:threat("m" .. i, "tank", 1000) end
		pull:to(10)
		open()
		V():Layout(284, 180)
		local shown = #shownRows()
		truthy(shown < 8)
		truthy(F().more:IsShown())
		eq(F().more:GetText(), "+" .. (8 - shown) .. " more")
	end)

	it("recomputes the order at most once a second, and at once when a mob enters DANGER", function()
		local pull = standard()
		open()
		local sorts = F().sorts
		for _ = 1, 4 do F():Draw() end
		eq(F().sorts, sorts)
		Mock.Advance(1.1)
		F():Draw()
		eq(F().sorts, sorts + 1)
		sorts = F().sorts
		-- a mob entering DANGER sorts at once
		pull:threat("calm", "healer", { raw = 990, scaled = 99 })
		MT().Tick()
		truthy(F().sorts > sorts)
		eq(names()[2] == "Calm rat" or names()[1] == "Calm rat" or names()[3] == "Calm rat", true)
	end)

	it("redraws only while visible", function()
		standard()
		Mock.ns.Window:SelectTab("settings")
		local writes = F().writes
		Mock.ns.Bus.Emit("MOBS_UPDATED")
		eq(F().writes, writes)
	end)
end)

describe("the pinned mob (SPEC-07 §2.4)", function()
	it("a click pins the mob, closes the list and puts the pin in the header; the icon releases it", function()
		standard()
		open()
		falsy(V().unpin:IsShown())
		click(row("close"))
		eq(TT().Pinned(), keyOf("close"))
		eq(TT().MobKey(), keyOf("close"))
		falsy(F().open)
		truthy(V().list:IsShown())
		truthy(V().unpin:IsShown())
		eq(V().mob:GetText(), "Close brute")
		contains(hover(V().unpin), "Pinned mob")
		V().unpin:Click()
		isNil(TT().Pinned())
		falsy(V().unpin:IsShown())
		eq(V().mob:GetText(), "Gorrak")
		eq(#Mock.errors, 0)
	end)

	it("a click on the pinned mob's row releases it", function()
		standard()
		open()
		click(row("close"))
		open()
		contains(hover(row("close")), "Followed by the monitor")
		click(row("close"))
		isNil(TT().Pinned())
		falsy(F().open)
	end)

	it("a click on the monitored row only closes the list", function()
		standard()
		open()
		click(row("boss"))
		isNil(TT().Pinned())
		falsy(F().open)
	end)

	it("never changes the game's target", function()
		standard()
		local target = UnitGUID("target")
		open()
		click(row("close"))
		eq(UnitGUID("target"), target)
	end)

	it("names who holds a pinned mob that no watched unit holds", function()
		Mock.units.Add("stranger", { name = "Stranger" })
		local pull = newPull{ { key = "boss", tokens = { "target" } }, { key = "free", tokens = { "nameplate1" }, name = "Hound" } }
		pull:at(0):start():threat("boss", "tank", 100):threat("free", "stranger", 500)
			:threat("free", "healer", { raw = 50, scaled = 10 })
		pull:target("free", "stranger"):to(3)
		open()
		click(row("free"))
		pull:to(4)
		eq(TT().HolderName(), "Stranger")
	end)

	it("cannot pin a mob without a stable identity, and says so", function()
		standard()
		open()
		local entry = MT().Get(keyOf("close"))
		falsy(TT().CanPin("tok:nameplate2:1"))
		truthy(TT().CanPin("mob:x"))
		truthy(TT().CanPin("tok:boss1:2"))
		truthy(TT().CanPin("tok:focus:2"))
		falsy(TT().CanPin("tgt:1"))
		local real = TT().CanPin
		TT().CanPin = function() return false end
		contains(table.concat(FL().RowTooltip(entry), "\n"), "Cannot be followed: no stable identity")
		TT().CanPin = real
	end)
end)

describe("the switch and the setting", function()
	it("show nothing with the switch off", function()
		boot(function(M) M.features = { monitor = true, multitarget = false, recording = false } end)
		standard()
		truthy(V():IsVisible())
		falsy(F().bar:IsShown())
		falsy(F().list:IsShown())
		falsy(V().unpin:IsShown())
		falsy(FL().SetOpen(true))
		truthy(V().list:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("show nothing with settings.mobs.enabled off, and close the open list", function()
		standard()
		open()
		truthy(Config():Set("account.settings.mobs.enabled", false))
		falsy(F().bar:IsShown())
		falsy(F().list:IsShown())
		truthy(V().list:IsShown())
	end)
end)

describe("a small window", function()
	it("keeps the state and the percentage, and the reason of an unknown mob", function()
		standard("none")
		open()
		Mock.ns.ThreatList.view:Layout(220, 140)
		local w = shownRows()[1]
		truthy(w.badge:IsShown())
		truthy(w.percent:IsShown())
		truthy(w.why:IsShown())
		eq(#Mock.errors, 0)
	end)
end)

describe("in Italian", function()
	before_boot(function(M)
		M.player.locale = "itIT"
		M.features = { monitor = true, multitarget = true, recording = false }
	end)

	it("writes the bar, the list and the tooltips in Italian", function()
		standard()
		eq(F().barWord:GetText(), "Su Kor")
		open()
		contains(V().quality:GetText(), "Portata: tutti")
		contains(hover(row("close")), "Clic per seguire questo mob")
		contains(hover(F().bar), "Clic per tornare all'elenco")
	end)
end)

describe("the demo", function()
	local function demo()
		Mock.ns.Window:Open()
		Mock.ns.Demo.Start()
		Mock.Advance(0.3)
	end

	it("shows the invented pull of five mobs beside the golem, reach all, and cannot pin", function()
		demo()
		truthy(F().bar:IsShown())
		eq(F().barLabel:GetText(), "Pull · 6")
		eq(F().barBadge:GetState(), "danger")
		open()
		eq(#shownRows() + (F().more:IsShown() and 1 or 0) > 0, true)
		local entries = {}
		local list, n = Mock.ns.MobTracker.List()
		eq(n, 6)
		for i = 1, n do entries[list[i].key] = list[i] end
		eq(entries["demo:mob4"].reason, "secret")
		eq(entries["demo:mob5"].reason, "no-token")
		contains(V().quality:GetText(), "DEMO")
		local w = shownRows()[1]
		contains(hover(w), "Demo: invented values")
		click(w)
		isNil(Mock.ns.TargetTracker.Pinned())
		truthy(F().open)
		eq(#Mock.errors, 0)
	end)

	it("puts the real tracker back at the end, with no list left", function()
		local real = Mock.ns.MobTracker
		demo()
		open()
		ne(Mock.ns.MobTracker, real)
		Mock.ns.Demo.Stop()
		eq(Mock.ns.MobTracker, real)
		falsy(F().bar:IsShown())
		falsy(F().open)
	end)

	it("leaves the tracker alone with the switch off", function()
		boot(function(M) M.features = { monitor = true, multitarget = false } end)
		local real = Mock.ns.MobTracker
		demo()
		eq(Mock.ns.MobTracker, real)
		falsy(F().bar:IsShown())
	end)
end)
