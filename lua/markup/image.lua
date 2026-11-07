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

--- What shows images. Leave it unset to pick one, or set something with `set`
--- and `del` like `vim.ui.img`.
---@type markup.image.backend?
M.backend = nil

local image_nvim ---@type markup.image.backend|false|nil

--- image.nvim as a backend, for a Neovim without `vim.ui.img`. It reads files
--- rather than bytes, so each image is written to one first.
---@return markup.image.backend?
function M.from_image_nvim()
	local ok, api = pcall(require, "image")
	if not ok or type(api) ~= "table" or not api.from_file then
		return nil
	end

	local dir = vim.fn.tempname()
	local placed, count = {}, 0

	--- image.nvim counts screen cells from zero, `vim.ui.img` from one.
	local function geometry(opts)
		return { x = opts.col - 1, y = opts.row - 1, width = opts.width, height = opts.height }
	end

	local function file_for(data)
		vim.fn.mkdir(dir, "p")
		local path = ("%s/%s.png"):format(dir, vim.fn.sha256(data):sub(1, 16))
		if not vim.uv.fs_stat(path) then
			local file = assert(io.open(path, "wb"))
			file:write(data)
			file:close()
		end
		return path
	end

	return {
		set = function(data_or_id, opts)
			if type(data_or_id) == "number" then
				local image = placed[data_or_id]
				if image then
					image:render(geometry(opts))
				end
				return data_or_id
			end

			count = count + 1
			local where = geometry(opts)
			local made, image = pcall(api.from_file, file_for(data_or_id), vim.tbl_extend("force", where, {
				id = ("markup-%d"):format(count),
			}))
			if made and image then
				image:render(where)
				placed[count] = image
			end
			return count
		end,
		del = function(id)
			local image = placed[id]
			placed[id] = nil
			if image then
				image:clear()
			end
			return image ~= nil
		end,
	}
end

--- What Neovim itself has to show images, which only newer ones do.
---@return markup.image.backend?
function M.native()
	return vim.ui and vim.ui.img
end

--- The backend in use: the one set, `vim.ui.img` where Neovim has it, or
--- image.nvim when it is there. Looked for when first needed, so that a plugin
--- manager that loads image.nvim later still finds it.
---@return markup.image.backend?
function M.resolve()
	if M.backend then
		return M.backend
	end
	local native = M.native()
	if native then
		return native
	end
	if image_nvim == nil then
		image_nvim = M.from_image_nvim() or false
	end
	return image_nvim or nil
end

---@return boolean
function M.available()
	return M.resolve() ~= nil
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
