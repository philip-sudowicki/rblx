--!strict
-- Argument validation for remote payloads. Everything from the client is untrusted.

local Validate = {}

function Validate.number(x: any, min: number?, max: number?): boolean
	if typeof(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return false
	end
	if min and x < min then
		return false
	end
	if max and x > max then
		return false
	end
	return true
end

function Validate.integer(x: any, min: number?, max: number?): boolean
	return Validate.number(x, min, max) and math.floor(x) == x
end

function Validate.string(x: any, maxLength: number): boolean
	return typeof(x) == "string" and #x <= maxLength and utf8.len(x) ~= nil
end

function Validate.boolean(x: any): boolean
	return typeof(x) == "boolean"
end

function Validate.oneOf(x: any, set: { [string]: any }): boolean
	return typeof(x) == "string" and set[x] ~= nil
end

-- Array of integers (e.g. item uids), at most maxLength entries, no duplicates.
function Validate.intArray(x: any, maxLength: number, min: number?, max: number?): boolean
	if typeof(x) ~= "table" then
		return false
	end
	local count = 0
	local seen = {}
	for key, value in x do
		count += 1
		if count > maxLength or typeof(key) ~= "number" or not Validate.integer(value, min, max) or seen[value] then
			return false
		end
		seen[value] = true
	end
	return count == #x
end

return Validate
