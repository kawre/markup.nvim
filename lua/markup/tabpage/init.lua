local markup = require("markup.core")

---@alias markup.TabPage.count "."|"+"|"-"|"0"|"$"

---@class markup.TabPage.props
---@field tabpage integer
---@field file? string
---@field count markup.TabPage.count
---@field mount boolean
---@field enter boolean

---@class markup.TabPage : markup.Object
---@field protected _ markup.TabPage.props
local TabPage = markup.Object("markup.tabpage")

---@param props markup.TabPage.constructor.props
function TabPage:init(props)
	self._ = vim.tbl_deep_extend("force", {
		count = "",
		enter = true,
		mount = false,
	}, props)

	self.tabpage = self._.tabpage

	if self._.mount then
		self:mount()
	end
end

local function tabpage_cmd(count, file)
	local cmd = count .. "tab"
	if file then
		return cmd .. "edit " .. file
	else
		return cmd .. "new"
	end
end

function TabPage:mount()
	if not self:is_valid() then
		vim.cmd(tabpage_cmd(self._.count, self._.file))
		self.tabpage = vim.api.nvim_get_current_tabpage()

		if not self._.enter then
			vim.cmd.tabprevious()
		end
	end
end

function TabPage:unmount()
	if self:is_valid() then
		local number = self:get_number()
		if number then
			vim.cmd.tabclose(number)
			self.tabpage = nil
		end
	end
end

function TabPage:is_valid()
	return self.tabpage and vim.api.nvim_tabpage_is_valid(self.tabpage)
end

function TabPage:get_number()
	return self.tabpage and vim.api.nvim_tabpage_get_number(self.tabpage)
end

function TabPage:get_var(name)
	local ok, var = pcall(vim.api.nvim_tabpage_get_var, self.tabpage, name)
	if ok then
		return var
	end
end

function TabPage:focus()
	if self:is_valid() then
		vim.api.nvim_set_current_tabpage(self.tabpage)
	end
end

function TabPage:set_file(file)
	self._.file = file
end

---@class markup.TabPage.constructor.props
---@field tabpage? integer bind to an existing tabpage handle
---@field file? string open new tabpage with this file
---@field count? markup.TabPage.count new tabpage appears after [count]
---@field mount? boolean open tabpage on init
---@field enter? boolean focus on new tabpage

---@alias markup.TabPage.constructor fun(props: markup.TabPage.constructor.props): markup.TabPage

---@type markup.TabPage.constructor
local MarkupTabPage = TabPage ---@diagnostic disable-line: assign-type-mismatch

return MarkupTabPage
