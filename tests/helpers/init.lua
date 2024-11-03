local markup = require("markup")

---@class markup-test.Helpers
local helpers = {}

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

return helpers
