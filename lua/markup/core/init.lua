---@class markup.core
---@field create_engine fun(width: integer): markup.core.engine

---@class markup.core.engine
---@field commit fun(self: markup.core.engine, ops: any[], len: integer): table
---@field node_at fun(self: markup.core.engine, row: integer, col: integer): integer?
---@field node_count fun(self: markup.core.engine): integer
---@field reset_frame fun(self: markup.core.engine)
---@field snap fun(self: markup.core.engine, from_row: integer, from_col: integer, row: integer, col: integer): integer?, integer?
---@field path_at fun(self: markup.core.engine, row: integer, col: integer): integer[]
---@field describe fun(self: markup.core.engine, id: integer): markup.core.node
---@field children fun(self: markup.core.engine, id: integer, offset: integer, limit: integer, flatten: boolean): markup.core.node[]
---@field child_position fun(self: markup.core.engine, id: integer, flatten: boolean): integer?

---@class markup.core.node
---@field id integer
---@field parent? integer
---@field display string
---@field text? string
---@field children integer
---@field x? integer
---@field y? integer
---@field outer_width? integer
---@field outer_height? integer
---@field content_width integer
---@field content_height integer
---@field margin integer[]
---@field padding integer[]
---@field width string
---@field height string
---@field spacing integer
---@field reverse boolean
---@field hl integer
---@field interactive boolean
---@field dirty boolean
---@field position string

--- @return string
local function get_lib_extension()
	if jit.os:lower() == "mac" or jit.os:lower() == "osx" then
		return ".dylib"
	end
	if jit.os:lower() == "windows" then
		return ".dll"
	end
	return ".so"
end

package.cpath = package.cpath
	.. ";"
	.. debug.getinfo(1).source:match("@?(.*/)")
	.. "../../../target/release/lib?"
	.. get_lib_extension()
	.. ";"
	.. debug.getinfo(1).source:match("@?(.*/)")
	.. "../../../target/release/?"
	.. get_lib_extension()

return require("markup_core")
