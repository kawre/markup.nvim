local markup = require("markup.core")
local FiberTag = require("markup.core.reconciler.enum").Tag

---@alias markup.create_fiber_root fun(child: markup.xElement): markup.Fiber

---@type markup.create_fiber_root
local function create_fiber_root(child)
	local fiber_root = markup.create_fiber(nil)

	fiber_root.tag = FiberTag.ROOT
	fiber_root.pending_props = { children = child }

	return fiber_root
end

return create_fiber_root
