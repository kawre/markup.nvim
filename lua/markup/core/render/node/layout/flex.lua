---@class markup.Render.Layout.Flex : markup.Render.Layout
local FlexLayout = {}
FlexLayout.__name = "RenderFlex"
FlexLayout.__type = { flex = true, block = true }

function FlexLayout.layout(node)
	-- flex layout logic
end

return FlexLayout
