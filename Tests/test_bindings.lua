-- Bindings.xml and the key of the quick mute (SPEC-04 §1.5, ARC-04, M3.5): the file the client loads by its name, the
-- one binding with no default key, the names it shows, and the global function that answers as /atw mute.

local function xml()
	local text = T.readFile("AzerothThreatwarden/Bindings.xml")
	notNil(text, "AzerothThreatwarden/Bindings.xml")
	return (text:gsub("<!%-%-.-%-%->", ""))
end

local function bindings()
	local out = {}
	for attributes, body in xml():gmatch("<Binding%s+(.-)>(.-)</Binding>") do
		local one = { body = body }
		for key, value in attributes:gmatch('(%w+)="(.-)"') do one[key] = value end
		out[#out + 1] = one
	end
	return out
end

-- What the key does: the body of the binding, run in the game's environment as the client runs it.
local function press()
	Mock.ClearOutput()
	local chunk = assert(loadstring(bindings()[1].body, "=Bindings.xml"))
	chunk()
	eq(#Mock.errors, 0)
	return Mock.PlainOutput()
end

describe("Bindings.xml", function()
	it("has one binding in the addons' category, with a header and no default key", function()
		local list = bindings()
		eq(#list, 1)
		eq(list[1].name, "AZEROTHTHREATWARDEN_MUTE")
		eq(list[1].header, "AZEROTHTHREATWARDEN")
		eq(list[1].category, "ADDONS")
		isNil(list[1].default)
		falsy(xml():find("default=", 1, true))
		matches(list[1].body, "^%s*AzerothThreatwarden_ToggleMute%(%)%s*$")
	end)

	it("is not listed in the TOC: the client loads it by its name", function()
		falsy(T.readFile("AzerothThreatwarden/AzerothThreatwarden.toc"):find("Bindings.xml", 1, true))
	end)

	it("calls a function the addon defines", function()
		eq(type(_G.AzerothThreatwarden_ToggleMute), "function")
	end)

	it("has the names the client shows, for its header and for the binding", function()
		eq(_G.BINDING_HEADER_AZEROTHTHREATWARDEN, "Azeroth Threatwarden")
		eq(_G.BINDING_NAME_AZEROTHTHREATWARDEN_MUTE, "Mute alerts")
	end)
end)

describe("the names in an Italian client", function()
	before_boot(function(M) M.player.locale = "itIT" end)

	it("are Italian, before and after the saved language is read", function()
		eq(_G.BINDING_NAME_AZEROTHTHREATWARDEN_MUTE, "Silenzia gli avvisi")
	end)
end)

describe("the names follow the client, not the chosen language", function()
	before_boot(function(M)
		M.saved = { AzerothThreatwardenDB = { schema = 3, settings = { language = "itIT" } } }
	end)

	it("stays English in an English client set to Italian", function()
		eq(AzerothThreatwarden.Locale.Active(), "itIT")
		eq(_G.BINDING_NAME_AZEROTHTHREATWARDEN_MUTE, "Mute alerts")
	end)
end)

describe("the key with the alerts switched off", function()
	before_boot(function(M) M.features = { alerts = false } end)

	it("says when the mute arrives and mutes nothing", function()
		contains(press(), "This arrives in v0.3.0.")
		falsy(Mock.ns.Alerts.IsMuted())
	end)
end)

describe("the key with the alerts on", function()
	before_boot(function(M) M.features = { monitor = true, alerts = true } end)

	it("mutes until the end of the next fight and unmutes, saying so in the player's chat", function()
		contains(press(), "Alerts muted until the end of the next fight.")
		truthy(Mock.ns.Alerts.IsMuted())
		contains(press(), "Alerts back on.")
		falsy(Mock.ns.Alerts.IsMuted())
	end)

	it("mutes until the end of this fight, and the fight ends it", function()
		Mock.combat.Enter()
		contains(press(), "Alerts muted until the end of this fight.")
		Mock.combat.Leave()
		falsy(Mock.ns.Alerts.IsMuted())
	end)

	it("answers when the alerts are off in Settings, and changes nothing", function()
		AzerothThreatwarden.Config:Set("account.settings.alerts.enabled", false)
		contains(press(), "Alerts are off in Settings.")
		falsy(Mock.ns.Alerts.IsMuted())
	end)

	it("posts nothing to others", function()
		local sent = 0
		SendChatMessage = function() sent = sent + 1 end
		press()
		eq(sent, 0)
	end)
end)
