local markup = require("markup")

---@class markup.Renderer.State : markup.Object
local State = markup.Object("MarkupRendererState")

function State:init(props)
    self._ = props
end

---@class markup.Renderer.State.constructor.props
---@field parent_element markup.Element
---@field children markup.Element[]
---@field style markup.Element.style

---@alias markup.Renderer.State.constructor fun(props: markup.Renderer.State.constructor.props): markup.Renderer.State

---@type markup.Renderer.State.constructor
local MarkupRendererState = State

return MarkupRendererState
