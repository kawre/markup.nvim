local markup = require("markup")

---@class markup.Empty : markup.Node
local Empty = markup.Node:extend("Empty") ---@diagnostic disable-line: undefined-field

function Empty:render_node() end

function Empty:render() end

return Empty({ type = "nil" })
