local markup = require("markup")

---@class markup.Brake : markup.Node
local Brake = markup.Node:extend("markup.brake") ---@diagnostic disable-line: undefined-field

function Brake:init()
	Brake.super.init(self, { type = "brake" })
end

return Brake
