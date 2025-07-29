---@module 'mini.test'
---@module 'markup'

local helpers = dofile("tests/helpers.lua")
local m = require("markup")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local function mock_renderer()
	child.lua([[
	_G.renderer = {
		render = function() end,
		rerender = function() end,
	}

	_G.frame = nil
	local App = m.Component(function()
		return _G.frame
	end)

	_G.renderer.rootf = Markup.factory.fiber.root(App())
	]])
end

local function reconcile_frame(frame)
	child.lua(([[
		_G.frame = %s
		_G.renderer.rootf = Markup.reconciler(_G.renderer.rootf)
		_G.renderer.rootf.child:set_flags(2)
	]]):format(frame))
end

local function expect_tree(frame, opts)
	reconcile_frame(frame)

	child.lua([[
		local lines = Markup.devkit.visualizer.fiber(_G.renderer.rootf, { hl = false })
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	]])
	expect.reference_screenshot(child.get_screenshot(), nil, opts)

	child.lua([[
		local lines = Markup.devkit.visualizer.node(_G.renderer.rootf.state_node, { hl = false })
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	]])
	expect.reference_screenshot(child.get_screenshot(), nil, opts)

	child.lua([[
		-- local lines = Markup.devkit.visualizer.node(_G.renderer.rootf.state_node, { hl = false })
		local lines = {  }
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		]])
	expect.reference_screenshot(child.get_screenshot(), nil, opts)
end

local function expect_visual_tree(before, after, opts)
	before = helpers.serialize(before)
	after = helpers.serialize(after)

	mock_renderer()
	expect_tree(before, opts)
	expect_tree(after, opts)
	expect_tree(before, opts)
end

local T = new_set({
	hooks = {
		pre_once = function()
			-- child.restart({ "-u", "scripts/minimal_init.lua" })
			m = helpers.mock_markup()
			child.start({ "-u", "scripts/minimal_init.lua" })
			child.lua([[m = require('markup')]])
		end,
		pre_case = function()
			child.lua([[Markup.util.reset_id()]])
			child.o.lines, child.o.columns = 15, 60
		end,
		post_once = function()
			child.stop()
			m = require("markup")
		end,
	},
})

T["reconciliation"] = new_set()

T["reconciliation"]["text update"] = function()
	local before = m.inline(5)
	local after = m.inline(6)

	expect_visual_tree(before, after)
end

T["reconciliation"]["insertion mid"] = function()
	local before = m.block({
		m.inline({ "im count: " .. 4 }),
		"i'm overriding",
	})

	local after = m.block({
		m.inline({ "im count: " .. 5 }),
		{ m.inline(10000), "2" },
		"i'm overriding",
	})

	expect_visual_tree(before, after)
end

-- TT["reconciliation"]['fiber']["`For` utility"] = function()
-- 	local before = markup.block({
-- 		markup.inline({ "im count: " .. 3 }),
-- 		markup.For({ 5, 5 }, function(v)
-- 			return v + 5
-- 		end),
-- 		"i'm overriding",
-- 	})
--
-- 	local after = markup.block({
-- 		markup.inline({ "im count: " .. 4 }),
-- 		{ markup.inline(10000), "2" },
-- 		markup.For({ 5, 5 }, function(v)
-- 			return v + 5
-- 		end),
-- 		"i'm overriding",
-- 	})
--
-- 	expect_visual_tree(before, after)
-- end

T["reconciliation"]["conversion from single text element to normal"] = function()
	local before = m.block("text")

	local after = m.block({
		m.inline({ "im count: " .. 4 }),
		"i'm overriding",
	})

	expect_visual_tree(before, after)
end

T["reconciliation"]["handles nil returns"] = function()
	local before = nil
	local after = "text"
	expect_visual_tree(before, after)
end

T["reconciliation"]["handles element conversion from nil to single text"] = function()
	local before = m.block()
	local after = m.block("text")
	expect_visual_tree(before, after)
end

