local markup = require("markup")
local log = require("markup.logger")
local ts = vim.treesitter

---@class markup.Parser.Html : markup.Parser
local Html = markup.Parser:extend("markup.parser.html") ---@diagnostic disable-line: undefined-field

Html.entities = {
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

Html.tag_map = {
	["a"] = markup.Anchor,
	["sub"] = markup.Sub,
	["sup"] = markup.Sup,
	["div"] = markup.Block,
	["p"] = markup.Block,
	["code"] = markup.Code,
	["pre"] = markup.Pre,
	["blockquote"] = markup.Block,
	["ul"] = markup.List,
	["ol"] = markup.OList,
	["li"] = markup.ListItem,
	["strong"] = markup.Strong,
	["s"] = markup.Strong,
}

function Html:init(...)
	Html.super.init(self, ...)

	-- -- self.text = self.text:gsub("\n", "&lcnl;\n")
	self.text = self.text:gsub(" <", "&nbsp;<")
	self.text = self.text:gsub("> ", ">&nbsp;")
	-- self.text = self.text:gsub("([^<>]*)", function(segment)
	-- 	-- Only process segments outside of <tags>
	-- 	if not segment:find("^<.*>$") then
	-- 		return segment:gsub(" ", "&nbsp;")
	-- 	end
	-- 	return segment
	-- end)
	log.debug(self.text)
end

---@param node TSNode
function Html:tag_name(node)
	local tag = node:child(0):child(1)
	return self:get_node_text(tag)
end

function Html:entity_mapper(node)
	local text = self:get_node_text(node)
	return markup.Inline(self.entities[text] or text)
end

function Html:tag_mapper(node)
	if node:type() == "element" then
		local tag = self:tag_name(node)
		return self.tag_map[tag] or markup.Inline
	else
		return markup.Inline
	end
end

function Html:parse_node(node)
	local children = {}

	for child in node:iter_children() do
		local ntype = child:type()
		local x

		if ntype == "text" then
			x = markup.Inline(self:get_node_text(child))
		elseif ntype == "entity" then
			x = self:entity_mapper(child)
		else
			x = self:parse_node(child)
		end

		table.insert(children, x)
	end

	if not vim.tbl_isempty(children) then
		local elem = self:tag_mapper(node)(children)
		return elem
	end
end

return Html
