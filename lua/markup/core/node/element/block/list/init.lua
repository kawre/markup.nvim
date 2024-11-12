local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.List.props : markup.Element.props
---@field ordered boolean
---@field marker string
---@field ordered_counter integer

---@class markup.List : markup.Block
---@field protected super markup.Block
---@field protected _ markup.List.props
local List = markup.Block:extend("markup.list") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Constructor
---------------------------------

function List:init(...)
    self:_extend_default_props({
        ordered = false,
        marker = " • ",
        ordered_counter = 1,
        type = "element-list",
    })
    List.super.init(self, ...)
end

---------------------------------
---- Methods
---------------------------------

function List:before_render()
    self._.ordered_counter = 1
end

function List:item_marker(inc)
    local marker = self._.marker

    if self._.ordered then
        marker = self._.ordered_counter .. ". "
        if inc then
            self._.ordered_counter = self._.ordered_counter + 1
        end
    end

    return marker
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.List.constructor.props : markup.Block.constructor.props
---@field ordered? boolean ordered or unordered list
---@field marker? string ordered list marker

---@alias markup.List.constructor fun(props?: string|markup.Node|markup.List.constructor.props, style?: markup.Element.style.props): markup.Element

---@type markup.List.constructor
local MarkupList = List ---@diagnostic disable-line: assign-type-mismatch

return MarkupList
