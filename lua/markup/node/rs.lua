-- return
package.cpath = package.cpath
	.. ";/home/kawre/projects/markup.nvim/target/release/libmarkup_node.so"

return require("markup.node") -- require the Rust module
