local markup = require("markup.core")
-- local FiberTag = require("markup.core.reconciler.enum").Tag

---@alias markup.create_fiber_from_fragment
---| fun(elements: markup.xElement[], key?): markup.Fiber

---@type markup.create_fiber_from_fragment
local function create_fiber_from_fragment(elements, key)
	return markup.create_fiber(nil, elements, key)
end

return create_fiber_from_fragment
