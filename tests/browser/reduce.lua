--- Shrinks a fuzz tree that Chromium lays out differently to a small one that
--- still differs, to see what one difference is made of.
---
--- It plays the writes of a seed as tests/test_fuzz.lua does, finds the first
--- state the browser disagrees with, freezes the knobs at their values there,
--- then drops children, props and wrappers while a difference remains. Any
--- difference counts, so a seed can hide more than the one it shows: run it
--- again once that one is fixed.
---
---   MARKUP_BROWSER_DIR=$(mktemp -d) nvim --headless --noplugin \
---     -u scripts/minimal_init.lua -l tests/browser/reduce.lua <seed> <steps> <depth> [resize]
---
--- `updates` seeds take 40 steps at depth 4, `deep trees` 20 at depth 7, and
--- `resizes` 40 at depth 4 with `resize`.
local seed, steps, depth, resize =
	tonumber(arg[1]), tonumber(arg[2]), tonumber(arg[3]), arg[4] == "resize"
local m = require("markup")
local F = dofile("tests/helpers/fuzz.lua")
local ref = dofile("tests/browser/reference.lua")
F.capture()
Markup.animate.enabled = false
vim.o.lines, vim.o.columns = 20, 60

local function measure(content, width)
	local win = Markup.window({
		position = "float",
		relative = "editor",
		row = 0,
		col = 0,
		width = width,
		height = 5,
		border = "none",
		backdrop = false,
		enter = false,
		show = true,
	})
	local view = Markup.view(win)
	local ok, err = pcall(function()
		view:render(content())
		F.settle()
	end)
	local result
	if ok then
		local boxes, tree = ref.snapshot(view.engine, view.browser_styles, view.browser_text)
		local rendered, html = pcall(ref.html, tree, { check_text = false })
		if rendered then
			result = { html = html, width = width, boxes = boxes, tree = tree }
		end
	end
	view:destroy()
	win:close()
	F.settle()
	return result
end

