---@module 'mini.test'
---@module 'markup'

local helpers = dofile("tests/helpers.lua")
local markup = require("markup")
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
	local App = markup.Component(function()
		return _G.frame
	end)

	_G.renderer.rootf = Markup.factory.fiber.root(App())
	_G.reconciler = Markup.reconciler(renderer)
	]])
end

local function reconcile_frame(frame)
	child.lua(([[
		_G.frame = %s
		_G.reconciler:reconcile()
		_G.renderer.rootf.child.flags:set(2)
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
			markup = helpers.mock_markup()
			child.start({ "-u", "scripts/minimal_init.lua" })
			child.lua([[markup = require('markup')]])
		end,
		pre_case = function()
			child.o.lines, child.o.columns = 15, 60
		end,
		post_once = function()
			child.stop()
			markup = require("markup")
		end,
	},
})

T["reconciliation"] = new_set()

T["reconciliation"]["text update"] = function()
	local before = markup.inline(5)
	local after = markup.inline(6)

	expect_visual_tree(before, after)
end

T["reconciliation"]["insertion mid"] = function()
	local before = markup.block({
		markup.inline({ "im count: " .. 4 }),
		"i'm overriding",
	})

	local after = markup.block({
		markup.inline({ "im count: " .. 5 }),
		{ markup.inline(10000), "2" },
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
	local before = markup.block("text")

	local after = markup.block({
		markup.inline({ "im count: " .. 4 }),
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
	local before = markup.block()
	local after = markup.block("text")
	expect_visual_tree(before, after)
end

T["reconciliation"]["handles new fragment elements"] = function()
	local before = {}
	local after = { 5 }
	expect_visual_tree(before, after)
end

T["reconciliation"]["removes empty values like nil and false"] = function()
	local before = markup.inline({ 5, false, nil, 5 })
	local after = markup.inline("text")
	expect_visual_tree(before, after)
end

T["reconciliation"]["removes raw empty values like nil and false"] = function()
	local before = false
	local after = "text"
	expect_visual_tree(before, after)
end

T["reconciliation"]["handles empty elements"] = function()
	local before = {
		markup.inline(5),
		markup.inline(),
		markup.inline(6),
	}
	local after = {}

	expect_visual_tree(before, after)
end

T["reconciliation"]["skips empty fragments"] = function()
	local before = {
		markup.inline(5),
	}
	local after = {
		markup.inline(5),
		{},
	}

	expect_visual_tree(before, after)
end

T["reconciliation"]["uses keys to reorder elements"] = function()
	local before = {
		markup.inline({ "A", key = "A" }),
		"123",
		markup.inline({ "B", key = "B" }),
		markup.inline({ "C", key = "C" }),
	}
	local after = {
		markup.inline({ "B", key = "B" }),
		markup.inline({ "A", key = "A" }),
		"123",
		markup.inline({ "C", key = "C" }),
	}

	expect_visual_tree(before, after)
end

T["reconciliation"]["keeps the not valid elements hidden after re-render"] = function()
	local before = {
		markup.inline(),
		markup.inline(5),
		markup.inline(),
		markup.inline(5),
		markup.inline(),
	}
	local after = {
		markup.inline(),
		markup.inline(5),
		markup.inline(),
		markup.inline(5),
		markup.inline(),
		"test",
		markup.block("block"),
		{
			markup.block("block"),
		},
		markup.block("block"),
	}

	expect_visual_tree(before, after)
	expect_visual_tree("node", before, after)
end

T["reconciliation"]["table within table"] = function()
	local before = {
		markup.inline(5),
		markup.inline(),
		"test",
		markup.block("block"),
	}
	local after = {
		markup.inline(5),
		markup.inline(),
		"test",
		markup.block("block"),
		{
			markup.block("block"),
		},
		markup.block("block"),
	}

	expect_visual_tree(before, after)
end

T["reconciliation"]["remove wrapping fragments"] = function()
	local before = markup.Fragment(5)
	local after = markup.Fragment(markup.inline("100"))

	expect_visual_tree(before, after)
end

T["reconciliation"]["keep wrapping fragments with key"] = function()
	local before = markup.Fragment({ 5, key = "A" })
	local after = markup.Fragment({ markup.inline("100"), key = "A" })

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
		markup.inline({ "A", key = "A" }),
		"123",
		markup.inline({ "B", key = "B" }),
		markup.inline({ "C", key = "C" }),
	}

	local after = {
		markup.inline({ "B", key = "B" }),
		markup.inline({ "A", key = "A" }),
		"123",
		markup.inline({ "C", key = "C" }),
	}

	expect_visual_tree(before, after)
end

T["reconciliation"]["removes child nodes"] = function()
	local before = markup.block({
		markup.inline(500),
		markup.block(501),
	})

	local after = markup.block({
		markup.inline(500),
	})

	expect_visual_tree(before, after)
end

T["reconciliation"]["handles insertion|deletion mid as fragment"] = function()
	local before = markup.block({
		markup.inline({ "im count: " .. 4 }),
		"i'm overriding",
	})

	local after = markup.block({
		markup.inline({ "im count: " .. 5 }),
		{ markup.inline(10000), "2" },
		"i'm overriding",
	})

	expect_visual_tree(before, after)
end

return T
