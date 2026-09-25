--!strict
-- Number, time and odds formatting shared by UI, chat and leaderboards.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.commas(n: number): string
	local negative = n < 0
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return if negative then "-" .. out else out
end

-- 950 → "950", 1234 → "1.23K", 45678 → "45.7K", 1.2e9 → "1.2B"
function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = if n == math.floor(n) then tostring(n) else string.format("%.1f", n)
		return if negative then "-" .. s else s
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / (1000 ^ tier)
	local s
	if scaled >= 100 then
		s = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		s = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		s = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	if s:find(".", 1, true) then
		s = s:gsub("0+$", ""):gsub("%.$", "")
	end
	return (if negative then "-" else "") .. s .. SUFFIXES[tier + 1]
end

-- Seconds → "4:05" or "1:02:03"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- Seconds → "8h 12m", "5m 3s", "12s"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	end
	return string.format("%ds", s)
end

function Format.weight(kg: number): string
	if kg >= 1000 then
		return string.format("%.2f t", kg / 1000)
	elseif kg >= 100 then
		return string.format("%d kg", math.floor(kg + 0.5))
	elseif kg >= 10 then
		return string.format("%.1f kg", kg)
	end
	return string.format("%.2f kg", kg)
end

function Format.meters(m: number): string
	return Format.commas(m) .. "m"
end

function Format.percent(fraction: number, decimals: number?): string
	local d = decimals or 0
	return string.format("%." .. d .. "f%%", fraction * 100)
end

-- Probability → "1 in 1,234"
function Format.odds(p: number): string
	if p <= 0 then
		return "—"
	end
	if p >= 1 then
		return "Guaranteed"
	end
	local n = 1 / p
	if n < 10 then
		return "1 in " .. string.format("%.1f", n)
	end
	if n >= 1e6 then
		return "1 in " .. Format.short(n)
	end
	return "1 in " .. Format.commas(n)
end

return Format
