---@param conf snacks.picker.Config
local function pick(conf)
	local picker = require("snacks.picker")

	conf = vim.tbl_deep_extend("keep", conf, {
		layout = {
			preset = "default",
		},
		win = {
			preview = { minimal = true },
		},
		title = "dev tools",
		preview = "preview",
		format = function(item)
			local ret = {}
			vim.tbl_map(function(col)
				if type(col) == "table" then
					ret[#ret + 1] = col
				else
					ret[#ret + 1] = { col }
				end
			end, item.item.entry)
			return ret
		end,
	})

	picker.pick(conf)
end

local function tree_pick(value)
	local render = value.render
	local phase = value.phase

	local t = {
		["fiber-tree"] = "fiber_root",
		["node-tree"] = "node_root",
		["render-tree"] = "render_root",
	}

	pick({
		items = require("markup.devkit.picker." .. phase)(render[t[phase]]),
		title = phase,
	})
end

---@param render markup.Renderer.meta.render
local function render_pick(render)
	local items = {}

	local phases = {
		["fiber-tree"] = "Fiber Tree",
		["node-tree"] = "Node Tree",
		["render-tree"] = "Render Tree",
	}

	for phase, name in pairs(phases) do
		items[#items + 1] = {
			text = name,
			preview = {
				text = ("Show %s"):format(phase),
				ft = "lua",
			},
			-- preview = false,
			item = {
				entry = { { name } },
				value = {
					render = render,
					phase = phase,
				},
			},
		}
	end

	pick({
		items = items,
		confirm = function(p, item)
			p:close()
			tree_pick(item.item.value)
		end,
	})
end

---@param renderer markup.renderer
local function renders_pick(renderer)
	local items = {}
	for _, render in ipairs(renderer._meta.renders) do
		table.insert(items, {
			text = ("Render %s (winid: %s)"):format(render.index, renderer.id),
			preview = {
				text = vim.inspect(render, { depth = 2 }),
				ft = "lua",
			},
			item = {
				entry = { { "render" }, { " " }, { tostring(render.index) } },
				value = render,
			},
		})
	end

	pick({
		items = items,
		confirm = function(p, item)
			p:close()
			render_pick(item.item.value)
		end,
	})
end

return function()
	local items = {}

	---@param renderer markup.renderer
	for _, renderer in ipairs(Markup.renderers) do
		items[#items + 1] = {
			text = ("Renderer (winid: %s)"):format(renderer.id),
			preview = {
				text = vim.inspect(renderer, { depth = 2 }),
				ft = "lua",
			},
			item = {
				entry = { { "renderer" }, { " " } },
				value = renderer,
			},
		}
	end

	pick({
		items = items,
		confirm = function(p, item)
			p:close()
			renders_pick(item.item.value)
		end,
	})
end
