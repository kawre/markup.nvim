---@module 'mini.test'
---@module 'markup'

local markup = require("markup")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local Factory = require("markup.core.factory.fiber")

local T = new_set()

T["factory"] = new_set()

T["factory"]["create()"] = new_set({
	parametrize = {
		{ "inline", "5" },
		{ "block", 5 },
	},
})

T["factory"]["create()"]["works"] = function(tag, props)
	local f = Factory.create(tag, props)

	eq(f.pending_props, props)
	eq(f.tag, tag)
	eq(f.flags.flags, 0)
	eq(f.index, 1)
end

T["factory"]["create_from_element()"] = new_set({
	parametrize = {
		{ markup.inline(5), "element" },
		{ markup.something(5), "element" },
		{ markup.block(5), "element" },
		{ markup.Component(function() end)(), "function" },
		{ markup.Fragment(markup.inline(5)), "fragment" },
	},
})

T["factory"]["create_from_element()"]["works"] = function(element, expected)
	local f = Factory.create_from_element(element)

	eq(f.tag, expected)
end

T["factory"]["create_from_type_and_props()"] = new_set({
	parametrize = {
		{ "inline", "5", "element" },
		{ "block", 5, "element" },
		{ "fragment", 5, "fragment" },
		{ "anything", 5, "element" },
		{ function() end, 5, "function" },
	},
})

T["factory"]["create_from_type_and_props()"]["works"] = function(type, props, expected)
	local f = Factory.create_from_type_and_props(type, props)

	eq(f.tag, expected)
end

return T
