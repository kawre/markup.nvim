-- Gets the engine for markup.nvim. lazy.nvim runs this file on install and on
-- update; other plugin managers can run `nvim -l build.lua` in the plugin's
-- directory.
--
-- On a release (the commit tagged v<version>), the engine for this platform is
-- downloaded from that release. Anywhere else, such as on master between
-- releases, it is built with `cargo build --release`, since an engine from
-- another version may not speak the same protocol as the Lua here.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local REPO = "kawre/markup.nvim"

local function say(msg)
	if coroutine.running() then
		coroutine.yield(msg) -- lazy.nvim shows it as progress
	else
		print(msg)
	end
end

local function run(cmd)
	local result = vim.system(cmd, { cwd = root, text = true }):wait()
	return result.code == 0, vim.trim((result.stdout or "") .. (result.stderr or ""))
end

local function version()
	local file = assert(io.open(root .. "/lua/markup/config.lua"))
	local text = file:read("*a")
	file:close()
	local found = text:match("version = \"([^\"]+)\"")
	assert(found, "no version in lua/markup/config.lua")
	return found
end

--- The release asset for this platform, and the name the library has here.
---@return string? asset, string library
local function platform()
	local uname = vim.uv.os_uname()
	local os = uname.sysname:lower()
	local arch = uname.machine:lower()
	arch = (arch == "aarch64" or arch == "arm64") and "arm64"
		or (arch:match("x86_64") or arch:match("amd64")) and "x86_64"
		or nil
	if os:match("windows") then
		return arch and ("markup_core-windows-%s.dll"):format(arch), "markup_core.dll"
	elseif os == "darwin" then
		return arch and ("markup_core-macos-%s.dylib"):format(arch), "libmarkup_core.dylib"
	elseif os == "linux" then
		return arch and ("markup_core-linux-%s.so"):format(arch), "libmarkup_core.so"
	end
	return nil, "libmarkup_core.so"
end

--- The SHA-256 of a file, with whatever the system has for it.
---@return string?
local function sha256(path)
	for _, cmd in ipairs({
		{ "sha256sum", path },
		{ "shasum", "-a", "256", path },
		{ "certutil", "-hashfile", path, "SHA256" },
	}) do
		if vim.fn.executable(cmd[1]) == 1 then
			local ok, out = run(cmd)
			-- certutil puts its sum on a line of its own, the others first.
			local sum = ok and (out:match("^(%x+)%s") or out:match("\n(%x+)\r?\n"))
			if sum and #sum == 64 then
				return sum:lower()
			end
		end
	end
end

local function download()
	local tag = "v" .. version()
	local on_tag, described = run({ "git", "describe", "--tags", "--exact-match" })
	if not on_tag or described ~= tag then
		return false, ("not on release %s"):format(tag)
	end
	local asset, library = platform()
	if not asset then
		return false, "no release build for this platform"
	end
	vim.fn.mkdir(root .. "/target/release", "p")
	say(("Downloading the engine for %s"):format(tag))
	local base = ("https://github.com/%s/releases/download/%s/"):format(REPO, tag)
	local target = "target/release/" .. library
	local ok, out = run({ "curl", "-fsSL", "-o", target, base .. asset })
	if not ok then
		return false, out
	end

	-- The release lists the SHA-256 of each file; a file that does not match
	-- is not used.
	local got_sums, sums = run({ "curl", "-fsSL", base .. "SHA256SUMS" })
	local want = got_sums and sums:match("(%x+)%s+%*?" .. vim.pesc(asset))
	local have = sha256(root .. "/" .. target)
	if want and have and want:lower() ~= have then
		os.remove(root .. "/" .. target)
		return false, ("%s does not match its SHA-256 in the release"):format(asset)
	elseif not (want and have) then
		say("Could not check the SHA-256 of the engine")
	end
	return true
end

local function build()
	if vim.fn.executable("cargo") == 0 then
		return false, "cargo is not installed"
	end
	say("Building the engine with cargo")
	return run({ "cargo", "build", "--release" })
end

local downloaded, why = download()
if downloaded then
	say("Downloaded the engine")
	return
end
local built, out = build()
if not built then
	error(
		("markup.nvim: no engine. Download: %s. Build: %s. Install Rust, or use a release (`version = \"*\"` with lazy.nvim)."):format(
			why,
			out
		)
	)
end
say("Built the engine")
