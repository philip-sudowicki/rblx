-- Test prelude: minimal Roblox stand-ins so pure DEEP HAUL modules run under the `luau` CLI.
-- Only what the pure modules need (datatypes, Enum, a virtual instance tree, require).

local baseEnv = getfenv(0)

---------------------------------------------------------------- typeof
local nativeTypeof = typeof
local function stubTypeof(v: any): string
	if type(v) == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
	end
	return nativeTypeof(v)
end

---------------------------------------------------------------- Vector3
local Vector3 = {}
local V3 = { __type = "Vector3" }
local V3methods = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	end
	return V3methods[k]
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end
function V3methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3methods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3methods.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3methods.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
Vector3.new = v3
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

---------------------------------------------------------------- Vector2
local Vector2 = {}
local V2 = { __type = "Vector2" }
V2.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end
	return nil
end
Vector2.new = function(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
Vector2.zero = Vector2.new(0, 0)

---------------------------------------------------------------- Color3
local Color3 = {}
local C3 = { __type = "Color3" }
C3.__index = {
	Lerp = function(a, b, t)
		return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
	end,
	ToHex = function(c)
		return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end,
}
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
end
function Color3.fromRGB(r, g, b)
	assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "Color3.fromRGB expects numbers")
	return Color3.new(r / 255, g / 255, b / 255)
end
function Color3.fromHex(hex)
	hex = hex:gsub("#", "")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then
		return Color3.new(v, t, p)
	elseif i == 1 then
		return Color3.new(q, v, p)
	elseif i == 2 then
		return Color3.new(p, v, t)
	elseif i == 3 then
		return Color3.new(p, q, v)
	elseif i == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end

---------------------------------------------------------------- simple datatypes
local function datatype(name, fields)
	local mt = { __type = name }
	mt.__index = mt
	local ctor = {}
	ctor.new = function(...)
		local args = { ... }
		local obj = {}
		for i, field in ipairs(fields) do
			obj[field] = args[i]
		end
		obj.__args = args
		return setmetatable(obj, mt)
	end
	return ctor
end
local ColorSequence = datatype("ColorSequence", { "Keypoints" })
local ColorSequenceKeypoint = datatype("ColorSequenceKeypoint", { "Time", "Value" })
local NumberSequence = datatype("NumberSequence", { "Keypoints" })
local NumberSequenceKeypoint = datatype("NumberSequenceKeypoint", { "Time", "Value" })
local NumberRange = datatype("NumberRange", { "Min", "Max" })
local UDim = datatype("UDim", { "Scale", "Offset" })
local UDim2 = datatype("UDim2", { "XScale", "XOffset", "YScale", "YOffset" })
UDim2.fromScale = function(x, y)
	return UDim2.new(x, 0, y, 0)
end
UDim2.fromOffset = function(x, y)
	return UDim2.new(0, x, 0, y)
end
local TweenInfo = datatype("TweenInfo", { "Time" })

---------------------------------------------------------------- Enum
local enumCache = {}
local EnumItemMt = { __type = "EnumItem" }
EnumItemMt.__index = EnumItemMt
EnumItemMt.__tostring = function(item)
	return "Enum." .. item.EnumType .. "." .. item.Name
end
local Enum = setmetatable({}, {
	__index = function(_, enumType)
		if not enumCache[enumType] then
			local items = {}
			enumCache[enumType] = setmetatable({}, {
				__index = function(_, name)
					if not items[name] then
						items[name] = setmetatable({ EnumType = enumType, Name = name }, EnumItemMt)
					end
					return items[name]
				end,
			})
		end
		return enumCache[enumType]
	end,
})

---------------------------------------------------------------- virtual instance tree
local Node = {}
Node.__index = function(node, key)
	local method = rawget(Node, key)
	if method then
		return method
	end
	local children = rawget(node, "_children")
	local child = children[key]
	if child then
		return child
	end
	error(string.format("%s is not a valid member of %s", tostring(key), rawget(node, "_path")), 2)
end
Node.__tostring = function(node)
	return rawget(node, "Name")
end

local function newNode(name, parent, path)
	local node = setmetatable({ Name = name, Parent = parent, _children = {}, _path = path }, Node)
	if parent then
		rawget(parent, "_children")[name] = node
	end
	return node
end
function Node.FindFirstChild(self, name)
	return rawget(self, "_children")[name]
end
function Node.WaitForChild(self, name)
	local child = rawget(self, "_children")[name]
	if not child then
		error("WaitForChild would hang: " .. rawget(self, "_path") .. "." .. tostring(name))
	end
	return child
