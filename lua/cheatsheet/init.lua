local config = require("cheatsheet.config")
local M = {}
local cache = nil

-- AGGRESSIVE CLEANING: Only allow printable characters and slashes
local function clean_text(str)
	if not str then
		return ""
	end
	-- Remove ANSI escape sequences
	str = str:gsub("\27%[[0-9;]*[mK]", "")
	-- Remove all control characters (0-31 and 127, includes \r, \t, etc.)
	str = str:gsub("[%c]", "")
	-- Trim whitespace
	str = vim.trim(str)
	return str
end

function M.open_cheat(topic)
	local buf = vim.api.nvim_create_buf(false, true)
	local ft = topic:match("([^/]+)")
	vim.api.nvim_set_option_value("filetype", ft or "markdown", { buf = buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_buf_set_name(buf, "cheat://" .. topic)

	vim.cmd("vsplit")
	vim.api.nvim_set_current_buf(buf)

	vim.system({ "curl", "-s", config.options.url .. topic .. "?T" }, { text = true }, function(obj)
		vim.schedule(function()
			if obj.stdout then
				local lines = vim.split(obj.stdout:gsub("\r", ""), "\n")
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			end
		end)
	end)
end

function M.setup(opts)
	config.setup(opts)
end

function M.pick()
	local snacks = require("snacks")

	local function launch(items)
		snacks.picker.pick({
			source = "cheat_sh",
			title = " Cheat.sh ",
			items = items,
			layout = config.options.layout,
			-- Force snacks to render the text column specifically
			format = "text",
			columns = {
				{ member = "text", hl = "SnacksPickerLabel" },
			},
			preview = function(ctx)
				local item = ctx.item
				if not item then
					return
				end

				vim.system({ "curl", "-s", config.options.url .. item.text .. "?T" }, { text = true }, function(obj)
					vim.schedule(function()
						if obj.stdout and vim.api.nvim_buf_is_valid(ctx.buf) then
							local lines = vim.split(obj.stdout:gsub("\r", ""), "\n")
							ctx.preview:set_lines(lines)
							local ft = item.text:match("([^/]+)")
							ctx.preview:highlight({ ft = ft or "markdown" })
						end
					end)
				end)
			end,
			confirm = function(picker, item)
				picker:close()
				local val = item.text
				vim.schedule(function()
					if val:sub(-1) == "/" then
						vim.ui.input({ prompt = "Query " .. val }, function(input)
							if input and input ~= "" then
								M.open_cheat(val .. input)
							end
						end)
					else
						M.open_cheat(val)
					end
				end)
			end,
		})
	end

	if cache then
		return launch(cache)
	end

	snacks.notify.info("Fetching Cheat.sh index...")

	-- Using vim.system for cleaner data capture
	vim.system({ "curl", "-s", config.options.url .. ":list" }, { text = true }, function(obj)
		if obj.code ~= 0 or not obj.stdout then
			vim.schedule(function()
				snacks.notify.error("Failed to fetch Cheat.sh list")
			end)
			return
		end

		local items = {}
		-- Split by newline to avoid gmatch issues with \r
		local raw_lines = vim.split(obj.stdout, "\n")

		for _, line in ipairs(raw_lines) do
			local clean = clean_text(line)
			-- Ignore comments and empty lines
			if clean ~= "" and not clean:match("^#") then
				table.insert(items, {
					text = clean,
					-- Adding this helps Snacks internal indexing
					label = clean,
				})
			end
		end

		vim.schedule(function()
			if #items > 0 then
				cache = items
				launch(items)
			else
				snacks.notify.error("Parsed list is empty")
			end
		end)
	end)
end

return M
