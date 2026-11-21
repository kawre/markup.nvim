-- Compare after the original tests finish, outside animations and child-Neovim RPC.
local dir = assert(vim.env.MARKUP_BROWSER_DIR)
local ref = dofile("tests/browser/reference.lua")
local compared, failures = 0, 0
local skips, cases = {}, {}
local report = assert(io.open(".tests/browser-report.jsonl", "w"))
local function entry(data)
	report:write(vim.json.encode(data), "\n")
end
local unique, groups = {}, {}
local function skip(case, reason)
	cases[case].skipped = cases[case].skipped + 1
	entry({ case = case, status = "skipped", reason = reason })
	skips[reason] = (skips[reason] or 0) + 1
end
local function fail(case, reason, input)
	cases[case].failed = cases[case].failed + 1
	entry({ case = case, status = "failed", reason = reason, input = input })
	failures = failures + 1
	print(("FAIL %s: %s"):format(case, reason))
end
for _, path in ipairs(vim.fn.glob(dir .. "/*.cases", false, true)) do
	for case in io.lines(path) do
		cases[case] = { passed = 0, failed = 0, skipped = 0 }
	end
end
for _, path in ipairs(vim.fn.glob(dir .. "/*.jsonl", false, true)) do
	for line in io.lines(path) do
		local frame = vim.json.decode(line)
		if frame.error then
			fail(frame.case, frame.error)
		elseif frame.skip then
			skip(frame.case, frame.skip)
		else
			local key = vim.fn.sha256(
				tostring(frame.lines ~= false) .. ":" .. frame.width .. ":" .. frame.html
			)
			if not groups[key] then
				groups[key] = {}
				unique[#unique + 1] = {
					key = key,
					html = frame.html,
					width = frame.width,
					check_text = frame.lines ~= false,
				}
			end
			frame.html = nil
			table.insert(groups[key], frame)
		end
	end
end
for start = 1, #unique, 32 do
	local batch = vim.list_slice(unique, start, math.min(start + 31, #unique))
	local results = ref.batch(batch)
	assert(#results == #batch, "incomplete Chromium response")
	for i, input in ipairs(batch) do
		for _, frame in ipairs(groups[input.key]) do
			local ok, status, reason = pcall(ref.compare, results[i], frame.boxes, frame.lines)
			if not ok then
				fail(frame.case, status, input)
			elseif status == "unsupported" then
				skip(frame.case, reason)
			else
				compared = compared + 1
				cases[frame.case].passed = cases[frame.case].passed + 1
			end
		end
	end
end
ref.close()
for _, reason in ipairs(vim.fn.sort(vim.tbl_keys(skips))) do
	print(("SKIP %d: %s"):format(skips[reason], reason))
end
local without_view = 0
for case, counts in pairs(cases) do
	if counts.passed + counts.failed + counts.skipped == 0 then
		without_view = without_view + 1
	end
	entry({ case = case, status = "summary", frames = counts })
end
report:close()
print(
	("%d cases, %d without a captured view. Frames: %d passed, %d failed."):format(
		vim.tbl_count(cases),
		without_view,
		compared,
		failures
	)
)
assert(compared > 0, "no browser comparisons ran")
assert(failures == 0, "browser comparison failed")
