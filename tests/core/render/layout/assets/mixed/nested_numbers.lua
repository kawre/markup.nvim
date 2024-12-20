---@diagnostic disable
local markup = require("markup")

local content = {
	markup.Block(1),
	markup.Inline(2),
	markup.Block({
		children = {
			markup.Inline(3),
			markup.Inline(4),
			markup.Block(5),
			markup.Block(5),
			markup.Inline(4),
			markup.Inline(4),
		},
	}),
	markup.Block({
		markup.Block(5),
		markup.Inline(4),
		markup.Inline(4),
		markup.Block({
			markup.Block(5),
			markup.Inline(4),
			markup.Inline(4),
		}),
	}),
	markup.Inline(4),
}
