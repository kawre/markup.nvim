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

local Switch = setmetatable({}, {
	__call = function(value, cases)
		cases = normalize_cases(cases)

		local case = cases[value]
		if case then
			return case
		end

		local default = cases.default
		if default then
			return default
		end
	end,
	__name = Collection.SWITCH,
})

---@alias markup.Switch fun(value: any, cases: { default?: any }): any

---@type markup.Switch
return Switch
