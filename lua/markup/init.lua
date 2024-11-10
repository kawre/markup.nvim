local core = require("markup.core")
local ui = require("markup.ui")

---@class markup
-- Object
---@field Object markup.Object.constructor
-- Text
---@field Node markup.Node.constructor
---@field Text markup.Text.constructor
---@field Pad markup.Padding.constructor
-- Line
---@field Line markup.Line.constructor
-- Element
---@field Element markup.Element.constructor
---@field Inline markup.Inline.constructor
---@field Block markup.Block.constructor
---@field Box markup.Box.constructor
-- Window
---@field Window markup.Window.constructor
---@field Renderer markup.Renderer.constructor
-- TabPage
---@field TabPage markup.TabPage.constructor
local markup = {}

---@private
markup.lookups = {}
---@private
markup.modules = { core, ui }

---@param lookups table<string, string>
function markup.register(lookups)
    for name, path in pairs(lookups) do
        markup.lookups[name] = path
    end
end

for _, module in ipairs(markup.modules) do
    markup.register(module.lookups)
end

return setmetatable(markup, {
    __index = function(t, k)
        if t.lookups[k] then
            return require(t.lookups[k])
        end
    end,
})
