---------------------------------
---- Node
---------------------------------

---@alias markup.Node.type "text"|"element"|"element-list"|"nil"|"fragment"

---@alias markup.Text.content string|integer

---------------------------------
---- Element
---------------------------------

---@alias markup.Element.children.content integer|string|table
---@alias markup.Element.children markup.Element.children.content|markup.Element.children.content[]

---@alias markup.Element.display "inline"|"block"|"inline-block"|"flex"|"grid"

---@alias markup.Element.size {width: integer, height: integer}

---@class markup.Element.style.alias
---@field color? string `fg` alias
---@field strike? string `strikethrough` alias

---@alias markup.Element.style string|(vim.api.keyset.highlight|markup.Element.style.alias)

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
