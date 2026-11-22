-- Compares the times of two builds, each run several times by scripts/bench.lua
-- with MARKUP_BENCH_OUT, as a Markdown table of medians.
--
-- nvim -l scripts/bench_compare.lua <dir of base results> <dir of head results>
--
-- Times on a shared machine wander by 10% and more, so this only reports: what
-- holds a change back is the counts, in `make bench_check`.

local base_dir, head_dir = arg[1], arg[2]
assert(base_dir and head_dir, "usage: bench_compare.lua <base dir> <head dir>")

--- Every result file in `dir`, decoded.
local function load(dir)
	local runs = {}
	for _, path in ipairs(vim.fn.glob(dir .. "/*.json", false, true)) do
		runs[#runs + 1] = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
	end
	return runs
end

local function median(values)
	if #values == 0 then
		return nil
	end
	table.sort(values)
	local middle = math.floor(#values / 2) + 1
	return #values % 2 == 1 and values[middle] or (values[middle - 1] + values[middle]) / 2
end

--- The median of `key` for `workload` over `runs`.
local function of(runs, workload, key)
	local values = {}
	for _, run in ipairs(runs) do
		local result = run[workload]
		if result and result[key] then
			values[#values + 1] = result[key]
		end
	end
	return median(values)
end

local base, head = load(base_dir), load(head_dir)
local names = {}
for _, run in ipairs(head) do
	for name in pairs(run) do
		names[name] = true
	end
end
names = vim.tbl_keys(names)
table.sort(names)

local function change(before, after)
	if not before or before == 0 then
		return ""
	end
	local percent = (after - before) / before * 100
	local mark = ""
	if percent >= 20 then
		mark = " 🔺"
	elseif percent <= -20 then
		mark = " 🟢"
	end
	return ("%+.0f%%%s"):format(percent, mark)
end

local function cell(value, format)
	return value and format:format(value) or "–"
end

local lines = {
	"### Stress test, base against head",
	"",
	("Medians of %d runs each, on one runner. Times only report; the counts in `make bench_check` are what fail."):format(
		math.min(#base, #head)
	),
	"",
	"| workload | ms/frame base | ms/frame head | change | layouts base | layouts head | change |",
	"|---|---:|---:|---:|---:|---:|---:|",
}
for _, name in ipairs(names) do
	local before, after = of(base, name, "frame_ms"), of(head, name, "frame_ms")
	local laid_before, laid_after = of(base, name, "layouts"), of(head, name, "layouts")
	lines[#lines + 1] = ("| %s | %s | %s | %s | %s | %s | %s |"):format(
		name,
		cell(before, "%.2f"),
		cell(after, "%.2f"),
		after and change(before, after) or "",
		cell(laid_before, "%d"),
		cell(laid_after, "%d"),
		laid_after and change(laid_before, laid_after) or ""
	)
end
if #base == 0 then
	lines[#lines + 1] = ""
	lines[#lines + 1] =
		"The base has no `scripts/bench.lua` stress mode to run, so only the head is shown."
end

io.stdout:write(table.concat(lines, "\n") .. "\n")
