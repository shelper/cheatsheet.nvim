local M = {}

M.defaults = {
	url = "https://cheat.sh/",
	layout = { preset = "default", preview = true },
}

-- Pre-populate options with defaults so it's never nil
M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
