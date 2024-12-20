return function()
	return setmetatable({}, {
		__call = function(self)
			local instance = setmetatable({}, {
				__index = self,
				__tostring = function(b)
					if self.__tostring then
						return self.__tostring(b)
					else
						return tostring(b)
					end
				end,
			})
			instance:init()
			return instance
		end,
	})
end
