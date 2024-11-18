---@alias markup.If.constructor fun(cond: boolean, node: markup.Node|markup.Node[]): markup.Node

---@type markup.If.constructor
return setmetatable({}, {
	__call = function(_, cond, node, else_node)
		if cond and node then
			if type(node) == "function" then
				node = node()
			end

			return node
		else
			return else_node or {}
		end
	end,
})
