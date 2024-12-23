local create_object = function(_)
	local Class = setmetatable({}, {
		__call = function(self, ...)
			local instance = setmetatable({}, self)
			instance:init(...)
			return instance
		end,
	})
	Class.__index = Class

	function Class:init() end

	return Class
end

---@class markup.BasicObject
local BasicObject = setmetatable({}, { __call = create_object })

return BasicObject
