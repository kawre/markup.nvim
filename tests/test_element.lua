---@module 'mini.test'
---@module 'markup'

local markup = require("markup")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set()

T["factory"] = new_set()

T["factory"]["primitive"] = new_set({
	parametrize = { { 5 }, { "5" } },
})

T["factory"]["primitive"]["creates element with single value"] = function(text)
	local e = markup.block(text)
	local e2 = markup.block({ children = text })

	eq(e, e2)
	eq(e.props.children, text)
	eq(e.type, "block")
end

T["factory"]["primitive"]["creates element with values array"] = function(text)
	local e = markup.block({ text, text })
	local e2 = markup.block({ children = { text, text } })

	eq(e, e2)
	eq(e.props.children, { text, text })
	eq(e.type, "block")
end

T["factory"]["primitive"]["nested"] = new_set({
	parametrize = { { markup.inline }, { markup.block } },
})

T["factory"]["primitive"]["nested"]["creates element with single element"] = function(
	param,
	element
)
	local e = markup.block(element(param))
	local e2 = markup.block({ children = element(param) })

	eq(e, e2)
	eq(e.props.children.props.children, param) ---@diagnostic disable-line: undefined-field
	eq(e.type, "block")
end

T["factory"]["primitive"]["nested"]["creates element with multiple nested elements"] = function(
	param,
	element
)
	local e = markup.block({ element(param), element(param) })
	local e2 = markup.block({ children = { element(param), element(param) } })

	eq(e, e2)
	local children = vim.tbl_map(function(v)
		return v.props.children
	end, e.props.children)
	eq(children, { param, param })
	eq(e.type, "block")
end

return T
