-- Mock client, part 10: the sounds of the game.
--
-- Imitates: PlaySound and C_Sound.PlaySound.
-- Dump (../WoW-Addons/docs/api.json, build 70170): the global PlaySound and system Sound (C_Sound) —
--   PlaySound(soundKitID, uiSoundSubType, forceNoDuplicates, runFinishCallback, overridePriority, volumeOverride)
--   -> success, soundHandle.
-- Whether a kit exists on Forever, and what the call answers for one that does not, only the game can say.
--
--   Mock.sound.calls      one { kit =, at = } per call, in order
--   Mock.sound.refuse     true: the call answers false (not played)
--   Mock.sound.fail       true: the call raises
local Mock = ...
local W = Mock.world

local sound = { calls = {}, refuse = false, fail = false }
Mock.sound = sound

local function play(kit)
	if type(kit) ~= "number" then error("Usage: PlaySound(soundKitID)", 3) end
	if sound.fail then error("mock sound error", 3) end
	sound.calls[#sound.calls + 1] = { kit = kit, at = W.clock.now }
	if sound.refuse then return false, nil end
	return true, #sound.calls
end

function PlaySound(...) return play((...)) end

C_Sound = {}
function C_Sound.PlaySound(...) return play((...)) end
