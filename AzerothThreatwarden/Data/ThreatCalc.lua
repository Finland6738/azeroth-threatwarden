-- ThreatCalc: the numbers derived from the threat reads (SPEC-02 §2, SPEC-03 §2.2, §2.5, ADR 0003). Lua 5.1, no game
-- API, no state of its own: Data/ThreatModel.lua keeps the rows and calls these functions on every update.
-- Threatwarden's own.
--
--   Margin                calculated  a non tank: 100 - p, in points; nil when p is not known
--   TankMargin            calculated  the unit holding the mob: 100 - s, s the highest scaled % of the other rows read
--                                     in `values`; [probe P2]: UnitThreatPercentageOfLead only when USE_LEAD is true
--   Trend                 estimated   least-squares slope of the scaled % over the valid samples of the last 3 s
--                                     (N >= 3 over >= 0.5 s), points per second, with a confidence from N and R²
--   Overtake              predicted   (100 - p) / trend for a non tank, only with trend > 0, confidence >= medium,
--                                     p < 100 and a result <= 10 s, rounded up to the second
--   PredictedWarning      predicted   (D - p) / trend <= 3 s with confidence >= medium (the predicted WARNING, M2.4)
--
-- Nothing here ever turns an unknown into a number: a nil in gives a nil out, with the reason it is missing
-- ("insufficient" = Insufficient data, "state-only", "alone", "not-rising", "low-confidence", "beyond", "holder", or the
-- reason of the read). The samples are a ring of SIZE pairs (observedAt, scaled %), made once per row (ARC-06).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local ThreatCalc = {}
ns.ThreatCalc, ns.modules.ThreatCalc = ThreatCalc, ThreatCalc

local type, ceil = type, math.ceil

ThreatCalc.SIZE = 32          -- samples kept per row (SPEC-03 §2.5)
ThreatCalc.WINDOW = 3         -- seconds of samples the trend looks at
ThreatCalc.MIN_SAMPLES = 3    -- fewer valid samples: Insufficient data (M2.3 Done when)
ThreatCalc.MIN_SPAN = 0.5     -- seconds the samples of a trend must cover
ThreatCalc.GAP = 1            -- seconds between two valid samples that restart the ring
ThreatCalc.HIGH = { samples = 8, r2 = 0.8 }
ThreatCalc.MEDIUM = { samples = 5, r2 = 0.5 }
ThreatCalc.MAX_OVERTAKE = 10  -- seconds: a later overtake is not shown
ThreatCalc.WARNING_AHEAD = 3  -- seconds: the predicted WARNING (SPEC-03 §2.2)
ThreatCalc.USE_LEAD = false   -- [probe P2]: true only if UnitThreatPercentageOfLead proves to be the % over the second

local EPSILON = 1e-6
local RANK = { high = 3, medium = 2, low = 1, unknown = 0 }

-- True when `confidence` is at least medium.
function ThreatCalc.Trusted(confidence)
	return (RANK[confidence] or 0) >= RANK.medium
end

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---------------------------------------------------------------------------------------------------------------------
-- The ring of samples
---------------------------------------------------------------------------------------------------------------------
-- A ring of SIZE samples, filled with zeros so that pushing into it never grows a table.
function ThreatCalc.NewSamples()
	local s = { t = {}, p = {}, head = 0, count = 0 }
	for i = 1, ThreatCalc.SIZE do s.t[i], s.p[i] = 0, 0 end
	return s
end

function ThreatCalc.Reset(s)
	s.head, s.count = 0, 0
end

-- The newest sample's time, or nil for an empty ring.
function ThreatCalc.Last(s)
	if s.count == 0 then return nil end
	return s.t[s.head]
end

-- Adds a valid sample. A sample not newer than the last one is ignored (a duplicate read, MON-07: an older sample never
-- replaces a newer one); a gap of more than GAP seconds since the last one restarts the ring (SPEC-03 §2.5).
-- Returns true when added.
function ThreatCalc.Push(s, t, p)
	if not finite(t) or not finite(p) then return false end
	if s.count > 0 then
		local last = s.t[s.head]
		if t <= last then return false end
		if t - last > ThreatCalc.GAP then s.head, s.count = 0, 0 end
	end
	local size = ThreatCalc.SIZE
	local head = s.head % size + 1
	s.t[head], s.p[head] = t, p
	s.head = head
	if s.count < size then s.count = s.count + 1 end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Trend (estimated)
