if vim.g.loaded_cheatsheet then
	return
end
vim.g.loaded_cheatsheet = true

vim.api.nvim_create_user_command("Cheatsheet", function()
	require("cheatsheet").pick()
end, { desc = "Search Cheat.sh with Snacks Picker" })
