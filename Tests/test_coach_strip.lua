-- UI/CoachStrip.lua and the border effect of UI/Window.lua (SPEC-04 §3.1–§3.2, §6 M3.4; ui-style 3.1, 3.4, 4.2): where
-- the strip is, what it says in every situation (idle, tip, an alert for 4 s then the tip, severity, mute, demo, switches
-- off), the tooltip with reason, category and confidence, the confidence pill only for estimated and predicted, the low
-- window, the border once per alert with and without animations, the pill's icon without the window message, the texts
-- in both languages. Fight scripts over the mock client (Tests/lib/fight.lua).

before_boot(function(M) M.features = { monitor = true, alerts = true, coach = true } end)

local function CS() return Mock.ns.CoachStrip end
local function V() return Mock.ns.ThreatList.view end
local function S() return V().strip end
local function W() return Mock.ns.Window end
local function L() return Mock.ns.L end
local function Tip() return Mock.ns.Widgets.Tooltip end
local function bus() return Mock.ns.Bus end

local function set(path, value) truthy(Mock.ns.Config:Set(path, value)) end

local function hover()
	Mock.RunScript(S(), "OnEnter")
	local text = table.concat(Tip().Lines(), "\n")
	Mock.RunScript(S(), "OnLeave")
	return text
end

local function dpsPull(me, rogue, outcome)
	local pull = Fight.new{
		player = { class = "MAGE", role = "DAMAGER", ranged = true },
		party = {
			{ key = "tank", role = "TANK", name = "Bram" },
			{ key = "healer", class = "PRIEST", role = "HEALER", name = "Sela" },
			{ key = "rogue", class = "ROGUE", role = "DAMAGER", name = "Kor" },
		},
		mobs = { { key = "boss", tokens = { "target", "boss1" }, classification = "worldboss", name = "Gorrak" } },
	}
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "tank", 1000)
		:threat("boss", "player", { raw = 500, scaled = me or 40 })
		:threat("boss", "rogue", { raw = 300, scaled = rogue or 20 })
	return pull
end

-- A made-up alert, as Data/Alerts.lua emits it (the strip copies what it needs).
local function raise(over)
	local alert = { kind = "danger", severity = 2, state = "DANGER", reason = nil, subject = "self", unitKey = "u",
		otherKey = false, mobKey = "m", message = "ALERT_DANGER", args = { 97 }, category = "detected",
		confidence = "high", at = Mock.ns.Compat.Now(), muted = false, demo = false, window = true, visual = true,
		sound = false }
	for k, v in pairs(over or {}) do alert[k] = v end
	bus().Emit("ALERT_RAISED", alert)
	return alert
end

local function warning(over)
	local alert = { kind = "warning", severity = 1, state = "WARNING", message = "ALERT_WARNING", args = { 82 } }
	for k, v in pairs(over or {}) do alert[k] = v end
	return raise(alert)
end

describe("where the strip is", function()
	it("sits between the header and the list header, 18 pt high, as wide as the content", function()
		truthy(S():IsShown())
		eq(S():GetHeight(), 18)
		local point, rel = S():GetPoint(1)
		eq(point, "TOPLEFT") eq(rel, V().header)
		local _, above = V().listHead:GetPoint(1)
		eq(above, S())
	end)

	it("is there for the Coach or the window message of the alerts, else the list takes the room", function()
		set("account.settings.coach.enabled", false)
		truthy(S():IsShown(), "the alerts keep it")
		set("account.settings.alerts.window", false)
		falsy(S():IsShown())
		local _, above = V().listHead:GetPoint(1)
		eq(above, V().header)
		set("account.settings.coach.enabled", true)
		truthy(S():IsShown(), "the Coach brings it back")
		set("account.settings.coach.enabled", false)
		set("account.settings.alerts.window", true)
		set("account.settings.alerts.enabled", false)
		falsy(S():IsShown())
	end)

end)

describe("with both switches off (ADR 0014)", function()
	before_boot(function(M) M.features = { monitor = true, alerts = false, coach = false } end)

	it("has no strip, whatever happens", function()
		falsy(S():IsShown())
		falsy(CS().Present())
		local pull = dpsPull(97)
		pull:to(2)
		falsy(S():IsShown())
		falsy(W().frame.flash:IsShown(), "no alert is emitted, so no effect")
	end)
end)

