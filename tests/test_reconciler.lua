---@module 'mini.test'
---@module 'markup'

local markup = require("markup")
local Reconciler = require("markup.core.reconciler")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local Factory = require("markup.core.factory.fiber")
local fiber_tree = require("markup.dev-tools.picker.fiber-tree")
local node_tree = require("markup.dev-tools.picker.node-tree")
local log = require("markup.logger")
_Markup.is_dev = false

local function mock_renderer(el)
	local renderer = {
		rerender = function() end,
		render = function() end,
	}
	renderer.root = {
		owner = renderer,
		current = Factory.create_root(el),
	}
	return renderer
end

local T = new_set()

T["structure"] = new_set({
	parametrize = {
		{
			markup.inline(5),
			markup.inline(6),
			"text change",
		},
		{
			markup.block({
				markup.inline({ "im count: " .. 4 }),
				-- { markup.inline(10000), "2" },
				"i'm overriding",
			}),
			markup.block({
				markup.inline({ "im count: " .. 5 }),
				{ markup.inline(10000), "2" },
				"i'm overriding",
			}),
			"insertion mid",
		},
		{
			markup.block({
				markup.inline({ "im count: " .. 3 }),
				-- { markup.inline(10000), "2" },
				markup.For({ 5, 5 }, function(v)
					return v + 5
				end),
				"i'm overriding",
			}),
			markup.block({
				markup.inline({ "im count: " .. 4 }),
				{ markup.inline(10000), "2" },
				markup.For({ 5, 5 }, function(v)
					return v + 5
				end),
				"i'm overriding",
			}),
			"for utility",
		},
		{
			markup.block("text"),
			markup.block({
				markup.inline({ "im count: " .. 4 }),
				"i'm overriding",
			}),
			"conversion from single text element to normal",
		},
		{
			vim.NIL,
			"text",
			"handles nil returns",
		},
		{
			markup.block(),
			markup.block("text"),
			"handles element conversion from nil to single text",
		},
		{
			{},
			{ 5 },
			"handles new fragment elements",
		},
		{
			markup.inline({ 5, false, nil, 5 }),
			markup.inline("text"),
			"removes empty values like `nil` and `false`",
		},
		{
			false,
			"text",
			"removes raw empty values like `nil` and `false`",
		},
		{
			{
				markup.inline(5),
				markup.inline(),
				markup.inline(6),
			},
			{},
			"handles empty elements",
		},
		{
			{
				markup.inline(5),
			},
			{
				markup.inline(5),
				{},
			},
			"skips empty fragments",
		},
		{
			{
				markup.inline({ "A", key = "A" }),
				"123",
				markup.inline({ "B", key = "B" }),
				markup.inline({ "C", key = "C" }),
			},
			{
				markup.inline({ "B", key = "B" }),
				markup.inline({ "A", key = "A" }),
				"123",
				markup.inline({ "C", key = "C" }),
			},
			"uses keys to reorder elements",
		},
		{
			{
				markup.inline(),
				markup.inline(5),
				markup.inline(),
				markup.inline(5),
				markup.inline(),
			},
			{
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
			},
			"keeps the not valid elements hidden after re-render",
		},
		{
			{
				markup.inline(5),
				markup.inline(),
				"test",
				markup.block("block"),
			},
			{
				markup.inline(5),
				markup.inline(),
				"test",
				markup.block("block"),
				{
					markup.block("block"),
				},
				markup.block("block"),
			},
			"table within table",
		},
		{
			markup.Fragment(5),
			markup.Fragment(markup.inline("100")),
			"remove wrapping fragments",
		},
		{
			markup.Fragment({ 5, key = "A" }),
			markup.Fragment({ markup.inline("100"), key = "A" }),
			"keep wrapping fragments with key",
		},
	},
})

local function expect_fiber_tree(renderer, name, index)
	local _, tree = fiber_tree(renderer.root.current)

	local dir = "tests/screenshots/"
	local fname = ("expect_fiber_tree---%s(%s)"):format(name, index)
	local path = dir .. fname

	if vim.fn.filereadable(path) == 0 then
		vim.fn.mkdir(dir, "p")
		vim.fn.writefile(tree, path)
	end

	eq(vim.fn.readfile(path), tree)
end

T["structure"]["works"] = function(before, after, name)
	local reconciler = Reconciler()
	local renderer
	before = before ~= vim.NIL and before
	after = after ~= vim.NIL and after

	local render_index = 0
	local App = markup.Component(function()
		render_index = render_index + 1

		return render_index % 2 == 1 and after or before
	end)

	renderer = mock_renderer(App())
	for i = 1, 3 do
		reconciler:reconcile(renderer.root)
		expect_fiber_tree(renderer, name, i)
		renderer.root.current.child.flags:set(2)
	end
end

T["node tree"] = new_set({
	parametrize = {
		{
			{ 5 },
			{ "1000" },
			"updates text node inplace",
		},
		{
			{ 5 },
			{},
			"deletes empty node",
		},
	},
})

local function expect_node_tree(renderer, name, index)
	local _, tree = node_tree(renderer.root.current.state_node)

	local dir = "tests/screenshots/"
	local fname = ("expect_node_tree---%s(%s)"):format(name, index)
	local path = dir .. fname

	if vim.fn.filereadable(path) == 0 then
		vim.fn.mkdir(dir, "p")
		vim.fn.writefile(tree, path)
	end

	eq(vim.fn.readfile(path), tree)
end

T["node tree"]["works"] = function(before, after, name)
	local reconciler = Reconciler()
	local renderer
	before = before ~= vim.NIL and before
	after = after ~= vim.NIL and after

	local render_index = 0
	local App = markup.Component(function()
		render_index = render_index + 1

		-- log.info(render_index % 2 == 0 and after or before)
		return render_index % 2 == 0 and after or before
	end)

	renderer = mock_renderer(App())
	for i = 1, 3 do
		reconciler:reconcile(renderer.root)
		expect_node_tree(renderer, name, i)
		renderer.root.current.child.flags:set(2)
	end
end

return T
