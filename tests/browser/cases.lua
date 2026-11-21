local m = require("markup")

return {
	{
		name = "block and inline",
		width = 12,
		tree = m.block({ m.inline("one "), m.inline("two"), m.block("three") }),
	},
	{ name = "word wrap", width = 5, tree = m.block("aa bb cc") },
	{
		name = "flex space between",
		width = 12,
		tree = m.flex({ justify = "between", m.block("a"), m.block("b") }),
	},
	{
		name = "grid columns and gaps",
		width = 12,
		tree = m.grid({
			columns = { 3, "1fr" },
			gap = { 1, 2 },
			m.block("a"),
			m.block("b"),
			m.block("c"),
			m.block("d"),
		}),
	},
}
