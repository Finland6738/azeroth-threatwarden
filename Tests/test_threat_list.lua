-- UI/ThreatList.lua (SPEC-03 §1.5–§1.6, §2.6, §3, §4.2; ui-style 3.2, 3.3) on fight scripts, over the three probe
-- outcomes: the rows (icon and word of the state always, class colour, role and tank icons, bar, number, trend), every
-- situation of the view (no target, target died or lost, out of combat, combat ended, empty, nothing readable), the
-- tooltips with their reasons, the four orders, "pin me on top", the stable order (MON-13), the places of a small
-- window ("+N more", the player's row always visible), bounded redraws and texts written only on a change, and the
-- texts in both languages.

before_boot(function(M) M.features = { monitor = true } end)

local function TL() return Mock.ns.ThreatList end
local function V() return TL().view end
local function L() return Mock.ns.L end
local function Tip() return Mock.ns.Widgets.Tooltip end

local function newPull(def)
	def = def or {}
	return Fight.new{
		player = def.player or { class = "MAGE", role = "DAMAGER", ranged = true },
		party = def.party or {
			{ key = "tank", role = "TANK", name = "Bram" },
			{ key = "healer", class = "PRIEST", role = "HEALER", name = "Sela" },
			{ key = "rogue", class = "ROGUE", role = "DAMAGER", name = "Kor" },
		},
		raid = def.raid,
		mobs = def.mobs or { { key = "boss", tokens = { "target" }, classification = "worldboss", name = "Gorrak" } },
	}
end

-- The tank holds the boss; the player, the rogue and the healer at fixed scaled percentages.
local function partyPull(me, rogue, outcome)
	local pull = newPull()
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "tank", 1000)
		:threat("boss", "player", { raw = 500, scaled = me or 40 })
		:threat("boss", "rogue", { raw = 300, scaled = rogue or 20 })
		:threat("boss", "healer", { raw = 100, scaled = 8 })
	return pull
end

