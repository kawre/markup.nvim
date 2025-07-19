local H = {}

function H.mock_markup()
	local function serialize(props)
		local function serialize_table(tbl)
			local parts = {}
			for k, v in pairs(tbl) do
				if type(k) ~= "number" then
					table.insert(parts, ("%s = %s"):format(k, serialize(v)))
				else
					table.insert(parts, serialize(v))
				end
			end
			return ("{ %s }"):format(table.concat(parts, ", "))
		end

		if type(props) == "table" then
			return serialize_table(props)
		elseif type(props) == "number" then
			return tostring(props)
		elseif type(props) == "string" then
			return props:match("^markup%.[^%.%(%)%s]+%b()$") and props or ("\"%s\""):format(props)
		elseif type(props) == "boolean" then
			return tostring(props)
		else
			error(("Unsupported type: %s"):format(type(props)))
		end
	end

	local function serializer(_, key)
		return function(props)
			return ("markup.%s(%s)"):format(key, serialize(props))
		end
	end

	return setmetatable({}, { __index = serializer })
end

return H
