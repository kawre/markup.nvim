---------------------------------
---- Node
---------------------------------

---@alias markup.Node.type "text"|"element"|"element-list"

---------------------------------
---- Element
---------------------------------

---@alias markup.Element.content string|markup.Node|(string|markup.Node)[]

---@alias markup.Element.display "inline"|"block"

---@class markup.Element.style.alias
---@field color? string
---@field strike? string

---@alias markup.Element.style vim.api.keyset.highlight|markup.Element.style.alias

---@alias markup.Element.type
---|"block"
---|"inline"

---------------------------------
---- Box
---------------------------------

---@alias markup.Box.align "start"|"center"|"end"
---@alias markup.Box.spacing integer
