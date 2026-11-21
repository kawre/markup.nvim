-- Loaded only by the browser-suite runner. Delay instrumentation until a test
-- actually loads View, so module-loading tests run in the same environment.
local dir = vim.env.MARKUP_BROWSER_DIR
local log = dir .. "/" .. vim.fn.getpid() .. ".jsonl"
local seen = {}
local function record(frame)
	frame.case = vim.env.MARKUP_BROWSER_CASE or "test setup"
	local line = vim.json.encode(frame)
	local key = vim.fn.sha256(line)
	if not seen[key] then
		seen[key] = true
		assert(vim.fn.writefile({ line }, log, "a") == 0)
	end
end

package.preload["markup.view"] = function()
	local View = dofile("lua/markup/view/init.lua")
	local ref = dofile("tests/browser/reference.lua")
	local new, apply, commit = View.new, View.apply, View.commit
	local buffer_owner = setmetatable({}, { __mode = "v" })
	function View:new(...)
		new(self, ...)
		-- Record authored style values, never the resolved layout dimensions.
		local styles, text, cmds = {}, {}, self.commands
		self.browser_text = text
		self.browser_styles = styles
		for _, method in ipairs({ "set_style", "set_tracks", "set_border" }) do
			local original = cmds[method]
			cmds[method] = function(commands, id, name, value, ...)
				original(commands, id, name, value, ...)
				if method == "set_border" then
					local preset = type(name) == "table" and name
						or require("markup.view.protocol").borders[name]
					name, value =
						"border_sides",
						value or preset.sides or { "top", "right", "bottom", "left" }
				end
				if name ~= "hl" and name ~= "interactive" and name ~= "snap" then
					styles[id] = styles[id] or {}
					styles[id][name] = value
				end
			end
		end
		for _, method in ipairs({ "create_text", "set_text" }) do
			local original = cmds[method]
			cmds[method] = function(commands, id, value)
				original(commands, id, value)
				text[id] = value
			end
		end
		local resize = cmds.resize
		self.browser_width = self.laid_width
		cmds.resize = function(commands, width)
			resize(commands, width)
			self.browser_width = width
		end
	end

	function View:commit()
		local previous = self.browser_committing
		self.browser_committing = true
		local ok, err = pcall(commit, self)
		self.browser_committing = previous
		if not ok then
			error(err, 0)
		end
	end

	function View:apply(patches)
		local changed = apply(self, patches)
		local buf = self.win.buf
		if #patches > 0 and buf and vim.api.nvim_buf_is_valid(buf) then
			buffer_owner[buf] = self
		end
		if
			self.browser_committing
			and self.browser_styles
			and self.win:valid()
			and (self.stats.commands > 0 or changed > 0)
		then
			local ok, message = pcall(function()
				local boxes, tree =
					ref.snapshot(self.engine, self.browser_styles, self.browser_text)
				local profile = { check_text = buffer_owner[buf] == self }
				local rendered, html = pcall(ref.html, tree, profile)
				if not rendered then
					if not ref.unsupported(html) then
						error(html)
					end
					record({ skip = tostring(html):match("unsupported: (.*)") })
					return
				end
				record({
					html = html,
					width = self.browser_width,
					boxes = boxes,
					lines = profile.check_text
						and vim.api.nvim_buf_get_lines(self.win.buf, 0, -1, false),
				})
			end)
			if not ok then
				record({ error = tostring(message) })
			end
		end
		return changed
	end
	return View
end
