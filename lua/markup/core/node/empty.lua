local markup = require("markup")

---@class markup.Empty: markup.Node
local Empty = markup.Node:extend("Empty")

function Empty:render() end

return Empty({ type = "nil" })
