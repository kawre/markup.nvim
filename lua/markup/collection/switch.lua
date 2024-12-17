local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Collection = require("markup.core.enum").Collection

local function normalize_cases(cases)
	local new_cases = {}

	for k, case in pairs(cases) do
		if type(k) == "table" then
			for _, v in ipairs(k) do
				new_cases[v] = case
			end
		else
			new_cases[k] = case
		end
	end

	return new_cases
end

local function is_callable(value)
	if type(value) == "function" then
		return true
	end
	local mt = getmetatable(value)
	return mt and type(mt.__call) == "function"
end

local function call_value(value, ...)
	if is_callable(value) then
		return value(...)
	else
		return value
	end
end

local Switch = setmetatable({}, {
	__call = function(_, value, cases, ...)
		cases = normalize_cases(cases)
		local case = cases[value]
		local default = cases.default

		if case then
			return call_value(case, ...)
		end

		if default then
			return call_value(default, ...)
		end
	end,
	__name = Collection.SWITCH,
})

---@alias markup.Switch fun(value: any, cases: { default?: any }, ...): any

---@type markup.Switch
return Switch
