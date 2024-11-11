---------------------------------
---- Node
---------------------------------

---@alias markup.Node.type "text"|"element"|"element-list"

---------------------------------
---- Element
---------------------------------

---@alias markup.Element.content string|markup.Node|(string|markup.Node)[]

---@alias markup.Element.display "inline"|"block"|"box"|"grid"

---@class markup.Element.style.alias
---@field color? string fg
---@field strike? string strikethrough

---@alias markup.Element.style vim.api.keyset.highlight|markup.Element.style.alias

---@alias markup.Element.type
---|"block"
---|"inline"

---@alias markup.Element.padding
---|integer
---|integer[]
---|{top?: integer, right?: integer, bottom?: integer, left?: integer}

---@alias markup.Element.margin markup.Element.padding

---------------------------------
---- Box
---------------------------------

---@alias markup.Box.align "start"|"center"|"end"
---@alias markup.Box.spacing integer