-- Returns, for each input, the mismatch message or false.
local function check(inputs)
	local out = {}
	for start = 1, #inputs, 32 do
		local batch = vim.list_slice(inputs, start, math.min(start + 31, #inputs))
		local results = ref.batch(vim.tbl_map(function(i)
			return { html = i.html, width = i.width, check_text = false }
		end, batch))
		for i, input in ipairs(batch) do
			local ok, err = pcall(ref.compare, results[i], vim.deepcopy(input.boxes), nil)
			out[#out + 1] = not ok and err or false
		end
	end
	return out
end

local world = F.world(F.rng(seed), { depth = depth, resize = resize })
-- Find a failing state: knob values and width after each write.
local states = {}
local function state()
	local values = {}
	for i, k in ipairs(world.knobs) do
		values[i] = k.signal()
	end
	return { values = values, width = vim.o.columns }
end
for step = 0, steps do
	if step > 0 then
		world.mutate()
		F.settle()
	end
	states[#states + 1] = state()
end
local inputs = {}
for _, s in ipairs(states) do
	for i, k in ipairs(world.knobs) do
		k.signal(s.values[i])
	end
	vim.o.columns = s.width
	F.settle()
	inputs[#inputs + 1] = measure(world.build, s.width)
		or { html = "", width = s.width, boxes = {} }
end
local results = check(inputs)
local failing
for i, r in ipairs(results) do
	if r then
		failing = i
		print("failing state", i, r)
		break
	end
end
assert(failing, "no failing state")
local s = states[failing]
for i, k in ipairs(world.knobs) do
	k.signal(s.values[i])
end
local width = s.width
vim.o.columns = width
F.settle()

-- Freeze knobs into a static spec.
local function val(knob)
	return world.knobs[knob].signal()
end
local function freeze(spec)
	local k = spec.kind
	if k == "text" then
		return spec
	elseif k == "dyntext" then
		return { kind = "text", value = val(spec.knob) }
	elseif k == "dynchild" then
		return val(spec.knob) and freeze(spec.child) or { kind = "text", value = spec.text }
	elseif k == "show" then
		if val(spec.knob) then
			return freeze(spec.child)
		end
		return spec.fallback and freeze(spec.fallback) or { kind = "none" }
	elseif k == "collapse" then
		return { kind = "collapse", open = val(spec.knob), child = freeze(spec.child) }
	elseif k == "each" then
		local items = {}
		for _, key in ipairs(val(spec.knob)) do
			items[#items + 1] = {
				kind = "box",
				tag = "block",
				props = {},
				children = { { kind = "text", value = "item " .. key .. " " }, freeze(spec.item) },
				item = key,
			}
		end
		return { kind = "box", tag = "block", props = {}, children = items }
	elseif k == "slide" then
		local page = val(spec.knob)
		return {
			kind = "slide",
			page = page,
			child = {
				kind = "box",
				tag = "block",
				props = {},
				children = { { kind = "text", value = "page " .. page }, freeze(spec.pages[page]) },
			},
		}
	elseif k == "component" then
		return freeze(spec.child)
	end
	local props = vim.deepcopy(spec.props)
	for name, index in pairs(spec.dynamic) do
		props[name] = val(index)
	end
	local children = {}
	for _, c in ipairs(spec.children) do
		children[#children + 1] = freeze(c)
	end
	return { kind = "box", tag = spec.tag, props = props, children = children }
end
-- each items append "#key" to texts; keep it simple: drop the suffix (approximation, checked below).
local function build(spec, item)
	local k = spec.kind
	if k == "none" then
		return nil
	elseif k == "text" then
		return item and (spec.value .. "#" .. item) or spec.value
	elseif k == "collapse" then
		return m.collapse(function()
			return spec.open
		end, function()
			return m.block({ build(spec.child, item) })
		end)
	elseif k == "slide" then
		return m.slide(function()
			return 1
		end, function()
			return build(spec.child, item)
		end)
	end
	local props = vim.deepcopy(spec.props)
	local children = {}
	for _, c in ipairs(spec.children) do
		local b = build(c, spec.item or item)
		if b ~= nil then
			children[#children + 1] = b
		end
	end
	props.children = children
	return m[spec.tag](props)
end

local root = freeze(world.root)
local function try(spec)
	return measure(function()
		return build(spec)
	end, width)
end
local first = try(root)
local r0 = check({ first })[1]
print("frozen:", r0)
assert(r0, "frozen tree does not fail")

-- Candidates: every single simplification of the tree.
local function candidates(spec)
	local out = {}
	local function walk(node, replace)
		if node.kind == "text" then
			if node.value ~= "x" and node.value ~= "" then
				replace({ kind = "text", value = "x" })
			end
			return
		end
		if node.kind == "none" then
			return
		end
		if node.child then
			replace(node.child)
			walk(node.child, function(new)
				local saved = node.child
				node.child = new
				replace(node)
				node.child = saved
			end)
			return
		end
		for i, c in ipairs(node.children) do
			replace(c)
		end
		for i = #node.children, 1, -1 do
			local saved = node.children
			local copy = vim.list_slice(saved)
			table.remove(copy, i)
			node.children = copy
			replace(node)
			node.children = saved
		end
		for _, name in ipairs(vim.tbl_keys(node.props)) do
			local saved = node.props
			local copy = vim.deepcopy(saved)
			copy[name] = nil
			node.props = copy
			replace(node)
			node.props = saved
		end
		if node.tag ~= "block" then
			local saved = node.tag
			node.tag = "block"
			replace(node)
			node.tag = saved
		end
		for i, c in ipairs(node.children) do
			walk(c, function(new)
				local saved = node.children
				local copy = vim.list_slice(saved)
				copy[i] = new
				node.children = copy
				replace(node)
				node.children = saved
			end)
		end
	end
	walk(spec, function(new)
		out[#out + 1] = vim.deepcopy(new)
	end)
	return out
end

local current, reason = root, r0
local rounds = 0
while true do
	rounds = rounds + 1
	local cands = candidates(current)
	local found = false
	for start = 1, #cands, 32 do
		local slice = vim.list_slice(cands, start, math.min(start + 31, #cands))
		local inputs, map = {}, {}
		for _, c in ipairs(slice) do
			local r = try(c)
			if r then
				inputs[#inputs + 1] = r
				map[#inputs] = c
			end
		end
		local rs = check(inputs)
		for i, r in ipairs(rs) do
			if r then
				current, reason, found = map[i], r, true
				break
			end
		end
		if found then
			break
		end
	end
	if not found then
		break
	end
end
local final = try(current)
print("rounds", rounds)
print("width", width)
print("reason", reason)
print(vim.inspect(current))
print(final.html)
ref.close()
