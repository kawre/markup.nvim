local m = require("markup")

return {
	{
		name = "nested empty boxes",
		width = 16,
		tree = m.flex({
			gap = 2,
			m.block({ width = 4, height = 3 }),
			m.block({ width = 6, m.block({ width = 3, height = 2 }) }),
		}),
	},
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
