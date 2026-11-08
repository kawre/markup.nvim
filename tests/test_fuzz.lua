---@module 'mini.test'

--- Property tests over random UIs. Each seed builds a random tree out of every
--- construct markup has, then writes random values to the signals it reads.
--- After every write the patched buffer must be what a brand new view of the
--- same signals draws: the same lines, highlights and number of engine nodes,
--- with as many effects, memos and scopes alive, and unmounting must leave
--- nothing behind.
---
--- A failure is shrunk before it is reported: the smallest tree and fewest
--- writes that still break, with the knobs they start from.
---
--- More seeds: `FUZZ_SEEDS=500 FUZZ_STEPS=100 make test_file FILE=tests/test_fuzz.lua`

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local SEEDS = tonumber(vim.env.FUZZ_SEEDS) or 40
local STEPS = tonumber(vim.env.FUZZ_STEPS) or 40

local function range(from, count)
	local list = {}
	for i = 1, count do
		list[i] = { from + i - 1 }
	end
	return list
end

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 20, 60
			child.lua([[
				m = require("markup")
				reactive = require("markup.reactive")
				F = dofile("tests/helpers/fuzz.lua")
				F.capture()
				Markup.animate.enabled = false
				win = Markup.window({ position = "current", show = false, minimal = false })
				win.buf = vim.api.nvim_get_current_buf()
				win:show()
				view = Markup.view(win)
			]])
		end,
		post_once = function()
			child.stop()
		end,
	},
})

--- Plays `steps` random writes on the UI of `seed`, returning the first broken
--- property, shrunk, or nil.
local function play(seed, steps, opts)
	child.lua(
		[[
		local seed, steps, opts = ...
		failure = nil
		local world = F.world(F.rng(seed), opts)
		local width = vim.api.nvim_win_get_width(win.win)
		local base = F.live()

		local function check()
			if #F.errors > 0 then
				return "reported " .. F.errors[1]
			end
			local mine, now = F.snapshot(view), F.live()
			local fresh, alive = F.fresh(view, world.build)
			local difference = F.difference(mine, fresh)
			if difference then
				return difference
			end
			for _, kind in ipairs({ "effects", "memos", "scopes" }) do
				if now[kind] - base[kind] ~= alive[kind] then
					return ("%d %s alive, a fresh render keeps %d"):format(now[kind] - base[kind], kind, alive[kind])
				end
			end
		end

		local ok, err = pcall(function()
			view:render(world.build())
			F.settle()
			for step = 0, steps do
				if step > 0 then
					world.mutate()
					F.settle()
				end
				local broken = check()
				if broken then
					return broken
				end
			end
			view:unmount()
			F.settle()
			local after = F.live()
			for _, kind in ipairs({ "effects", "memos", "scopes" }) do
				if after[kind] ~= base[kind] then
					return ("%d %s left after unmount"):format(after[kind] - base[kind], kind)
				end
			end
			if view.engine:node_count() ~= 1 then
				return ("%d engine nodes left after unmount"):format(view.engine:node_count())
			end
		end)
		local broken = ok and err or (not ok and ("error " .. tostring(err))) or nil
		if broken then
			pcall(view.destroy, view)
			F.settle()
			local writes, shrunk = F.shrink(world, world.writes, width)
			failure = ("seed %d, after %d writes: %s\n"):format(seed, #world.writes, broken)
				.. (shrunk and ("shrunk to: " .. F.report(world, writes, shrunk)) or "(does not replay on its own)")
		end
	]],
		{ seed, steps, opts or vim.empty_dict() }
	)
	return child.lua_get("failure")
end

T["updates match a fresh render"] = new_set({ parametrize = range(1, SEEDS) })

T["updates match a fresh render"]["seed"] = function(seed)
	eq(play(seed, STEPS), vim.NIL)
end

T["resizes match a fresh render"] = new_set({ parametrize = range(2001, math.ceil(SEEDS / 2)) })

T["resizes match a fresh render"]["seed"] = function(seed)
	eq(play(seed, STEPS, { resize = true }), vim.NIL)
end

T["deep trees match a fresh render"] = new_set({ parametrize = range(1001, math.ceil(SEEDS / 4)) })

T["deep trees match a fresh render"]["seed"] = function(seed)
	eq(play(seed, math.ceil(STEPS / 2), { depth = 7 }), vim.NIL)
end

return T
