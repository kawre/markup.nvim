local markup = require("markup.core")

---@class markup.Padding : markup.Text
---@field protected super markup.Text
local Padding = markup.Text:extend("markup.padding")

---@type table<integer, string>
local cache = {}

---@param n integer
function Padding:init(n)
	if not cache[n] then
		cache[n] = (" "):rep(n)
	end
	Padding.super.init(self, cache[n])
end

---@alias markup.Padding.constructor
---| fun(n: integer): markup.Padding
---| { static: markup.Text.static }
---| markup.Text.static

return Padding
