local core = require("markup.core")
local ui = require("markup.ui")

---@class markup
-- Object
---@field Object markup.Object.constructor
-- Text
---@field Node markup.Node.constructor
---@field Text markup.Text.constructor
---@field Pad markup.Padding.constructor
-- Element
---@field Element markup.Element.constructor
-- Inline
---@field Inline markup.Inline.constructor
---@field Anchor markup.Inline.constructor
---@field Code markup.Inline.constructor
---@field Italic markup.Inline.constructor
---@field Mark markup.Inline.constructor
---@field Strike markup.Inline.constructor
---@field Strong markup.Inline.constructor
---@field Sub markup.Inline.constructor
---@field Sup markup.Inline.constructor
---@field Underline markup.Inline.constructor
-- Block
---@field Block markup.Block.constructor
---@field Box markup.Box.constructor
---@field List markup.List.constructor
---@field OrderedList markup.List.constructor
---@field ListItem markup.Block.constructor
-- Window
---@field Window markup.Window.constructor
---@field Renderer markup.Renderer.constructor
---@field RendererLine markup.Line.constructor
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
