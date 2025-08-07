---@class markup.rust
---@field create_dom fun(): markup.dom
---@field create_lsx fun(...): markup.element

---@class markup.dom
---@field create_element fun(dom: markup.dom, tag: string, props: table?, ...?): markup.node
---@field create_text_node fun(dom: markup.dom, text: table|string): markup.node

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
	.. ";/home/kawre/projects/markup.nvim/target/release/libmarkup"
	.. get_lib_extension()
-- .. ";"
-- .. debug.getinfo(1).source:match("@?(.*/)")
-- .. "../../../../../target/release/lib?"
-- .. get_lib_extension()
-- .. ";"
-- .. debug.getinfo(1).source:match("@?(.*/)")
-- .. "../../../../../target/release/?"
-- .. get_lib_extension()

return require("markup_module")