describe("a low window", function()
	it("keeps the strip and drops the list header in a window with fewer than two rows", function()
		local pull = dpsPull(40)
		pull:to(2)
		V():Layout(300, 190)
		truthy(V().listHead:IsShown())
		V():Layout(300, 110)
		truthy(S():IsShown())
		falsy(V().listHead:IsShown())
		local _, above = V().list:GetPoint(1)
		eq(above, S())
		V():Layout(300, 300)
		truthy(V().listHead:IsShown())
	end)
end)

describe("what the strip says", function()
	it("waits for combat in text-3, and is empty in combat without a tip", function()
		eq(S().kind, "idle")
		eq(S().text:GetText(), "Advice appears during combat")
		falsy(S().stripe:IsShown())
		isNil(S():TooltipLines())
		local pull = Fight.new{ mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start():threat("boss", "player", 100)
		pull:to(2)
		eq(S().kind, "empty", "alone with the mob: nothing to advise")
		eq(S().text:GetText(), "")
		pull:stop()
		eq(S().kind, "idle")
	end)

	it("has no idle line with the Coach off", function()
		set("account.settings.coach.enabled", false)
		eq(S().kind, "empty")
		eq(S().text:GetText(), "")
	end)

	it("shows the tip with the coach icon, the accent stripe and its reason in the tooltip", function()
		local pull = dpsPull(40)
		pull:to(3)
		eq(S().kind, "tip")
		eq(S().text:GetText(), L().COACH_SAFE)
		truthy(S().coachIcon:IsShown())
		truthy(S().stripe:IsShown())
		falsy(S().badge:IsShown())
		eq(S().pill.label:GetText(), "HIGH", "an estimated tip says its confidence")
		truthy(S().pill:IsShown())
		falsy(S().predictIcon:IsShown())
		local tip = hover()
		contains(tip, L().COACH_SAFE)
		contains(tip, "Why: Your threat is 40 %")
		contains(tip, "Basis: estimated, high confidence")
		contains(tip, "Advice")
		matches(tip, "Shown %d+ s ago")
	end)

	it("shows no pill for a detected tip", function()
		local pull = dpsPull(85)
		pull:to(7)   -- the Warning alert of the entry has left the strip
		eq(S().text:GetText(), L().COACH_WARNING)
		falsy(S().pill:IsShown())
		contains(hover(), "Basis: detected, high confidence")
	end)

	it("shows the predict icon and the confidence of a predicted tip", function()
		bus().Emit("COACH_TIP", nil)
		local pull = dpsPull(40)
		local t = 0.2
		while t <= 4 do
			pull:at(t):threat("boss", "player", { raw = 500, scaled = 40 + t * 8 })
			t = t + 0.2
		end
		local seen = false
		for second = 1, 40 do
			pull:to(second / 10)
			if S().kind == "tip" and S().tip.category == "predicted" then seen = true break end
		end
		truthy(seen, "D3 was shown")
		truthy(S().predictIcon:IsShown())
		truthy(S().pill:IsShown())
		contains(hover(), "Basis: predicted")
	end)

	it("says Not enough data for advice with its reason, and no category", function()
		local pull = dpsPull(40, 20, "none")
		pull:to(2)
		eq(S().kind, "tip")
		eq(S().text:GetText(), "Not enough data for advice")
		local tip = hover()
		contains(tip, "Why: ")
		falsy(tip:find("Basis", 1, true))
	end)
end)

describe("an alert in the strip", function()
	it("takes the strip for 4 s with the state badge, then the tip comes back", function()
		local pull = dpsPull(40)
		pull:to(2)
		raise()
		eq(S().kind, "alert")
		eq(S().badge:GetState(), "danger")
		truthy(S().badge:IsShown())
		eq(S().badge.label:GetText(), "DANGER", "icon and word, never a colour alone")
		truthy(S().stripe:IsShown())
		falsy(S().coachIcon:IsShown())
		eq(S().text:GetText(), "Threat 97 %: very close to taking aggro")
		local tip = hover()
		contains(tip, "Why: Your threat passed the Danger threshold (95 %).")
		contains(tip, "Basis: detected, high confidence")
		contains(tip, "Alert")
		pull:to(5.5)
		eq(S().kind, "alert", "still within 4 s")
		pull:to(6.5)
		eq(S().kind, "tip")
		eq(S().text:GetText(), L().COACH_SAFE)
	end)

	it("is replaced by one of the same or a higher severity, not covered by a lower one", function()
		local pull = dpsPull(40)
		pull:to(1)
		raise()
		warning()
		eq(S().text:GetText(), "Threat 97 %: very close to taking aggro")
		pull:to(4)
		raise({ severity = 3, message = "ALERT_AGGRO", args = {} })
		eq(S().text:GetText(), "You have aggro")
		pull:to(6)
		eq(S().kind, "alert", "the 4 s start again")
		raise({ severity = 3, message = "ALERT_PET", args = {} })
		eq(S().text:GetText(), "Your pet has the mob")
		pull:to(9.5)
		eq(S().kind, "alert")
		pull:to(10.5)
		eq(S().kind, "tip")
	end)

	it("names the other unit as the list does and explains it", function()
		local pull = dpsPull(40)
		pull:to(1)
		local key = Mock.ns.ThreatModel.RowOf("party3").record.unitKey
		raise({ kind = "other", message = "ALERT_OTHER_DANGER", otherKey = key, args = {} })
		eq(S().text:GetText(), "Kor is very close to taking aggro")
		contains(hover(), "Why: Their threat passed the Danger threshold (95 %).")
		raise({ kind = "lost", severity = 3, message = "ALERT_LOST", otherKey = key, args = {} })
		contains(hover(), "Why: Kor is at the top of its threat list. The cause is not known.")
	end)

	it("has a reason for every message", function()
		for _, key in ipairs(Mock.ns.Alerts.MESSAGES) do
			local reason = Mock.ns.Alerts.REASONS[key]
			notNil(reason, key)
			notNil(L()[reason], reason)
			local message, why = Mock.ns.Alerts.Text({ message = key, args = { 90 }, otherKey = key:find("OTHER")
				or key == "ALERT_LOST" or key == "ALERT_MARGIN_DANGER" or key == "ALERT_MARGIN_WARNING",
				confidence = "medium" })
			truthy(message and #message > 0 and why and #why > 0, key)
			falsy(why:find("%", 1, true) and why:find("%[sd]"), key)
		end
	end)

	it("says the confidence of a predicted alert, with the pill", function()
		local pull = dpsPull(40)
		pull:to(1)
		warning({ message = "ALERT_WARNING_PREDICTED", args = { 4 }, category = "predicted", confidence = "medium" })
		truthy(S().predictIcon:IsShown())
		eq(S().pill.label:GetText(), "MEDIUM")
		contains(hover(), "Basis: predicted, medium confidence")
	end)

	it("comes from the real alerts of a fight, with the window channel", function()
		local pull = dpsPull(97)
		pull:to(1)
		eq(S().kind, "alert")
		eq(S().text:GetText(), "Threat 97 %: very close to taking aggro")
	end)

	it("is not taken without the window channel", function()
		set("account.settings.alerts.window", false)
		local pull = dpsPull(40)
		pull:to(1)
		raise({ window = false })
		eq(S().kind, "tip")
	end)

	it("is not kept while the window cannot show it", function()
		local pull = dpsPull(40)
		pull:to(1)
		W():Close()
		raise()
		W():Open()
		eq(S().kind, "tip")
	end)

	it("drops the held alert when the window message is turned off", function()
		local pull = dpsPull(40)
		pull:to(1)
		raise()
		set("account.settings.alerts.window", false)
		eq(S().kind, "tip")
	end)

	it("changes nothing in the settings of a read-only strip and never prints", function()
		local pull = dpsPull(40)
		pull:to(1)
		local printed = #Mock.output
		raise()
		pull:to(6)
		eq(#Mock.output, printed)
		eq(#Mock.errors, 0)
	end)
end)

describe("the mute", function()
	it("says Alerts muted for 2 s and keeps the mute icon", function()
		local pull = dpsPull(40)
		pull:to(1)
		Mock.ns.Alerts.ToggleMute()
		eq(S().kind, "note")
		eq(S().text:GetText(), "Alerts muted")
		truthy(S().muteIcon:IsShown())
		pull:to(3.5)
		eq(S().kind, "tip")
		truthy(S().muteIcon:IsShown())
		contains(hover(), "Alerts muted until the end of this fight")
		Mock.ns.Alerts.ToggleMute()
		eq(S().text:GetText(), "Alerts back on")
		falsy(S().muteIcon:IsShown())
		pull:to(6)
		eq(S().kind, "tip")
	end)

	it("says until the next fight out of combat", function()
		Mock.ns.Alerts.ToggleMute()
		contains(hover(), "Alerts muted until the end of the next fight")
	end)
end)

describe("the demo", function()
	it("says in the tooltip that the values are invented", function()
		truthy(Mock.ns.Demo.Start())
		Mock.Advance(2)
		raise({ demo = true })
		contains(hover(), L().MON_DEMO_TIP)
		Mock.ns.Demo.Stop()
		eq(S().kind, "idle")
	end)
end)

describe("the border (SPEC-04 §3.2)", function()
	local function flash() return W().frame.flash end

	it("takes the colour of the state once, holds 1.5 s and goes", function()
		set("account.settings.animations", false)
		local pull = dpsPull(40)
		pull:to(1)
		raise()
		truthy(flash():IsShown())
		eq(flash():GetAlpha(), 1)
		truthy(flash().rings.compact:IsShown())
		local r, g, b = flash().rings.compact:GetVertexColor()
		local sr, sg, sb = Mock.ns.Theme.Color("state-danger")
		near(r, sr, 1e-6) near(g, sg, 1e-6) near(b, sb, 1e-6)
		isNil(W().frame.titles.compact.chip.alert, "the window shows the message: the pill is left alone")
		pull:to(2.3)
		truthy(flash():IsShown())
		pull:to(2.7)
		falsy(flash():IsShown())
	end)

	it("fades in, holds and fades out with the animations on", function()
		local pull = dpsPull(40)
		pull:to(1)
		warning()
		truthy(flash():IsShown())
		pull:to(2.7)
		truthy(flash():IsShown(), "120 ms in, 1.5 s held, 320 ms out")
		pull:to(3.3)
		falsy(flash():IsShown())
	end)

	it("starts again only for a more severe alert", function()
		set("account.settings.animations", false)
		local pull = dpsPull(40)
		pull:to(1)
		warning()
		pull:to(2)
		warning()
		pull:to(2.7)
		falsy(flash():IsShown(), "the second warning did not restart it")
		warning()
		pull:to(3.5)
		raise()
		pull:to(4.4)
		truthy(flash():IsShown(), "the danger restarted it")
		warning()
		eq(W().effect, 2)
		pull:to(5.2)
		falsy(flash():IsShown())
	end)

	it("does nothing without the visual channel or with the window closed", function()
		local pull = dpsPull(40)
		pull:to(1)
		raise({ visual = false })
		falsy(flash():IsShown())
		W():Close()
		raise()
		falsy(flash():IsShown())
		isNil(W().effect)
	end)

	it("ends when the window is closed", function()
		local pull = dpsPull(40)
		pull:to(1)
		raise()
		W():Close()
		isNil(W().effect)
		W():Open()
		falsy(flash():IsShown())
	end)

	it("shows the state's icon in the pill when the window message is off (never a colour alone)", function()
		set("account.settings.alerts.window", false)
		set("account.settings.animations", false)
		local pull = dpsPull(40)
		pull:to(1)
		raise({ window = false })
		for _, bar in pairs(W().frame.titles) do
			eq(bar.chip.alert, "danger")
			deepEq(bar.chip.icon._texCoord, { Mock.ns.Assets.IconCoords("state-danger") })
			eq(bar.chip.label:GetText(), "Live", "the module word stays")
		end
		pull:to(3)
		for _, bar in pairs(W().frame.titles) do
			isNil(bar.chip.alert)
			deepEq(bar.chip.icon._texCoord, { Mock.ns.Assets.IconCoords("check") })
		end
	end)

	it("follows the tab: the ring of the layout on screen", function()
		set("account.settings.animations", false)
		raise()
		W():SelectTab("settings")
		truthy(flash().rings.wide:IsShown())
		falsy(flash().rings.compact:IsShown())
	end)
end)

describe("the strip in Italian", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = true }
		M.player.locale = "itIT"
	end)

	it("writes the idle line, the alert and the tooltip in Italian", function()
		eq(S().text:GetText(), "I consigli compaiono in combattimento")
		local pull = dpsPull(40)
		pull:to(2)
		contains(hover(), "Perché: ")
		contains(hover(), "Consiglio")
		raise()
		eq(S().badge.label:GetText(), "PERICOLO")
		contains(hover(), "Avviso")
		contains(hover(), "soglia di Pericolo (95 %)")
		Mock.ns.Alerts.ToggleMute()
		eq(S().text:GetText(), "Avvisi silenziati")
	end)
end)
