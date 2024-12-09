local markup = require("markup.core")

---@class markup.Render.Object : markup.Object
local RenderObject = markup.Object("markup.render.object")

function RenderObject:init() end

function RenderObject:attach() end

function RenderObject:detach() end

function RenderObject:first_child() end

function RenderObject:last_child() end

function RenderObject:prev_sibling() end

function RenderObject:next_sibling() end

return RenderObject