end
function Node.GetChildren(self)
	local out = {}
	for _, child in pairs(rawget(self, "_children")) do
		table.insert(out, child)
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end
function Node.IsA(self, className)
	if className == "ModuleScript" then
		return rawget(self, "_source") ~= nil
	end
	return className == "Instance" or className == "Folder"
end
function Node.GetFullName(self)
	return rawget(self, "_path")
end

local root = newNode("game", nil, "game")

local function ensurePath(path)
	local node = root
	local built = "game"
	for part in string.gmatch(path, "[^/]+") do
		built = built .. "." .. part
		local existing = rawget(node, "_children")[part]
		if not existing then
			existing = newNode(part, node, built)
		end
		node = existing
	end
	return node
end

---------------------------------------------------------------- services
local fakeSignal = {
	Connect = function()
		return { Disconnect = function() end }
	end,
}
local RunService = {
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
	IsStudio = function()
		return true
	end,
	Heartbeat = fakeSignal,
	RenderStepped = fakeSignal,
	Stepped = fakeSignal,
}
local services = {
	RunService = RunService,
	Players = { GetPlayers = function()
		return {}
	end, PlayerAdded = fakeSignal, PlayerRemoving = fakeSignal },
	HttpService = {
		GenerateGUID = function()
			return "00000000-0000-0000-0000-000000000000"
		end,
	},
}
local game = setmetatable({
	GetService = function(_, name)
		if services[name] then
			return services[name]
		end
		return ensurePath(name)
	end,
}, {
	__index = function(_, key)
		return ensurePath(key)
	end,
})

local task = {
	spawn = function(fn, ...)
		if type(fn) == "function" then
			fn(...)
		end
	end,
	defer = function(fn, ...)
		if type(fn) == "function" then
			fn(...)
		end
	end,
	delay = function() end,
	wait = function()
		return 0
	end,
}

---------------------------------------------------------------- module loading
local moduleCache = {}
local loading = {}
local stubRequire

local function envFor(node)
	return setmetatable({
		script = node,
		require = stubRequire,
		game = game,
		workspace = ensurePath("Workspace"),
		typeof = stubTypeof,
		Vector3 = Vector3,
		Vector2 = Vector2,
		Color3 = Color3,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		NumberSequence = NumberSequence,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		NumberRange = NumberRange,
		UDim = UDim,
		UDim2 = UDim2,
		TweenInfo = TweenInfo,
		Enum = Enum,
		task = task,
	}, { __index = baseEnv })
end

stubRequire = function(node)
	if type(node) ~= "table" or rawget(node, "_source") == nil then
		error("require: not a ModuleScript: " .. tostring(node), 2)
	end
	local path = rawget(node, "_path")
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	if loading[path] then
		error("cyclic require: " .. path, 2)
	end
	loading[path] = true
	local fn, err = loadstring(rawget(node, "_source"), "=" .. path)
	if not fn then
		error("compile error in " .. path .. ": " .. tostring(err))
	end
	setfenv(fn, envFor(node))
	local result = fn()
	loading[path] = nil
	moduleCache[path] = result
	return result
end

function __registerModules(modules)
	for path, source in pairs(modules) do
		local node = ensurePath(path)
		rawset(node, "_source", source)
	end
end

---------------------------------------------------------------- test runner
function __runTests(files)
	local passed, failed = 0, 0
	local failures = {}
	for _, file in ipairs(files) do
		local tests = {}
		local env = envFor(ensurePath("Tests"))
		env.test = function(name, fn)
			table.insert(tests, { name = name, fn = fn })
		end
		env.Shared = ensurePath("ReplicatedStorage/Shared")
		env.ServerPure = ensurePath("ServerScriptService/Server/Pure")
		env.ServerConfig = ensurePath("ServerScriptService/Server/Config")
		env.eq = function(actual, expected, msg)
			if actual ~= expected then
				error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(actual)), 2)
			end
		end
		env.near = function(actual, expected, eps, msg)
			if math.abs(actual - expected) > eps then
				error(string.format("%sexpected %s ± %s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(eps), tostring(actual)), 2)
			end
		end
		env.ok = function(cond, msg)
			if not cond then
				error(msg or "assertion failed", 2)
			end
		end
		local fn, err = loadstring(file.source, "=" .. file.name)
		if not fn then
			error("compile error in " .. file.name .. ": " .. tostring(err))
		end
		setfenv(fn, env)
		fn()
		for _, t in ipairs(tests) do
			local success, message = pcall(t.fn)
			if success then
				passed += 1
			else
				failed += 1
				table.insert(failures, string.format("  FAIL %s › %s\n       %s", file.name, t.name, tostring(message)))
			end
		end
	end
	for _, line in ipairs(failures) do
		print(line)
	end
	print(string.format("%d passed, %d failed", passed, failed))
	if failed > 0 then
		error("unit tests failed")
	end
end
