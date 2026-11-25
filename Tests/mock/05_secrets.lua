-- Mock client, part 2: secret values and the predictions of C_Secrets (SPEC-01 §2 and ARC-11, SPEC-08 §1 P3).
--
-- Imitates: issecretvalue, issecrettable, canaccessvalue; C_Secrets.HasSecretRestrictions,
-- ShouldUnitThreatValuesBeSecret, ShouldUnitThreatStateBeSecret, ShouldUnitIdentityBeSecret,
-- ShouldUnitComparisonBeSecret, CanCompareUnitTokens.
-- Dump (../WoW-Addons/docs/api.json, build 70170): systems FrameScript (issecretvalue, issecrettable, canaccessvalue)
-- and SecretUtil (the C_Secrets functions, with `ShouldUnitThreatStateBeSecret(unit [, mobUnit])` and
-- `ShouldUnitThreatValuesBeSecret(unit, mobUnit)`).
--
-- A secret of the mock is **stricter than the client**: any operation on it raises an error ("secret value used: ..."),
-- because the addon must never compare, add, format, concatenate, print or save one (ARC-11), even where the client
-- would let tainted code do it. `type()` answers the type the secret stands for, as we expect the client to [verify P3],
-- so that a `type(v) == "number"` check does not hide a missing issecretvalue. Two things plain Lua cannot catch: `==`
-- against an ordinary value answers false silently, and a secret is "true" in a condition; the SavedVariables
-- serializer of the harness refuses a saved secret.
--
-- Configure (kept across Mock.Reload), each field a boolean or a function(unit, mob) -> boolean:
--   Mock.secrets.Set{ values = true }             threat values are secret (percentages, raw threat)
--   Mock.secrets.Set{ state = true }              the threat state is secret too (everything)
--   Mock.secrets.Set{ identity = true }           GUIDs, names and classes of other units are secret
--   Mock.secrets.Set{ comparison = true }         UnitIsUnit answers a secret
--   predictValues, predictState                   what C_Secrets predicts when it must differ from what the client
--                                                 returns (a prediction that lies)
--   restrictions = false                          HasSecretRestrictions (default: true when anything is secret)
--   Mock.secrets.Reset()
-- Mock.Secret("number") makes a secret by hand (an event payload, a spell id).
local Mock = ...
local W = Mock.world

W.secrets = W.secrets or {}
W.secretKinds = W.secretKinds or setmetatable({}, { __mode = "k" })
local config, kinds = W.secrets, W.secretKinds

local plainType = type
function type(...)
	if select("#", ...) == 0 then return plainType() end
	local value = ...
	return kinds[value] or plainType(value)
end

local function refuse(operation)
	return function() error("secret value used: " .. operation, 2) end
end

-- One metatable for every secret: each value is its own userdata, so two secrets never compare equal by identity.
local prototype = newproxy(true)
do
	local meta = getmetatable(prototype)
	meta.__index = refuse("indexed")
	meta.__newindex = refuse("assigned")
	meta.__call = refuse("called")
	meta.__concat = refuse("concatenated")
	meta.__tostring = refuse("turned into text")
	meta.__len = refuse("measured")
	meta.__eq = refuse("compared")
	meta.__lt = refuse("compared")
	meta.__le = refuse("compared")
	meta.__add = refuse("added")
	meta.__sub = refuse("subtracted")
	meta.__mul = refuse("multiplied")
	meta.__div = refuse("divided")
	meta.__mod = refuse("taken modulo")
	meta.__pow = refuse("raised to a power")
	meta.__unm = refuse("negated")
	meta.__metatable = false
end

function Mock.Secret(kind)
	local value = newproxy(prototype)
	kinds[value] = kind or "number"
	return value
end

function issecretvalue(value) return kinds[value] ~= nil end
function issecrettable(value) return kinds[value] ~= nil end
function canaccessvalue(value) return kinds[value] == nil end

local secrets = {}
Mock.secrets = secrets

local FIELDS = { values = true, state = true, identity = true, comparison = true, predictValues = true,
	predictState = true, restrictions = true }

function secrets.Set(changes)
	for key, value in pairs(changes) do
		if not FIELDS[key] then error("Mock.secrets.Set: unknown field " .. tostring(key), 2) end
		config[key] = value
	end
end

function secrets.Reset()
	for key in pairs(FIELDS) do config[key] = nil end
end

local function answer(field, a, b)
	local value = config[field]
	if plainType(value) == "function" then value = value(a, b) end
	return value
end

-- What the client really returns: values are secret when the values or the whole state are.
function secrets.StateSecret(unit, mob) return answer("state", unit, mob) == true end
function secrets.ValuesSecret(unit, mob) return answer("values", unit, mob) == true or secrets.StateSecret(unit, mob) end
function secrets.IdentitySecret(unit) return unit ~= "player" and answer("identity", unit) == true end
function secrets.ComparisonSecret(a, b) return answer("comparison", a, b) == true end

local function predicted(field, real, unit, mob)
	local value = answer(field, unit, mob)
	if value == nil then return real(unit, mob) end
	return value == true
end

local function needUnit(value, name)
	if plainType(value) ~= "string" then error("Usage: " .. name .. "(unit)", 3) end
end

C_Secrets = {}

function C_Secrets.HasSecretRestrictions()
	if config.restrictions ~= nil then return config.restrictions == true end
	return (config.values or config.state or config.identity or config.comparison or config.predictValues
		or config.predictState) and true or false
end

function C_Secrets.ShouldUnitThreatStateBeSecret(unit, mob)
	needUnit(unit, "ShouldUnitThreatStateBeSecret")
	return predicted("predictState", secrets.StateSecret, unit, mob)
end

function C_Secrets.ShouldUnitThreatValuesBeSecret(unit, mob)
	needUnit(unit, "ShouldUnitThreatValuesBeSecret")
	needUnit(mob, "ShouldUnitThreatValuesBeSecret")
	local value = answer("predictValues", unit, mob)
	if value ~= nil then return value == true end
	return secrets.ValuesSecret(unit, mob)
end

function C_Secrets.ShouldUnitIdentityBeSecret(unit)
	needUnit(unit, "ShouldUnitIdentityBeSecret")
	return secrets.IdentitySecret(unit)
end

function C_Secrets.ShouldUnitComparisonBeSecret(a, b)
	needUnit(a, "ShouldUnitComparisonBeSecret")
	needUnit(b, "ShouldUnitComparisonBeSecret")
	return secrets.ComparisonSecret(a, b)
end

function C_Secrets.CanCompareUnitTokens(a, b)
	needUnit(a, "CanCompareUnitTokens")
	needUnit(b, "CanCompareUnitTokens")
	return not secrets.ComparisonSecret(a, b)
end
