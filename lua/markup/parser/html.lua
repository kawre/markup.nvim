local m = require("markup")

---@class markup.parser.html : markup.parser.impl
local M = {}

M.entities = {
	["&nbsp;"] = " ",
	["&quot;"] = "\"",
	["&#39;"] = "'",

	["&rarr;"] = "",
	["&larr;"] = "",
	["&uarr;"] = "↑",
	["&darr;"] = "↓",

	["&thinsp;"] = " ",
	["&hellip;"] = "…",
	["&lfloor;"] = "⌊",
	["&rfloor;"] = "⌋",
	["&amp;"] = "&",
	["&mdash;"] = "—",
	["&ndash;"] = "–",

	["&rdquo;"] = "”",
	["&rsquo;"] = "’",
	["&ldquo;"] = "“",
	["&lsquo;"] = "‘",

	["&lcpad;"] = "",
	["&lcnl;"] = "",
	["&lctab;"] = "\t",
	["&lcend;"] = "",
	["&lccode;"] = "`",

	-- Math symbols
	["&lt;"] = "<",
	["&gt;"] = ">",
	["&plus;"] = "+",
	["&plusmn;"] = "±",
	["&times;"] = "×",
	["&frasl;"] = "/",
	["&forall;"] = "∀",
	["&part;"] = "∂",
	["&exist;"] = "∃",
	["&empty;"] = "∅",
	["&nabla;"] = "∇",
	["&isin;"] = "∈",
	["&notin;"] = "∉",
	["&ni;"] = "∋",
	["&prod;"] = "∏",
	["&sum;"] = "∑",
	["&minus;"] = "−",
	["&lowast;"] = "∗",
	["&radic;"] = "√",
	["&prop;"] = "∝",
	["&infin;"] = "∞",
	["&ang;"] = "∠",
	["&and;"] = "∧",
	["&or;"] = "∨",
	["&cap;"] = "∩",
	["&cup;"] = "∪",
	["&int;"] = "∫",
	["&there4;"] = "∴",
	["&sim;"] = "∼",
	["&cong;"] = "≅",
	["&asymp;"] = "≈",
	["&ne;"] = "≠",
	["&equiv;"] = "≡",
	-- ["&le;"] = "<=",
	-- ["&ge;"] = ">=",
	["&le;"] = "≤",
	["&ge;"] = "≥",
	["&sub;"] = "⊂",
	["&sup;"] = "⊃",
	["&nsub;"] = "⊄",
	["&sube;"] = "⊆",
	["&supe;"] = "⊇",
	["&oplus;"] = "⊕",
	["&otimes;"] = "⊗",
	["&perp;"] = "⊥",
	["&sdot;"] = "⋅",
}

M.tag_map = {
	-- ["a"] = m.Anchor,
	-- ["sub"] = m.Sub,
	-- ["sup"] = m.Sup,
	["div"] = m.block,
	["p"] = m.block,
	-- ["code"] = m.Code,
	["pre"] = m.block,
	["blockquote"] = m.block,
	["ul"] = m.block,
	-- ["ol"] = m.OList,
	-- ["li"] = m.ListItem,
	-- ["strong"] = m.Strong,
	-- ["s"] = m.Strong,
}

function M.prepare_text(text)
	Markup.log(text)
	-- -- self.text = self.text:gsub("\n", "&lcnl;\n")
	text = text:gsub(" <", "&nbsp;<")
	text = text:gsub("> ", ">&nbsp;")

	return text
	-- self.text = self.text:gsub("([^<>]*)", function(segment)
	-- 	-- Only process segments outside of <tags>
	-- 	if not segment:find("^<.*>$") then
	-- 		return segment:gsub(" ", "&nbsp;")
	-- 	end
	-- 	return segment
	-- end)
end

---@param parser markup.parser
---@param node TSNode
function M.tag_name(parser, node)
	local tag = node:child(0):child(1)
	return parser:get_node_text(tag)
end

---@param parser markup.parser
function M.entity_mapper(parser, node)
	local text = parser:get_node_text(node)
	return m.inline(M.entities[text] or text)
end

function M.tag_mapper(parser, node)
	if node:type() == "element" then
		local tag = M.tag_name(parser, node)
		return M.tag_map[tag] or m.inline
	else
		return m.block
	end
end

---@param parser markup.parser
---@param node TSNode
function M.parse_node(parser, node)
	local children = {}

	for child in node:iter_children() do
		local ntype = child:type()
		local x

		if ntype == "text" then
			x = m.inline(parser:get_node_text(child))
		elseif ntype == "entity" then
			x = M.entity_mapper(parser, child)
		else
			x = M.parse_node(parser, child)
		end

		table.insert(children, x)
	end

	if not vim.tbl_isempty(children) then
		local elem = M.tag_mapper(parser, node)(children)
		return elem
	end
end

return M
