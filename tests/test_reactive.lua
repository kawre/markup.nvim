---@module 'mini.test'

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

require("markup")
local r = require("markup.reactive")

local T = new_set()

T["signal"] = new_set()

T["signal"]["reads and writes"] = function()
	local count = r.signal(1)
	eq(count(), 1)
	count(2)
	eq(count(), 2)
end

T["signal"]["accepts an updater function"] = function()
	local count = r.signal(1)
	count(function(c)
		return c + 1
	end)
	eq(count(), 2)
end

T["signal"]["can be set to nil"] = function()
	local value = r.signal(1)
	value(nil)
	eq(value(), nil)
end

T["effect"] = new_set()

T["effect"]["runs immediately and after changes"] = function()
	local count, seen = r.signal(0), {}
	r.effect(function()
		seen[#seen + 1] = count()
	end)
	count(1)
	r.flush()
	eq(seen, { 0, 1 })
end

-- They ran in `pairs` order over a table keyed by the effects, which differs
-- from one session to the next, so a bug that depends on it came and went.
T["effect"]["run in the order they were made"] = function()
	local source, order = r.signal(0), {}
	for i = 1, 60 do
		r.effect(function()
			source()
			order[#order + 1] = i
		end)
	end
	order = {}
	source(1)
	r.flush()
	local expected = {}
	for i = 1, 60 do
		expected[i] = i
	end
	eq(order, expected)
end

T["effect"]["runs once for many writes"] = function()
	local count, runs = r.signal(0), 0
	r.effect(function()
		count()
		runs = runs + 1
	end)
	for i = 1, 100 do
		count(i)
	end
	r.flush()
	eq(runs, 2)
end

T["effect"]["ignores writes of the same value"] = function()
	local count, runs = r.signal(0), 0
	r.effect(function()
		count()
		runs = runs + 1
	end)
	count(0)
	r.flush()
	eq(runs, 1)
end

T["effect"]["tracks only what the last run read"] = function()
	local gate, a, b = r.signal(true), r.signal(0), r.signal(0)
	local runs = 0
	r.effect(function()
		runs = runs + 1
		if gate() then
			a()
		else
			b()
		end
	end)

	gate(false)
	r.flush()
	a(1)
	r.flush()
	eq(runs, 2)

	b(1)
	r.flush()
	eq(runs, 3)
end

T["effect"]["keeps working after an error"] = function()
	local notify = vim.notify
	vim.notify = function() end

	local count, other, seen = r.signal(0), r.signal(0), {}
	r.effect(function()
		if count() == 1 then
			error("boom")
		end
	end)
	r.effect(function()
		seen[#seen + 1] = other()
	end)

	count(1)
	other(1)
	r.flush()
	vim.wait(10)
	vim.notify = notify

	eq(seen, { 0, 1 })
end

T["effect"]["stops a runaway loop"] = function()
	local notify, reported = vim.notify, nil
	vim.notify = function(message)
		reported = message
	end

	local count = r.signal(0)
	local effect = r.effect(function()
		count(count() + 1)
	end)
	r.flush()
	vim.wait(10)
	vim.notify = notify
	r.dispose(effect)

	eq(reported ~= nil, true)
end

T["untrack"] = function()
	local count, runs = r.signal(0), 0
	r.effect(function()
		r.untrack(count)
		runs = runs + 1
	end)
	count(1)
	r.flush()
	eq(runs, 1)
end

T["memo"] = new_set()

T["memo"]["computes lazily and caches"] = function()
	local count, runs = r.signal(1), 0
	local double = r.memo(function()
		runs = runs + 1
		return count() * 2
	end)
	eq(runs, 0)
	eq(double(), 2)
	eq(double(), 2)
	eq(runs, 1)

	count(2)
	eq(double(), 4)
end

T["memo"]["never shows a mix of old and new values"] = function()
	local a = r.signal(1)
	local b = r.memo(function()
		return a() + 1
	end)
	local c = r.memo(function()
		return a() + b()
	end)

	local seen = {}
	r.effect(function()
		seen[#seen + 1] = { a(), b(), c() }
	end)
	a(2)
	r.flush()

	eq(seen, { { 1, 2, 3 }, { 2, 3, 5 } })
end

T["owners"] = new_set()

T["owners"]["disposing stops effects and runs cleanups"] = function()
	local count, runs, cleaned = r.signal(0), 0, 0
	local _, owner = r.scope(function()
		r.on_cleanup(function()
			cleaned = cleaned + 1
		end)
		r.effect(function()
			count()
			runs = runs + 1
		end)
	end)

	r.dispose(owner)
	count(1)
	r.flush()

	eq(runs, 1)
	eq(cleaned, 1)
end

T["owners"]["effects dispose what they created before rerunning"] = function()
	local outer, inner = r.signal(0), r.signal(0)
	local inner_runs = 0
	r.effect(function()
		outer()
		r.effect(function()
			inner()
			inner_runs = inner_runs + 1
		end)
	end)

	outer(1)
	r.flush()
	inner(1)
	r.flush()

	-- First mount, the remount after `outer`, and one rerun of the live effect.
	eq(inner_runs, 3)
end

T["owners"]["a scope can outlive the effect creating it"] = function()
	local trigger, value, runs = r.signal(0), r.signal(0), 0
	local _, root = r.scope(function(parent)
		local created = false
		r.effect(function()
			trigger()
			if not created then
				created = true
				r.scope(function()
					r.effect(function()
						value()
						runs = runs + 1
					end)
				end, parent)
			end
		end)
	end)

	trigger(1)
	r.flush()
	value(1)
	r.flush()
	eq(runs, 2)

	r.dispose(root)
end

T["owners"]["disposed children are released"] = function()
	local _, root = r.scope(function(parent)
		for _ = 1, 100 do
			local _, child = r.scope(function() end, parent)
			r.dispose(child)
		end
		eq(parent.children == nil or vim.tbl_isempty(parent.children), true)
	end)
	r.dispose(root)
end

T["context"] = function()
	local seen
	r.scope(function()
		r.provide("theme", "dark")
		r.scope(function()
			seen = r.inject("theme")
		end)
	end)

	eq(seen, "dark")
	eq(r.inject("theme", "fallback"), "fallback")
end

return T
