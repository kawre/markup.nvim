---@module 'mini.test'
---@module 'markup'

for name, _ in pairs(package.loaded) do
	if name:match("^markup") then
		package.loaded[name] = nil
	end
end

local markup = require("markup")
local Reconciler = require("markup.core.reconciler")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local Factory = require("markup.core.factory.fiber")
local fiber_tree = require("markup.dev-tools.picker.fiber-tree")
local node_tree = require("markup.dev-tools.picker.node-tree")
local log = require("markup.logger")
local child = MiniTest.new_child_neovim()
Markup.is_dev = false

local function mock_renderer()
	local renderer = {}

	local frame
	local App = markup.Component(function()
		return frame
	end)

	renderer.render = function() end
	renderer.rerender = function() end
	renderer.root = {
		owner = renderer,
		current = Factory.create_root(App()),
	}

	local reconciler = Reconciler()

	renderer.frame = function(element)
		frame = element
		reconciler:reconcile(renderer.root)
		renderer.root.current.child.flags:set(2)
	end

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
	local _, tree = fiber_tree(renderer.root.current, true)

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
	before = before ~= vim.NIL and before
	after = after ~= vim.NIL and after

	local renderer = mock_renderer()

	renderer.frame(after)
	expect_fiber_tree(renderer, name, 1)

	renderer.frame(before)
	expect_fiber_tree(renderer, name, 2)

	renderer.frame(after)
	expect_fiber_tree(renderer, name, 3)
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
			"reorders nodes by keys",
		},
		{
			markup.block({
				markup.inline(500),
				markup.block(501),
			}),
			markup.block({
				markup.inline(500),
			}),
			"removes child nodes",
		},
		{
			markup.block({
				markup.inline({ "im count: " .. 4 }),
				"i'm overriding",
			}),
			markup.block({
				markup.inline({ "im count: " .. 5 }),
				{ markup.inline(10000), "2" },
				"i'm overriding",
			}),
			"handles insertion|deletion mid as fragment",
		},
	},
})

local function expect_node_tree(renderer, name, index)
	local _, tree = node_tree(renderer.root.current.state_node, true)

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
	before = before ~= vim.NIL and before
	after = after ~= vim.NIL and after

	local renderer = mock_renderer()

	renderer.frame(before)
	expect_node_tree(renderer, name, 1)

	renderer.frame(after)
	expect_node_tree(renderer, name, 2)

	renderer.frame(before)
	expect_node_tree(renderer, name, 3)
end

return T
