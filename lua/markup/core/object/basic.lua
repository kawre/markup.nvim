return function()
	return setmetatable({}, {
		__call = function(self)
			local instance = setmetatable({}, {
				__index = self,
				__tostring = function(b)
					return self.__tostring(b)
				end,
			})
			instance:init()
			return instance
		end,
	})
end
