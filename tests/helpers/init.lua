local markup = require("markup.core")

---@class markup-test.Helpers
local helpers = {}

function helpers.mock(node)
	local window = helpers.open_window()
	local renderer = helpers.bind_renderer(window)

	local function create_mock(props, lines, extmarks)
		renderer({ body = node(props) }):render()
		helpers.assert_lines(window, lines)
		if extmarks then
			helpers.assert_extmarks(window, extmarks)
		end
	end

	return setmetatable({
		cleanup = function()
			helpers.close_window(window)
		end,
		set_width = function(width)
			vim.api.nvim_win_set_width(window.winid, width)
		end,
		set_height = function(height)
			vim.api.nvim_win_set_height(window.winid, height)
		end,
	}, {
		__call = function(_, ...)
			create_mock(...)
		end,
	})
end

function helpers.open_window()
	local buf = vim.api.nvim_create_buf(false, true)

	local opts = {
		relative = "editor",
		width = 10,
		height = 20,
		row = 1,
		col = 1,
		style = "minimal",
	}

	local win = vim.api.nvim_open_win(buf, true, opts)

	return { bufnr = buf, winid = win }
end

function helpers.close_window(window)
	vim.api.nvim_buf_delete(window.bufnr, { force = true })
end

function helpers.bind_renderer(window)
	---@param opts markup.Element.constructor.props
	return function(opts)
		local renderer_opts = {
			winid = window.winid,
			bufnr = window.bufnr,
		}

		for key, value in pairs(opts) do
			renderer_opts[key] = value
		end

		return markup.Renderer(renderer_opts)
	end
end

function helpers.assert_lines(window, lines)
	local buf_lines = vim.api.nvim_buf_get_lines(window.bufnr, 0, -1, false)
	assert.are.same(lines, buf_lines)
end

function helpers.assert_extmarks(window, extmarks)
	local buf_extmarks = vim.api.nvim_buf_get_extmarks(window.bufnr, -1, 0, -1, {})
	assert.are.same(extmarks, buf_extmarks)
end

function helpers.read_lua_file(filename)
	local file, err = io.open(filename, "r") -- Open the file in read mode
	if not file then
		return nil, "Error opening file: " .. (err or "unknown error")
	end

	local content = file:read("*a") -- Read the entire content of the file
	file:close() -- Close the file
	return content
end

function helpers.mock_layout(assets_path, node_name)
	return function(content)
		local str = helpers.read_lua_file(assets_path .. content)
		return ([[
		frame = markup.Renderer()
		%s
		frame:render(markup.%s(content))
	]]):format(str, node_name)
	end
end

function helpers.render(content)
	return ([[
		frame = markup.Renderer()
		%s
		frame:render(content)
	]]):format(content)
end

return helpers