-- The shown row widgets, top to bottom.
local function shownRows()
	local out = {}
	for _, w in ipairs(V().widgets) do
		if w:IsShown() and w.data then out[#out + 1] = w end
	end
	return out
end

local function tokens()
	local out = {}
	for _, w in ipairs(shownRows()) do out[#out + 1] = w.data.record.unitToken end
	return out
end

local function widget(token)
	for _, w in ipairs(shownRows()) do
		if w.data.record.unitToken == token then return w end
	end
end

local function hover(frame)
	Mock.RunScript(frame, "OnEnter")
	local lines = Tip().Lines()
	return table.concat(lines, "\n"), lines
end

local function text(fs) return fs:IsShown() and fs:GetText() or nil end

describe("the monitor tab", function()
	it("is the monitor with the switch on, the M1 text with it off", function()
		truthy(V():IsVisible())
		local page = Mock.ns.Window.frame.pages.monitor
		falsy(page.text:IsShown())
		falsy(page.logo:IsShown())
		boot(function(M) M.features = {} end)
		isNil(TL().view)
		local old = Mock.ns.Window.frame.pages.monitor
		truthy(old.text:IsShown())
		eq(old.text:GetText(), "Threat monitoring arrives in v0.2.0")
	end)

	it("says No target and asks for one", function()
		eq(V().situation, "none")
		eq(text(V().mob), "No target")
		eq(text(V().message), "Target an enemy to see its threat")
		eq(#shownRows(), 0)
		eq(text(V().quality), "")
		falsy(V().listHead:IsShown())
	end)

	it("shows the mob out of combat as Not in combat, with its classification", function()
		newPull()
		Mock.Fire("PLAYER_TARGET_CHANGED")
		eq(V().situation, "idle")
		eq(text(V().mob), "Gorrak")
		eq(text(V().class), "Boss")
		eq(text(V().message), "Not in combat")
		eq(text(V().quality), "Not in combat")
		falsy(V().badge:IsShown())
	end)

	it("says Unknown mob when the name is secret", function()
		local pull = partyPull()
		pull:secrets{ identity = true }
		pull:to(1)
		eq(text(V().mob), "Unknown mob")
	end)
end)

describe("the rows (values)", function()
	it("show one row per unit on the list, holder first, with icon, word, bar and number", function()
		partyPull(84, 97):to(1)
		eq(V().situation, "list")
		deepEq(tokens(), { "party1", "party3", "player", "party2" })
		local me = widget("player")
		eq(me.badge:GetState(), "warning")
		eq(me.badge.label:GetText(), "WARNING")
		notNil(me.badge.icon:GetTexture())
		eq(me.stripe:GetState(), "warning")
		eq(me.bar:GetPercent(), 84)
		eq(me.bar.number:GetText(), "84 %")
		eq(widget("party3").badge.label:GetText(), "DANGER")
		eq(widget("party1").badge.label:GetText(), "DANGER", "the tank, on its margin of 3")
		truthy(me.ring:IsShown(), "the player's row has the accent ring")
		falsy(widget("party3").ring:IsShown())
		truthy(widget("party1").tank:IsShown(), "the holder has the tank icon")
		falsy(me.tank:IsShown())
		eq(me.role.name, "role-dps")
		eq(widget("party1").role.name, "role-tank")
		eq(widget("party2").role.name, "role-healer")
		eq(widget("party1").name:GetText(), "Bram")
	end)

	it("paint the name in the class colour of the game", function()
		C_ClassColor = { GetClassColor = function(class)
			if class == "ROGUE" then return { r = 1, g = 0.96, b = 0.41 } end
		end }
		partyPull():to(1)
		local r, g, b = widget("party3").name:GetTextColor()
		near(r, 1, 1e-6) near(g, 0.96, 1e-6) near(b, 0.41, 1e-6)
		local r1, g1 = widget("party1").name:GetTextColor()
		local tr, tg = Mock.ns.Theme.Color("text-1")
		near(r1, tr, 1e-6, "an unknown colour is text-1") near(g1, tg, 1e-6)
	end)

	it("ask the game for the colour of a class once, however often the rows change places (ARC-06)", function()
		local asked = {}
		C_ClassColor = { GetClassColor = function(class)
			asked[class] = (asked[class] or 0) + 1
			return { r = 1, g = 0.5, b = 0 }
		end }
		local pull = partyPull(50, 70)
		pull:to(1)
		local places = {}
		for second = 2, 8 do   -- the player and the rogue swap places again and again
			pull:threat("boss", "player", { scaled = second % 2 == 0 and 78 or 30 })
			pull:to(second + 0.5)
			places[tokens()[2]] = true
		end
		truthy(places.player and places.party3, "both were second in turn")
		eq(asked.ROGUE, 1)
		eq(asked.MAGE, 1)
		for class, n in pairs(asked) do eq(n, 1, class) end
		near((widget("party3").name:GetTextColor()), 1, 1e-6)
	end)

	it("name an unreadable unit after its token, never empty", function()
		local pull = partyPull()
		pull:secrets{ identity = true }
		pull:to(1)
		eq(widget("party1").name:GetText(), "Party 1")
		eq(widget("player").name:GetText(), "Testchar", "the player's own name is readable")
	end)

	it("show the header: own state, the tank and the margin", function()
		partyPull(84, 20):to(1)
		eq(V().badge:GetState(), "warning")
		eq(text(V().tank), "Tank: Bram")
		eq(text(V().margin), "Margin +16")
		truthy(V().tankIcon:IsShown())
		falsy(V().notice:IsShown())
	end)

	it("say when the player is not on the list, without a badge", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "tank", 1000)
		pull:to(1)
		falsy(V().badge:IsShown())
		eq(text(V().notice), "You are not on its threat list")
		falsy(V().margin:IsShown())
	end)

	it("show the tank's margin over the second in the tank's own view", function()
		local pull = newPull{ player = { class = "WARRIOR", role = "TANK" },
			party = { { key = "rogue", class = "ROGUE", role = "DAMAGER", name = "Kor" } } }
		pull:at(0):start():threat("boss", "player", 1000):threat("boss", "rogue", { raw = 700, scaled = 70 })
		pull:to(1)
		eq(text(V().margin), "Margin +30")
		eq(V().badge:GetState(), "safe")
	end)

	it("name an unwatched holder, or say Unknown tank", function()
		local pull = partyPull()
		Mock.units.Add("stranger", { name = "Vel" })
		pull:at(0.5):threat("boss", "stranger", 5000):aggro("boss", "stranger"):target("boss", "stranger")
		pull:to(1)
		eq(text(V().tank), "Tank: Vel (not in the list)")
		contains(hover(V().header), "Held by a unit that is not in the list")
	end)

	it("show an arrow for the trend and the predicted time in its place", function()
		local pull = partyPull(40)
		for i = 1, 20 do pull:at(i * 0.2):threat("boss", "player", { raw = 500 + i * 20, scaled = 40 + i * 2 }) end
		pull:to(3.5)
		local me = widget("player")
		truthy(me.time:IsShown(), "predicted")
		contains(me.time:GetText(), "~")
		falsy(me.trend:IsShown())
		truthy(me.bar.predict:IsShown())
		local tip = hover(me)
		contains(tip, "May take aggro in about")
		contains(tip, "(predicted)")
		contains(tip, "(estimated)")
		falsy(widget("party1").trend:IsShown(), "no arrow for the holder")
		truthy(widget("party3").trend:IsShown())
		eq(widget("party3").trend.name, "trend-flat")
	end)
end)

describe("no state by colour alone, every unknown with its reason", function()
	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("has icon and word on every badge, outcome " .. outcome, function()
			partyPull(84, 97, outcome):to(1)
			local badges = {}
			for _, w in ipairs(shownRows()) do badges[#badges + 1] = w.badge end
			if V().badge:IsShown() then badges[#badges + 1] = V().badge end
			truthy(#badges >= 1)
			for _, badge in ipairs(badges) do
				truthy(badge.icon:IsShown())
				notNil(badge.icon:GetTexture())
				local word = badge.label:GetText()
				truthy(word == "SAFE" or word == "WARNING" or word == "DANGER" or word == "UNKNOWN", word)
			end
		end)
	end

	it("state only: no bar, a dash, the reason in the tooltip", function()
		partyPull(84, 97, "state"):to(1)
		eq(V().situation, "list")
		local me = widget("player")
		falsy(me.bar:IsShown())
		eq(me.dash:GetText(), "—")
		falsy(me.trend:IsShown())
		local tip = hover(me)
		contains(tip, "State only: the client hides threat values here")
		contains(tip, "From the game's threat state")
		contains(tip, "(detected)")
		contains(text(V().quality), "State only · ")
		falsy(tip:find("84 %", 1, true))
	end)

	it("nothing readable: one line, not a row per member, header UNKNOWN with the reason", function()
		partyPull(84, 97, "none"):to(1)
		eq(V().situation, "unavailable")
		eq(#shownRows(), 0)
		eq(text(V().message), "Threat data unavailable")
		eq(text(V().reason), "Secret value")
		eq(V().badge:GetState(), "unknown")
		eq(V().badge.label:GetText(), "UNKNOWN")
		eq(text(V().tank), "Unknown tank")
		contains(hover(V().header), "Nothing readable says who holds it")
		contains(text(V().quality), "0 % valid")
		eq(V().quality.token, "warn")
	end)

	it("an unreadable unit among readable ones: dashed bar, ?, reason", function()
		local pull = partyPull(84, 40)
		pull:secrets{ values = function(unit) return unit == "party3" end,
			state = function(unit) return unit == "party3" end }
		pull:to(1)
		local w = widget("party3")
		eq(w.badge.label:GetText(), "UNKNOWN")
		eq(w.bar.number:GetText(), "?")
		eq(w.bar:GetState(), "unknown")
		truthy(w.bar.dashes[1]:IsShown())
		local tip = hover(w)
		contains(tip, "Secret value")
		contains(tip, "Scaled threat: Secret value")
		eq(tokens()[#tokens()], "party3", "unknown rows come last")
	end)

	it("a row's tooltip lists every value with its category or its reason", function()
		partyPull(84, 20):to(1)
		local tip = hover(widget("player"))
		contains(tip, "State: WARNING (calculated)")
		contains(tip, "Scaled threat: 84 % (detected)")
		contains(tip, "Margin: +16 (calculated)")
		contains(tip, "Trend: ~+0.0 %/s")
		contains(tip, "(estimated)")
		contains(tip, "Time to overtake: Not rising")
		contains(tip, "Last read")
		contains(tip, "Mode: Live")
		contains(hover(widget("party1")), "Lead over the next: ")
	end)

	it("keeps the open tooltip up to date", function()
		local pull = partyPull(40)
		pull:to(1)
		hover(widget("player"))
		pull:at(1.5):threat("boss", "player", { raw = 800, scaled = 70 })
		pull:to(2)
		contains(table.concat(Tip().Lines(), "\n"), "70 %")
	end)
end)

describe("the end of a fight and the end of a mob", function()
	it("keeps the last rows, stale, with Combat ended", function()
		local pull = partyPull(84)
		pull:to(1)
		Mock.combat.Leave()
		Mock.Advance(2)
		eq(V().situation, "ended")
		eq(text(V().mob), "Combat ended")
		eq(text(V().quality), "Not in combat")
		local w = widget("player")
		eq(w.badge:GetState(), "unknown")
		eq(w.bar.number:GetText(), "?")
		eq(w.trend.name, "stale")
		truthy(w.trend:IsShown())
		contains(hover(w), "Stale: last read")
		falsy(V().badge:IsShown())
	end)

	it("says Target died, then No target once deselected", function()
		local pull = partyPull()
		pull:at(1):die("boss")
		pull:to(2)
		eq(V().situation, "died")
		eq(text(V().mob), "Target died")
		eq(#shownRows(), 0)
		Mock.units.SetToken("target", nil)
		Mock.Fire("PLAYER_TARGET_CHANGED")
		eq(text(V().mob), "No target")
	end)

	it("says Target lost when the mob vanishes", function()
		local pull = partyPull()
		pull:at(1):vanish("boss")
		pull:to(2)
		eq(V().situation, "lost")
		eq(text(V().mob), "Target lost")
	end)

	it("says No one on its list at the start of a fight", function()
		local pull = newPull()
		pull:at(0):start()
		pull:to(1)
		eq(V().situation, "empty")
		eq(text(V().message), "No one is on its threat list yet")
	end)
end)

describe("the order (SPEC-03 §3)", function()
	local function four(outcome)
		local pull = partyPull(50, 70, outcome)
		pull:to(1)
		return pull
	end

	it("is by percentage by default, then the player's risk, absolute threat and change by choice", function()
		four()
		eq(TL().Sort(), "relative")
		deepEq(tokens(), { "party1", "party3", "player", "party2" })
		contains(V().sortButton.label:GetText(), "Percentage")
		TL().SetSort("absolute")
		deepEq(tokens(), { "party1", "player", "party3", "party2" })
		TL().SetSort("risk")
		deepEq(tokens(), { "party1", "party3", "player", "party2" })
	end)

	it("orders the risk before the percentage", function()
		local pull = partyPull(40, 75)
		for i = 1, 14 do pull:at(i * 0.2):threat("boss", "player", { raw = 500 + i, scaled = 40 + i * 2 }) end
		pull:to(3)
		eq(widget("player").badge:GetState(), "warning", "predicted")
		deepEq(tokens(), { "party1", "party3", "player", "party2" })
		TL().SetSort("risk")
		eq(tokens()[1], "player")
	end)

	it("orders by recent change", function()
		local pull = partyPull(40, 40)
		for i = 1, 15 do
			pull:at(i * 0.2):threat("boss", "rogue", { raw = 300 + i * 10, scaled = 40 + i })
		end
		pull:to(3.2)
		TL().SetSort("change")
		eq(tokens()[1], "party3")
	end)

	it("cycles with a click on the list header", function()
		four()
		local seen = {}
		for i = 1, 4 do
			Mock.RunScript(V().sortButton, "OnClick")
			seen[i] = TL().Sort()
		end
		deepEq(seen, { "absolute", "risk", "change", "relative" })
	end)

	it("says absolute threat needs the values when there are none", function()
		four("state")
		TL().SetSort("absolute")
		contains(hover(V().sortButton), "Needs threat values")
		eq(tokens()[1], "party1", "the default order is used")
	end)

	it("pins the player on top when asked, with a word that says so", function()
		four()
		eq(V().pinButton.label:GetText(), "Me on top: off")
		Mock.RunScript(V().pinButton, "OnClick")
		truthy(TL().PinSelf())
		eq(V().pinButton.label:GetText(), "Me on top: on")
		eq(tokens()[1], "player")
		TL().SetPinSelf(false)
		eq(tokens()[1], "party1")
	end)

	it("keeps ties in the roster order", function()
		partyPull(30, 30):to(1)
		local t = tokens()
		eq(t[2], "player")
		eq(t[3], "party3")
	end)

	it("orders at most once a second, and at once when a row enters DANGER (MON-13)", function()
		local pull = partyPull(40, 20)
		pull:to(1)
		local sorts = V().sorts
		pull:at(1.2):threat("boss", "rogue", { raw = 600, scaled = 60 })
		pull:to(1.3)
		deepEq(tokens(), { "party1", "player", "party3", "party2" }, "the values changed, the places have not yet")
		eq(widget("party3").bar:GetPercent(), 60)
		truthy(V().sorts - sorts <= 1)
		pull:to(2.5)
		deepEq(tokens(), { "party1", "party3", "player", "party2" })
		pull:at(2.6):threat("boss", "healer", { raw = 900, scaled = 98 })
		pull:to(2.75)
		eq(tokens()[2], "party2", "DANGER orders at once")
	end)
end)

describe("a small window (SPEC-03 §3, §4.2)", function()
	local function raidPull()
		local members = { { key = "m1", role = "TANK" } }
		for i = 2, 9 do members[i] = { key = "m" .. i, class = "ROGUE" } end
		local pull = newPull{ raid = true, party = members }
		pull:at(0):start():threat("boss", "m1", 1000)
		for i = 2, 9 do pull:threat("boss", "m" .. i, { raw = i * 50, scaled = 20 + i }) end
		pull:threat("boss", "player", { raw = 10, scaled = 1 })
		pull:to(1)
		return pull
	end

	it("shows what fits, then +N more, the player always visible", function()
		raidPull()
		local shown = shownRows()
		truthy(#shown >= 3 and #shown < 10, "fits " .. #shown)
		truthy(V().more:IsShown())
		eq(V().more:GetText(), "+" .. (10 - #shown) .. " more")
		eq(tokens()[#shown], "player")
	end)

	it("shows more rows when taller", function()
		raidPull()
		local before = #shownRows()
		V():Layout(300, 400)
		truthy(#shownRows() > before)
	end)

	it("drops the role icon, the trend and the track before the state's word when narrow", function()
		partyPull(84):to(1)
		V():Layout(220, 140)
		local w = shownRows()[1]
		falsy(w.role:IsShown())
		falsy(w.trend:IsShown())
		truthy(w.badge:IsShown())
		truthy(w.badge.label:GetText() ~= "")
		falsy(V().columns.track)
		V():Layout(600, 400)
		truthy(V().columns.showMargin)
		eq(widget("player").margin:GetText(), "+16")
	end)
end)

describe("bounded redraws", function()
	it("draws once per THREAT_UPDATED and nothing when nothing happens", function()
		local pull = partyPull()
		pull:to(1)
		local updates, redraws = 0, V().redraws
		Mock.ns.Bus.On("THREAT_UPDATED", function() updates = updates + 1 end)
		pull:to(3)
		truthy(updates > 0)
		eq(V().redraws - redraws, updates)
		Mock.combat.Leave()
		Mock.Advance(3)
		redraws = V().redraws
		Mock.Advance(10)
		eq(V().redraws, redraws, "no redraw out of combat")
	end)

	it("writes a text only when it changes", function()
		local pull = partyPull()
		pull:to(2)
		local writes, redraws = V().writes, V().redraws
		pull:to(4)
		truthy(V().redraws > redraws)
		eq(V().writes, writes, "same values, no text written")
	end)

	it("does not draw while hidden, and catches up when shown", function()
		local pull = partyPull()
		pull:to(1)
		Mock.ns.Window:SelectTab("settings")
		local redraws = V().redraws
		Mock.ns.ThreatModel.Update()
		Mock.ns.Bus.Emit("THREAT_UPDATED")
		eq(V().redraws, redraws)
		Mock.ns.Window:SelectTab("monitor")
		truthy(V().redraws > redraws)
	end)

	it("allocates next to nothing when nothing changes", function()
		local pull = partyPull()
		pull:to(1)
		Mock.ns.Scheduler.Stop("threat")
		Mock.ns.ThreatModel.Update()
		for _ = 1, 20 do V():Redraw() end
		-- the smallest growth of three batches (as test_scanner): the mock allocates for the mob's name once only
		local grown = math.huge
		for _ = 1, 3 do
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for _ = 1, 500 do V():Redraw() end
			grown = math.min(grown, collectgarbage("count") - before)
			collectgarbage("restart")
		end
		truthy(grown < 4, "grew by " .. grown .. " KB")
	end)

	it("raises no error through a whole fight in the three outcomes", function()
		for _, outcome in ipairs(Fight.OUTCOMES) do
			boot(function(M) M.features = { monitor = true } end)
			local pull = partyPull(84, 97, outcome)
			pull:to(3)
			Mock.combat.Leave()
			Mock.Advance(2)
		end
		eq(#Mock.errors, 0)
	end)
end)

describe("the texts in Italian", function()
	before_boot(function(M) M.features = { monitor = true } M.player.locale = "itIT" end)

	it("writes the view and the tooltips in Italian", function()
		partyPull(84, 97):to(1)
		eq(widget("player").badge.label:GetText(), "ATTENZIONE")
		eq(text(V().margin), "Margine +16")
		contains(V().sortButton.label:GetText(), "Ordine: Percentuale")
		contains(hover(widget("player")), "Threat scalata: 84 % (rilevato)")
		eq(#Mock.errors, 0)
	end)
end)

describe("nothing on screen without a locale key, with the monitor", function()
	local MARK, END = "\194\171", "\194\187"
	before_boot(function(M)
		M.features = { monitor = true }
		M.OnFilesLoaded(function()
			local strings = AzerothThreatwarden.Locale.Strings("enUS")
			for key, value in pairs(strings) do
				local holders = {}
				for p in value:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*[cdiouxXeEfgGqs]") do holders[#holders + 1] = " " .. p end
				strings[key] = MARK .. key .. table.concat(holders) .. END
			end
		end)
	end)

	-- units, mobs and plain values are not language
	local NAMES = { Gorrak = true, Bram = true, Sela = true, Kor = true, Testchar = true }

	local function check(root)
		local bad = {}
		local function walk(widget_)
			if widget_:IsShown() == false then return end
			if widget_:GetObjectType() == "FontString" and type(widget_:GetText()) == "string" then
				local rest = widget_:GetText():gsub(MARK, "{"):gsub(END, "}")
				local removed = 1
				while removed > 0 do rest, removed = rest:gsub("{[^{}]*}", "") end
				for name in pairs(NAMES) do rest = rest:gsub(name, "") end
				rest = rest:gsub("[%d%p%s]", "")
				if rest ~= "" and rest ~= "?" then bad[#bad + 1] = widget_:GetText() end
			end
			for _, child in ipairs({ widget_:GetChildren() }) do walk(child) end
			for _, region in ipairs({ widget_:GetRegions() }) do walk(region) end
		end
		walk(root)
		return bad
	end

	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("in the view and in the tooltips, outcome " .. outcome, function()
			partyPull(84, 97, outcome):to(1)
			deepEq(check(V()), {})
			local hovered = { V().header, V().sortButton }
			for _, w in ipairs(shownRows()) do hovered[#hovered + 1] = w end
			for _, frame in ipairs(hovered) do
				Mock.RunScript(frame, "OnEnter")
				if Tip().Frame() and Tip().IsShown() then deepEq(check(Tip().Frame()), {}) end
				Mock.RunScript(frame, "OnLeave")
			end
		end)
	end
end)