T["reconciliation"]["handles new fragment elements"] = function()
	local before = {}
	local after = { 5 }
	expect_visual_tree(before, after)
end

T["reconciliation"]["removes empty values like nil and false"] = function()
	local before = m.inline({ 5, false, nil, 5 })
	local after = m.inline("text")
	expect_visual_tree(before, after)
end

T["reconciliation"]["removes raw empty values like nil and false"] = function()
	local before = false
	local after = "text"
	expect_visual_tree(before, after)
end

T["reconciliation"]["handles empty elements"] = function()
	local before = {
		m.inline(5),
		m.inline(),
		m.inline(6),
	}
	local after = {}

	expect_visual_tree(before, after)
end

T["reconciliation"]["skips empty fragments"] = function()
	local before = {
		m.inline(5),
	}
	local after = {
		m.inline(5),
		{},
	}

	expect_visual_tree(before, after)
end

T["reconciliation"]["uses keys to reorder elements"] = function()
	local before = {
		m.inline({ "A", key = "A" }),
		"123",
		m.inline({ "B", key = "B" }),
		m.inline({ "C", key = "C" }),
	}
	local after = {
		m.inline({ "B", key = "B" }),
		m.inline({ "A", key = "A" }),
		"123",
		m.inline({ "C", key = "C" }),
	}

	expect_visual_tree(before, after)
end

T["reconciliation"]["keeps the not valid elements hidden after re-render"] = function()
	local before = {
		m.inline(),
		m.inline(5),
		m.inline(),
		m.inline(5),
		m.inline(),
	}
	local after = {
		m.inline(),
		m.inline(5),
		m.inline(),
		m.inline(5),
		m.inline(),
		"test",
		m.block("block"),
		{
			m.block("block"),
		},
		m.block("block"),
	}

	expect_visual_tree(before, after)
	expect_visual_tree("node", before, after)
end

T["reconciliation"]["table within table"] = function()
	local before = {
		m.inline(5),
		m.inline(),
		"test",
		m.block("block"),
	}
	local after = {
		m.inline(5),
		m.inline(),
		"test",
		m.block("block"),
		{
			m.block("block"),
		},
		m.block("block"),
	}

	expect_visual_tree(before, after)
end

T["reconciliation"]["remove wrapping fragments"] = function()
	local before = m.Fragment(5)
	local after = m.Fragment(m.inline("100"))

	expect_visual_tree(before, after)
end

T["reconciliation"]["keep wrapping fragments with key"] = function()
	local before = m.Fragment({ 5, key = "A" })
	local after = m.Fragment({ m.inline("100"), key = "A" })

	expect_visual_tree(before, after)
end

T["reconciliation"]["updates text node inplace"] = function()
	local before = { 5 }
	local after = { "1000" }

	expect_visual_tree(before, after)
end

T["reconciliation"]["deletes empty node"] = function()
	local before = { 5 }
	local after = {}

	expect_visual_tree(before, after)
end

T["reconciliation"]["reorders nodes by keys"] = function()
	local before = {
		m.inline({ "A", key = "A" }),
		"123",
		m.inline({ "B", key = "B" }),
		m.inline({ "C", key = "C" }),
	}

	local after = {
		m.inline({ "B", key = "B" }),
		m.inline({ "A", key = "A" }),
		"123",
		m.inline({ "C", key = "C" }),
	}

	expect_visual_tree(before, after)
end

T["reconciliation"]["removes child nodes"] = function()
	local before = m.block({
		m.inline(500),
		m.block(501),
	})

	local after = m.block({
		m.inline(500),
	})

	expect_visual_tree(before, after)
end

T["reconciliation"]["handles insertion|deletion mid as fragment"] = function()
	local before = m.block({
		m.inline({ "im count: " .. 4 }),
		"i'm overriding",
	})

	local after = m.block({
		m.inline({ "im count: " .. 5 }),
		{ m.inline(10000), "2" },
		"i'm overriding",
	})

	expect_visual_tree(before, after)
end

return T
