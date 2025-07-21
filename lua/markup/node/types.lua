---------------------------------
---- Node
---------------------------------

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

---@alias markup.Element.style vim.api.keyset.highlight|markup.Element.style.alias

---@alias markup.Element.type
---| "block"
---| "inline"
---| "flex"
---| "hflex"
---| "grid"
---| "anchor"

---@alias markup.Element.padding
---| integer
---| integer[]
---| {top?: integer, right?: integer, bottom?: integer, left?: integer}

---@alias markup.Element.margin markup.Element.padding

---@alias markup.Tree.icons.props {expand?: string, collapse?: string, indent?: string, indent_last?: string, indent_hor?: string}
---@alias markup.Tree.icons {expand: string, collapse: string, indent: string, indent_last: string, indent_hor: string}

---------------------------------
---- Box
---------------------------------

---@alias markup.Box.align "start"|"center"|"end"
---@alias markup.Box.justify "start"|"center"|"end"|"between"
---@alias markup.Box.spacing integer
