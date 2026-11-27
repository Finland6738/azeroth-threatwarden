-- A strict RFC 4180 reader for the export tests (SPEC-06 §4.3, EXP-02): "," between fields, "\n" between rows (the
-- game's edit box holds no "\r"), quoted fields with doubled quotes, line breaks inside quotes. It fails on anything a
-- strict reader would refuse: a quote inside an unquoted field, text after a closing quote, a quote never closed.
-- Loaded by Tests/lib/harness.lua; test files see it as the global `CSV`.
-- Adapted from Azeroth Accord (Tests/lib/csv.lua), same owner, GPL-3.0 (ADR 0012).
local CSV = {}

-- text -> { { field, ... }, ... }; raises on malformed text.
function CSV.parse(text)
	local rows, row = {}, {}
	local i, n = 1, #text
	while true do
		local field
		if text:sub(i, i) == '"' then
			local parts = {}
			i = i + 1
			while true do
				local q = text:find('"', i, true)
				if not q then error("csv: a quoted field is never closed", 2) end
				parts[#parts + 1] = text:sub(i, q - 1)
				if text:sub(q + 1, q + 1) == '"' then
					parts[#parts + 1] = '"'
					i = q + 2
				else
					i = q + 1
					break
				end
			end
			field = table.concat(parts)
			local after = text:sub(i, i)
			if after ~= "" and after ~= "," and after ~= "\n" then error("csv: text after a closing quote", 2) end
		else
			local stop = text:find("[,\n]", i) or (n + 1)
			field = text:sub(i, stop - 1)
			if field:find('"', 1, true) then error("csv: a quote inside an unquoted field: " .. field, 2) end
			if field:find("\r", 1, true) then error("csv: a carriage return outside quotes", 2) end
			i = stop
		end
		row[#row + 1] = field
		local sep = text:sub(i, i)
		if sep == "," then
			i = i + 1
		else
			rows[#rows + 1] = row
			if sep == "" then return rows end
			row = {}
			i = i + 1
			if i > n then return rows end   -- a final line break
		end
	end
end

-- text -> header (list), records ({ [column] = value }); raises when a row has not the header's number of fields.
function CSV.records(text)
	local rows = CSV.parse(text)
	local header, out = rows[1], {}
	for i = 2, #rows do
		if #rows[i] ~= #header then error(("csv: row %d has %d fields, the header %d"):format(i, #rows[i], #header), 2) end
		local r = {}
		for c, name in ipairs(header) do r[name] = rows[i][c] end
		out[#out + 1] = r
	end
	return header, out
end

return CSV
