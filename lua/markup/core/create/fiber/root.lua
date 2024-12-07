local markup = require("markup.core")
local FiberTag = require("markup.core.fiber.enum").Tag

---@alias markup.create_fiber_root fun(): markup.Fiber

---@type markup.create_fiber_root
local function create_fiber_root()
	local root = markup.create_root()
	local fiber = markup.Fiber(root)
	fiber.state_node = fiber.type(fiber.props)
	fiber.tag = FiberTag.ROOT
	return fiber
end

return create_fiber_root
