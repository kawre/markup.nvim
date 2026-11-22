-- Runs every workload of the stress test (lua/markup/devkit/stress.lua) for a
-- fixed number of frames, with its timers and clocks moved by hand, and counts
-- the work each one does: nodes laid out, commands sent, lines written.
--
-- Counts are the same on every machine, so CI holds them to the ones in
-- scripts/bench_counts.json: more than `TOLERANCE` above them fails. Times are
-- printed too, but only compared between two builds on one machine.
--
-- nvim --headless -u NONE -i NONE -c "luafile scripts/bench.lua"
--
-- MARKUP_BENCH=check  fail when a count went up (`make bench_check`)
-- MARKUP_BENCH=update write the counts as the new baseline (`make bench_update`)
-- MARKUP_BENCH_OUT    also write the results to this JSON file
-- MARKUP_BENCH_ONLY   run only the workload of this name

-- Wide enough that neither column of the stress test squeezes the other.
vim.o.showtabline = 0
vim.o.columns, vim.o.lines = 220, 70
vim.opt.rtp:prepend(vim.fn.getcwd())

local FRAMES = 120
local FRAME_MS = 16
local TOLERANCE = 0.10
local BASELINE = "scripts/bench_counts.json"
-- What is held to the baseline. Times are not.
local COUNTS = { "layouts", "commands", "lines", "commits" }

local mode = vim.env.MARKUP_BENCH or "run"

require("markup").setup({})
local reactive = require("markup.reactive")
local stress = require("markup.devkit.stress")

-- Nothing moves on its own: the test's timers, its clock and every animation
-- wait for `advance`, so a run does the same work on any machine.
Markup.animate.manual = true
stress.manual = true

--- The workloads: each setting on its own at the `insane` preset's step, and
--- that preset whole.
local function workloads()
	local insane
	for _, preset in ipairs(stress.presets) do
		if preset.name == "insane" then
			insane = preset.steps
		end
	end
	local list = {}
	for _, setting in ipairs(stress.settings) do
		-- The rate is part of churn, not a workload of its own.
		if setting.key ~= "churn_rate" then
			list[#list + 1] = {
				name = setting.key,
				apply = function()
					stress.apply_preset("idle")
					for j, other in ipairs(stress.settings) do
						if
							other.key == setting.key
							or (setting.key == "churn" and other.key == "churn_rate")
						then
							stress.step(other.key, insane[j] - 1)
						end
					end
				end,
			}
		end
	end
	list[#list + 1] = {
		name = "insane",
		apply = function()
			stress.apply_preset("insane")
		end,
	}
	return list
end

local function now()
	return vim.uv.hrtime() / 1e6
end

---@return table<string, number>
local function run(workload)
	math.randomseed(1)
	local view = stress.open({ preset = "idle", inspector = false })
	reactive.flush()

	local result = { layouts = 0, commands = 0, lines = 0, commits = 0, engine = 0, apply = 0 }
	local counting = false
	view:on_commit(function()
		if counting then
			local stats = view.stats
			result.commits = result.commits + 1
			result.layouts = result.layouts + (stats.layouts or 0)
			result.commands = result.commands + stats.commands
			result.lines = result.lines + stats.lines
			result.engine = result.engine + stats.engine
			result.apply = result.apply + stats.apply
		end
	end)

	-- Mounting counts too: what a workload costs to show is part of it.
	counting = true
	local started = now()
	workload.apply()
	reactive.flush()
	result.mount_ms = now() - started

	started = now()
	for _ = 1, FRAMES do
		stress.advance(FRAME_MS)
		reactive.flush()
	end
	result.frame_ms = (now() - started) / FRAMES
	counting = false

	view:destroy()
	vim.cmd("silent! tabclose")
	reactive.flush()
	return result
end

local function read_json(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local text = file:read("*a")
	file:close()
	return vim.json.decode(text)
end

local function write_json(path, value)
	-- One workload a line, in a fixed order, so a change of baseline diffs well.
	local names = vim.tbl_keys(value)
	table.sort(names)
	local lines = {}
	for i, name in ipairs(names) do
		local keys = vim.tbl_keys(value[name])
		table.sort(keys)
		local fields = {}
		for _, key in ipairs(keys) do
			local number = value[name][key]
			local text = math.floor(number) == number and ("%d"):format(number)
				or ("%.3f"):format(number)
			fields[#fields + 1] = ("%q: %s"):format(key, text)
		end
		lines[#lines + 1] = ("  %q: { %s }%s"):format(
			name,
			table.concat(fields, ", "),
			i < #names and "," or ""
		)
	end
	local file = assert(io.open(path, "w"))
	file:write("{\n" .. table.concat(lines, "\n") .. "\n}\n")
	file:close()
end

local results, order = {}, {}
for _, workload in ipairs(workloads()) do
	if not vim.env.MARKUP_BENCH_ONLY or vim.env.MARKUP_BENCH_ONLY == workload.name then
		results[workload.name] = run(workload)
		order[#order + 1] = workload.name
	end
end

local out = {}
local function say(line)
	out[#out + 1] = line
end

say(
	("%-11s %9s %9s %8s %7s %10s %10s"):format(
		"workload",
		"layouts",
		"commands",
		"lines",
		"commits",
		"ms/frame",
		"mount ms"
	)
)
for _, name in ipairs(order) do
	local r = results[name]
	say(
		("%-11s %9d %9d %8d %7d %10.2f %10.2f"):format(
			name,
			r.layouts,
			r.commands,
			r.lines,
			r.commits,
			r.frame_ms,
			r.mount_ms
		)
	)
end

local failed = false
if mode == "check" then
	local baseline = read_json(BASELINE)
	if not baseline then
		say(("no baseline at %s: run make bench_update"):format(BASELINE))
		failed = true
	else
		local lower = false
		for _, name in ipairs(order) do
			local expected = baseline[name]
			if not expected then
				say(("%s: not in the baseline, run make bench_update"):format(name))
				failed = true
			else
				for _, key in ipairs(COUNTS) do
					local got, want = results[name][key], expected[key] or 0
					-- A little room above zero, which no percentage gives.
					local limit = math.floor(want * (1 + TOLERANCE)) + 2
					if got > limit then
						say(("FAIL %s %s: %d, the baseline is %d"):format(name, key, got, want))
						failed = true
					elseif got < want * (1 - TOLERANCE) then
						say(
							("note %s %s: %d, below the baseline of %d"):format(
								name,
								key,
								got,
								want
							)
						)
						lower = true
					end
				end
			end
		end
		if lower and not failed then
			say("Counts went down: run make bench_update to keep them there.")
		end
		say(failed and "Work went up past the baseline." or "Counts are within the baseline.")
	end
elseif mode == "update" then
	local counts = {}
	for _, name in ipairs(order) do
		counts[name] = {}
		for _, key in ipairs(COUNTS) do
			counts[name][key] = results[name][key]
		end
	end
	write_json(BASELINE, counts)
	say(("wrote %s"):format(BASELINE))
end

if vim.env.MARKUP_BENCH_OUT then
	local all = {}
	for _, name in ipairs(order) do
		local r = results[name]
		all[name] = {
			layouts = r.layouts,
			commands = r.commands,
			lines = r.lines,
			commits = r.commits,
			frame_ms = r.frame_ms,
			mount_ms = r.mount_ms,
			engine = r.engine,
			apply = r.apply,
		}
	end
	write_json(vim.env.MARKUP_BENCH_OUT, all)
end

io.stdout:write(table.concat(out, "\n") .. "\n")
vim.cmd(failed and "cquit 1" or "qa!")
