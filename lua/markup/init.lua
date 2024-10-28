local markup = {}

function markup.setup()
	vim.api.nvim_create_user_command("Markup", function()
		require("markup-playground").open()
	end, {})
end

return markup