---------------------------------------------------------------------------------------------------------------------
-- ThreatCalc.Trend(samples, now) -> slope (points per second) or nil, confidence, samples used, r2.
-- Least squares over the samples of the last WINDOW seconds before `now` (the newest sample when `now` is nil).
-- Fewer than MIN_SAMPLES samples, or less than MIN_SPAN seconds between the first and the last: nil, "unknown"
-- (Insufficient data). A constant series has slope 0 and counts as R² = 1.
function ThreatCalc.Trend(s, now)
	local count = s.count
	if count == 0 then return nil, "unknown", 0, nil end
	local size, ts, ps, head = ThreatCalc.SIZE, s.t, s.p, s.head
	local newest = ts[head]
	if not finite(now) then now = newest end
	local from, to = now - ThreatCalc.WINDOW - EPSILON, now + EPSILON   -- a little slack for the float sums of times
	local n, sx, sy, sxx, sxy, syy = 0, 0, 0, 0, 0, 0
	local first, last = nil, nil
	local i = head
	for _ = 1, count do
		local t = ts[i]
		if t < from then break end   -- older from here on
		if t <= to then
			local x, y = t - newest, ps[i]   -- times relative to the newest sample: small numbers, stable sums
			n = n + 1
			sx, sy = sx + x, sy + y
			sxx, sxy, syy = sxx + x * x, sxy + x * y, syy + y * y
			if not last then last = t end
			first = t
		end
		i = i - 1
		if i < 1 then i = size end
	end
	if n < ThreatCalc.MIN_SAMPLES or (last - first) < ThreatCalc.MIN_SPAN then return nil, "unknown", n, nil end
	local varX = sxx - sx * sx / n
	if varX <= 0 then return nil, "unknown", n, nil end
	local covXY = sxy - sx * sy / n
	local varY = syy - sy * sy / n
	local slope = covXY / varX
	local r2
	if varY <= 1e-9 * n then
		r2 = 1
	else
		r2 = covXY * covXY / (varX * varY)
		if r2 > 1 then r2 = 1 elseif r2 < 0 then r2 = 0 end
	end
	local confidence = "low"
	if n >= ThreatCalc.HIGH.samples and r2 >= ThreatCalc.HIGH.r2 then
		confidence = "high"
	elseif n >= ThreatCalc.MEDIUM.samples and r2 >= ThreatCalc.MEDIUM.r2 then
		confidence = "medium"
	end
	return slope, confidence, n, r2
end

---------------------------------------------------------------------------------------------------------------------
-- Margin (calculated)
---------------------------------------------------------------------------------------------------------------------
-- The margin of a non tank: 100 - p points, or nil and "missing" when p is not known.
function ThreatCalc.Margin(p)
	if not finite(p) then return nil, "missing" end
	return 100 - p, nil
end

-- The margin of the unit holding the mob: 100 - s, with s the highest scaled % among the other rows read in `values`.
--   second   the highest scaled % of the others, or nil
--   others   how many other rows are on the threat list (present), read in any mode
--   reason   why `second` is nil while others exist (the reason of the first of them)
--   lead     the holder's UnitThreatPercentageOfLead, used only when USE_LEAD is true [probe P2]
-- Returns margin or nil, and the reason: "alone" (no one else on the list), or the reason of the others.
function ThreatCalc.TankMargin(second, others, reason, lead)
	if ThreatCalc.USE_LEAD and finite(lead) then return lead - 100, nil end
	if finite(second) then return 100 - second, nil end
	if not others or others == 0 then return nil, "alone" end
	return nil, reason or "missing"
end

---------------------------------------------------------------------------------------------------------------------
-- Predictions
---------------------------------------------------------------------------------------------------------------------
-- ThreatCalc.Overtake(p, trend, confidence) -> whole seconds (rounded up) until a non tank may take the aggro, or nil
-- and the reason: "insufficient" (no trend or no p), "not-rising" (trend <= 0), "low-confidence", "has-aggro"
-- (p >= 100), "beyond" (more than MAX_OVERTAKE seconds).
function ThreatCalc.Overtake(p, trend, confidence)
	if not finite(p) or not finite(trend) then return nil, "insufficient" end
	if p >= 100 then return nil, "has-aggro" end
	if trend <= EPSILON then return nil, "not-rising" end   -- a flat series gives a float dust slope
	if not ThreatCalc.Trusted(confidence) then return nil, "low-confidence" end
	local t = (100 - p) / trend
	if t > ThreatCalc.MAX_OVERTAKE then return nil, "beyond" end
	return ceil(t - 1e-9), nil
end

-- True when the trend says that p reaches the DANGER threshold `danger` within WARNING_AHEAD seconds with a confidence
-- of at least medium (SPEC-03 §2.2); the seconds as a second value.
function ThreatCalc.PredictedWarning(p, trend, confidence, danger)
	if not finite(p) or not finite(trend) or not finite(danger) then return false end
	if p >= danger or trend <= EPSILON or not ThreatCalc.Trusted(confidence) then return false end
	local t = (danger - p) / trend
	return t <= ThreatCalc.WARNING_AHEAD, t
end

-- True when a read observed at `observedAt`, expected every `interval` seconds (nil: no place in the round robin), is
-- older than the freshness threshold max(2 * interval, 0.5 s) at `now` (SPEC-03 §1.5, DAT-12).
function ThreatCalc.IsStale(observedAt, interval, now)
	if not finite(observedAt) or not finite(now) then return true end
	local limit = 0.5
	if finite(interval) and 2 * interval > limit then limit = 2 * interval end
	return now - observedAt > limit + 1e-9
end

if ns.addon then ns.addon.ThreatCalc = ThreatCalc end
