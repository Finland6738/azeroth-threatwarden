-- UI/ExportBox.lua and the *Export* buttons (SPEC-06 §4.6, §6 M6.5; EXP-01, EXP-04, EXP-05, EXP-07; ui-style §3.6;
-- ADR 0001, 0013, 0014): the box read-only and selected, closed by Esc, the warning about names always there, the
-- selectors with *CSV only*, the names switch, the choices remembered until a /reload, the status line, a recording
-- deleted while the box is open, the buttons of the report and of the comparison, combat, Italian, the switches off.

local function features(extra)
	local on = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		replay = true, analytics = true, export = true }
	for k, v in pairs(extra or {}) do on[k] = v end
	return on
end

before_boot(function(M) M.features = features() end)

local function B() return Mock.ns.ExportBox end
local function E() return Mock.ns.Export end
local function S() return Mock.ns.Session end
local function St() return Mock.ns.Storage end
local function L() return Mock.ns.L end
local function W() return AzerothThreatwarden.Window end

local counter = 0

local function session(o)
	o = o or {}
	counter = counter + 1
	local s = S().New{ id = "xb-" .. counter, started = 1767225600 + counter * 100, group = "party", diff = 1,
		zone = "The Deadmines", rec = { hz = 2, warning = 80, danger = 95, mode = "values" } }
	S().AddUnit(s, { name = o.me or "Testchar", role = "DAMAGER", token = "player", me = true }, 0)
	S().AddUnit(s, { name = "Bram", role = "TANK", token = "party1" }, 0)
	S().AddMob(s, { name = "Gorrak", class = "elite", npc = 448 }, 0)
	for _, e in ipairs({ { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
		{ 0, "S", 1, 1, 0, "S", "-" }, { 400, "c" } }) do
		S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7])
	end
	for _, t in ipairs({ 50, 150, 250 }) do
		S().AddRow(s, t, 1, 1, 400, "0")
		S().AddRow(s, t, 1, 2, 1000, "3")
	end
	s.q.v[1], s.q.v[2] = 100, 100
	S().Join(s)
	s.state, s.ended, s.dur, s.fight = "complete", "combat", 400, 400
	truthy(St().Add(s))
	truthy(St().Closed(s, true))
	return s
end

local function frames() for _ = 1, 200 do Mock.Advance(0.05) end end

local function openBox(kind, subject)
	truthy(B().Open(kind or "fight", subject))
	frames()
	return B():Frame()
end

local function report(s)
	W():Open()
	truthy(W():SelectTab("reports"))
	local view = W():Frame().pages.reports.view
	view:Layout(900, 600)
	view:Select(s.id)
	frames()
	return view
end

local function comparison()
	W():Open()
	truthy(W():SelectTab("reports"))
	local view = W():Frame().pages.reports.view
	view:Layout(900, 600)
	view.segmented.buttons.analytics:Click()
	view.analyticsPage.rows[1]:Click()
	frames()
	return view, view.analyticsPage
end

local function hover(frame)
	Mock.RunScript(frame, "OnEnter")
	local text = table.concat(Mock.ns.Widgets.Tooltip.Lines(), "\n")
	Mock.RunScript(frame, "OnLeave")
	return text
end

