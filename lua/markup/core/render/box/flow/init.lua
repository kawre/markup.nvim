local markup = require("markup.core")

---@class markup.Render.Flow : markup.Render.Box
local RenderFlow = markup.Render.Box:extend("markup.render.flow")

function RenderFlow:is_inline()
	--
end

function RenderFlow:is_inline_flow()
	--
end

function RenderFlow:is_block_flow()
	--
end

function RenderFlow:is_anonymous_block()
	--
end

function RenderFlow:make_children_non_inline()
	--
end

return RenderFlow
