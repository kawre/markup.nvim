--- Images drawn over a view, where their element sits in the layout.
---
--- The terminal draws them on top of the text, so an image has to move when its
--- element does, and go when it scrolls away, is clipped, or unmounts. Views
--- take care of that, this holds the backend and what images measure.

---@class markup.image.backend
---@field set fun(data_or_id: string|integer, opts: table): integer
---@field del fun(id: integer): boolean

---@class markup.image
local M = {
	--- Width over height of a terminal cell, which is about twice as tall.
	cell_ratio = 0.5,
	--- Cells wide, when an element gives no width.
	default_width = 40,
}

--- What shows images, `vim.ui.img` when this Neovim has it. Replace it to use
--- something else, with `set` and `del` like `vim.ui.img`.
---@type markup.image.backend?
M.backend = vim.ui and vim.ui.img

---@return boolean
function M.available()
	return M.backend ~= nil
end

local PNG_SIGNATURE = "\137PNG\r\n\26\n"

local function uint32(data, at)
	local a, b, c, d = data:byte(at, at + 3)
	return ((a * 256 + b) * 256 + c) * 256 + d
end

--- Pixels of a PNG, read from its header.
---@param data string
---@return integer? width
---@return integer? height
function M.png_size(data)
	if type(data) ~= "string" or #data < 24 or data:sub(1, 8) ~= PNG_SIGNATURE then
		return nil
	end
	return uint32(data, 17), uint32(data, 21)
end

--- Cells an image takes. A missing height follows the proportions of the image.
---@param data? string
---@param width? integer
---@param height? integer
---@return integer width
---@return integer height
function M.size(data, width, height)
	width = width or M.default_width
	if height then
		return width, height
	end

	local pixels_wide, pixels_tall = M.png_size(data)
	if pixels_wide and pixels_wide > 0 then
		return width, math.max(math.floor(width * pixels_tall / pixels_wide * M.cell_ratio + 0.5), 1)
	end
	return width, 1
end

return M
