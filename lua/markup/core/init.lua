---@class markup.core
---@field create_engine fun(width: integer): markup.core.engine

---@class markup.core.engine
---@field commit fun(self: markup.core.engine, ops: any[], len: integer): table
---@field node_at fun(self: markup.core.engine, row: integer, col: integer): integer?
---@field node_count fun(self: markup.core.engine): integer

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
