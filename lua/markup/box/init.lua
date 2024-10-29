local markup = require("markup")
local log = require("markup.logger")

---@alias markup.Box.align "start"|"center"|"end"
---@alias markup.Box.direction "row"|"column"

---@class markup.Box.props : markup.Element.props
---@field align markup.Box.align
---@field spacing integer
---@field direction markup.Box.direction

---@class markup.Box : markup.Element
---@field _ markup.Box.props
local Box = markup.Block:extend("MarkupBox")

---@param props markup.Box.constructor.props
function Box:init(props)
	props = vim.tbl_deep_extend("force", {
		align = "start",
		direction = "column",
		spacing = 0,
		children = {},
	}, props)

	Box.super.init(self, props)
end

-- function Box:content()
-- 	--    local children = self._.children
-- 	--    local content = {}
-- 	--
-- 	-- for _, elem in ipairs(children) do
-- 	--
-- 	-- end
--
-- 	return self._.children
-- end

---@param renderer markup.Renderer
---@param parent markup.Element
function Box:draw(renderer, parent)
	local content = self:content()

	renderer:endl()

	for i, obj in ipairs(content) do
		markup
			[self._.direction == "row" and "Inline" or "Block"]({
				children = obj:content(),
			})
			:draw(renderer, self)

		if i ~= #content and self._.spacing then
			if self._.direction == "row" then
				renderer:pad(self._.spacing)
			else
				renderer:endl(self._.spacing)
			end
		end
	end

	renderer:endl()
end

---@class markup.Box.constructor.props
---@field children markup.Element[]
---@field spacing? integer
---@field align? markup.Box.align
---@field direction? markup.Box.direction

---@alias markup.Box.constructor fun(props: markup.Element | markup.Box.constructor.props): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box

return MarkupBox
