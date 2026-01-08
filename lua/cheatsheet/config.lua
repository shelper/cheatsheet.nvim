local M = {}

M.defaults = {
	url = "https://cheat.sh/",
	layout = { preset = "default", preview = true },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
