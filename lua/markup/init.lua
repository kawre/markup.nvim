local markup = {
	Box = require("markup.box"),
	Inline = require("markup.inline"),
	Block = require("markup.block"),
	Renderer = require("markup.renderer"),
}

function markup.setup()
	vim.api.nvim_create_user_command("Markup", function()
		require("markup-playground").open()
	end, {})
end

return markup