describe("the box (SPEC-06 §4.6)", function()
	it("opens with the text selected, under the warning, with its size and the hint", function()
		local s = session()
		local f = openBox("fight", s.id)
		truthy(B():IsShown())
		contains(UISpecialFrames, "AzerothThreatwardenExport")
		eq(f:GetWidth(), 640)
		eq(f:GetHeight(), 460)
		eq(f.title:GetText(), "Export · This fight · Gorrak")
		eq(f.edit:GetText(), E().Display(B():GetText()))
		matches(B():GetText(), "^```\nThreatwarden · Gorrak · ")
		truthy(f.edit:HasFocus())
		truthy(f.edit._highlighted)
		truthy(f.warning:IsShown())
		eq(f.warning:GetText(), L().EXPORT_WARNING)
		truthy(f.warningIcon:IsShown())
		matches(f.status:GetText(), "^about %d+ KB$")
		eq(f.hint:GetText(), L().EXPORT_HINT)
		eq(f.contents:Active(), "fight")
		eq(f.formats:Active(), "text")
		eq(#Mock.output, 0)
		eq(#Mock.errors, 0)
	end)

	it("is read-only, selects all when it gets the keyboard and closes with Close or Esc, forgetting the text", function()
		local s = session()
		local f = openBox("fight", s.id)
		local shown = f.edit:GetText()
		Mock.TypeInto(f.edit, "typed")
		eq(f.edit:GetText(), shown)
		f.edit:ClearFocus()
		f.edit._highlighted = false
		f.edit:SetFocus()
		truthy(f.edit._highlighted)
		f.close:Click()
		falsy(B():IsShown())
		isNil(B():GetText())
		eq(f.edit:GetText(), "")
		openBox("fight", s.id)
		Mock.RunScript(f.edit, "OnEscapePressed")
		falsy(B():IsShown())
		eq(f.edit:GetText(), "")
	end)

	it("switches content and format, with CSV only for events and readings", function()
		local s = session()
		local f = openBox("fight", s.id)
		f.formats.buttons.csv:Click()
		frames()
		matches(B():GetText(), "^session,started_utc,zone,")
		f.formats.buttons.text:Click()
		frames()
		matches(B():GetText(), "^```")
		f.contents.buttons.events:Click()
		frames()
		matches(B():GetText(), "^t_s,event,")
		eq(f.formats:Active(), "csv")
		falsy(f.formats.buttons.text:IsEnabled())
		eq(hover(f.formats.buttons.text), L().EXPORT_CSV_ONLY)
		f.formats.buttons.text:Click()
		frames()
		matches(B():GetText(), "^t_s,event,")
		eq(f.title:GetText(), "Export · Events · Gorrak")
		f.contents.buttons.readings:Click()
		frames()
		matches(B():GetText(), "^t_s,enemy,unit,percent,")
		-- the format chosen comes back with a content that has it
		f.contents.buttons.fight:Click()
		frames()
		matches(B():GetText(), "^```")
		truthy(f.formats.buttons.text:IsEnabled())
		Mock.RunScript(f.formats.buttons.text, "OnEnter")
		falsy(Mock.ns.Widgets.Tooltip.IsShown(), "no tooltip on a segment that is on")
		eq(#Mock.errors, 0)
	end)

	it("replaces the names with the switch and remembers the choices until a /reload", function()
		local s = session()
		local f = openBox("fight", s.id)
		falsy(f.names:IsOn())
		contains(B():GetText(), "Bram")
		f.names:Click()
		frames()
		truthy(f.names:IsOn())
		eq(f.warning:GetText(), L().EXPORT_REPLACED)
		truthy(f.warning:IsShown())
		falsy(B():GetText():find("Bram", 1, true))
		falsy(B():GetText():find("Testchar", 1, true))
		contains(B():GetText(), "Player 1")
		f.formats.buttons.csv:Click()
		f.contents.buttons.readings:Click()
		frames()
		B():Hide()
		f = openBox("fight", s.id)
		eq(f.contents:Active(), "readings")
		truthy(f.names:IsOn())
		falsy(B():GetText():find("Bram", 1, true))
		Mock.Reload()
		isNil(Mock.ns.ExportBox.frame)
		eq(Mock.ns.ExportBox.content, "fight")
		eq(Mock.ns.ExportBox.format, "text")
		isNil(Mock.ns.ExportBox.replace)
	end)

	it("says Building export… while the text is built in slices, then puts it with one SetText", function()
		local s = session()
		E().SLICE = 1
		local f = B():Frame()
		local sets = 0
		local set = f.edit.SetText
		f.edit.SetText = function(self, text)
			if text ~= "" then sets = sets + 1 end
			return set(self, text)
		end
		B().content = "readings"
		B().Open("fight", s.id)
		eq(f.status:GetText(), L().EXPORT_BUILDING)
		eq(f.edit:GetText(), "")
		frames()
		matches(B():GetText(), "^t_s,")
		eq(sets, 1)
		-- a new choice drops the build running
		B().Open("fight", s.id)
		f.contents.buttons.events:Click()
		frames()
		matches(B():GetText(), "^t_s,event,")
	end)

	it("says outside the text what the limit left out", function()
		local s = session()
		E().MAX_TEXT = 100
		B().content = "readings"
		local f = openBox("fight", s.id)
		local info = B().info
		truthy(info.left > 1)
		contains(f.status:GetText(), info.left .. " rows left out (limit ")
		falsy(B():GetText():find("left out", 1, true))
		E().MAX_TEXT = 262144
		f.contents.buttons.events:Click()
		frames()
		falsy(f.status:GetText():find("left out", 1, true))
	end)

	it("doubles | in the field only", function()
		local s = session{ me = "Te|st" }
		B().content = "readings"
		local f = openBox("fight", s.id)
		contains(B():GetText(), "Te|st")
		contains(f.edit:GetText(), "Te||st")
	end)

	it("empties itself when the recording is deleted", function()
		local s, other = session(), session()
		local f = openBox("fight", s.id)
		truthy(St().Delete(other.id))
		frames()
		matches(B():GetText(), "^```")
		truthy(St().Delete(s.id))
		isNil(B():GetText())
		eq(f.edit:GetText(), "")
		eq(f.status:GetText(), "This recording was deleted.")
		truthy(B():IsShown())
		f.formats.buttons.csv:Click()
		frames()
		eq(f.edit:GetText(), "")
		eq(f.status:GetText(), "This recording was deleted.")
		eq(#Mock.errors, 0)
	end)

	it("works in combat", function()
		local s = session()
		Mock.combat.Enter()
		local f = openBox("fight", s.id)
		matches(B():GetText(), "^```")
		f.close:Click()
		eq(#Mock.errors, 0)
	end)

	it("opens nothing without a subject", function()
		falsy(B().Open("fight", nil))
		falsy(B().Open("compare", nil))
		falsy(B():IsShown())
	end)

	it("speaks Italian", function()
		boot(function(M) M.player.locale = "itIT" end)
		local s = session()
		local f = openBox("fight", s.id)
		eq(f.title:GetText(), "Esportazione · Questo scontro · Gorrak")
		eq(f.warning:GetText(), "Questo testo contiene i nomi del tuo gruppo. Condividilo solo con chi è d'accordo.")
		eq(f.close:GetLabel(), "Chiudi")
		matches(f.status:GetText(), "^circa ")
	end)
end)

describe("the Export buttons", function()
	it("of the report's head card open the box on that recording", function()
		local s = session()
		local view = report(s)
		truthy(view.head.export:IsShown())
		truthy(view.head.export:IsEnabled())
		eq(view.head.export:GetLabel(), L().EXPORT_BUTTON)
		eq(hover(view.head.export), L().EXPORT_BUTTON_TIP)
		view.head.export:Click()
		frames()
		truthy(B():IsShown())
		matches(B():GetText(), "^```\nThreatwarden · Gorrak")
		eq(#Mock.errors, 0)
	end)

	it("wrap onto a second line in a narrow card", function()
		local s = session()
		local view = report(s)
		view.head.buttons:Reflow(900)
		eq(view.head.buttons:GetHeight(), 32)
		view.head.buttons:Reflow(260)
		truthy(view.head.buttons:GetHeight() > 32)
		view:Layout(300, 600)
		eq(#Mock.errors, 0)
	end)

	it("stand beside Delete and Close without the replay", function()
		boot(function(M) M.features = features{ replay = false } end)
		local s = session()
		local view = report(s)
		isNil(view.head.replay)
		view.head.buttons:Reflow(900)
		eq(view.head.buttons:GetHeight(), 32)
		for _, button in ipairs({ view.head.delete, view.head.export, view.head.close }) do
			truthy(button:GetNumPoints() == 1 and button:IsShown())
		end
		local _, _, _, x = view.head.close:GetPoint(1)
		truthy(x > view.head.delete:GetWidth() + view.head.export:GetWidth(), "Close after Export: " .. x)
	end)

	it("of the report are off for a damaged recording, with the reason", function()
		local s = session()
		local view = report(s)
		view.problem = "damaged"
		view:Refresh()
		falsy(view.head.export:IsEnabled())
		eq(hover(view.head.export), L().REPORT_DAMAGED)
	end)

	it("of the comparison open the box on it, with only its content", function()
		session()
		session()
		local _, page = comparison()
		local button = page.compare.buttons.export
		truthy(page.compare.buttons:IsShown())
		truthy(button:IsShown())
		falsy(page.compare.buttons.refresh:IsShown())
		button:Click()
		frames()
		local f = B():Frame()
		eq(f.title:GetText(), "Export · Comparison · Gorrak")
		truthy(f.comparison:IsShown())
		falsy(f.contents:IsShown())
		matches(B():GetText(), "^```\nThreatwarden · Comparison · Gorrak")
		truthy(f.formats.buttons.text:IsEnabled())
		f.formats.buttons.csv:Click()
		frames()
		matches(B():GetText(), "^session,started_utc,enemy,group,")
		eq(f.warning:GetText(), L().EXPORT_WARNING)
		-- a new fight shows Refresh before it
		session()
		frames()
		truthy(page.compare.buttons.refresh:IsShown())
		truthy(button:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("empties the comparison's box when one of its recordings is deleted", function()
		local a = session()
		session()
		local _, page = comparison()
		page.compare.buttons.export:Click()
		frames()
		truthy(St().Delete(a.id))
		isNil(B():GetText())
		eq(B():Frame().status:GetText(), L().EXPORT_DELETED)
		eq(#Mock.errors, 0)
	end)

	it("hides without a comparison to export", function()
		session{}
		local _, page = comparison()
		page:Choose(false)
		frames()
		falsy(page.compare.buttons:IsShown())
	end)
end)

describe("the switches off (ADR 0014)", function()
	it("make no button, no frame and open nothing", function()
		for _, off in ipairs({ { export = false }, { analytics = false } }) do
			boot(function(M) M.features = features(off) end)
			local s = session()
			local view = report(s)
			isNil(view.head.export)
			isNil(view.head.buttons)
			if view.segmented then
				view.segmented.buttons.analytics:Click()
				view.analyticsPage.rows[1]:Click()
				frames()
				isNil(view.analyticsPage.compare.buttons.export)
				falsy(view.analyticsPage.compare.buttons:IsShown())
			end
			falsy(B().Open("fight", s.id))
			isNil(B().frame)
			isNil(AzerothThreatwardenExport)
			eq(#Mock.errors, 0)
		end
	end)
end)
