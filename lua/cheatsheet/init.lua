local config = require("cheatsheet.config")
local M = {}
local cache = nil

-- Aggressive cleaning for the picker list
local function clean_text(str)
	if not str then
		return ""
	end
	str = str:gsub("\27%[[0-9;]*[mK]", "") -- Strip ANSI
	str = str:gsub("[%c]", "") -- Strip Control Chars
	return vim.trim(str)
end

function M.open_cheat(topic)
	local buf = vim.api.nvim_create_buf(false, true)
	local ft = topic:match("([^/]+)")

	-- Set buffer options safely
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_buf_set_name(buf, "cheat://" .. topic)

	-- Try to set filetype, fallback to markdown
	pcall(function()
		vim.api.nvim_set_option_value("filetype", ft or "markdown", { buf = buf })
	end)

	vim.cmd("vsplit")
	vim.api.nvim_set_current_buf(buf)

	vim.system({ "curl", "-s", config.options.url .. topic .. "?T" }, { text = true }, function(obj)
		vim.schedule(function()
			if obj.stdout and vim.api.nvim_buf_is_valid(buf) then
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
			format = "text",
			columns = {
				{ member = "text", hl = "SnacksPickerLabel" },
			},
			preview = function(ctx)
				local item = ctx.item
				if not item then
					return
				end

				-- Store the current text to verify after async call
				local current_text = item.text

				vim.system({ "curl", "-s", config.options.url .. current_text .. "?T" }, { text = true }, function(obj)
					vim.schedule(function()
						-- 1. Check if buffer is still valid
						-- 2. Check if the user is still hovering over the same item
						if
							obj.stdout
							and vim.api.nvim_buf_is_valid(ctx.buf)
							and ctx.item
							and ctx.item.text == current_text
						then
							local lines = vim.split(obj.stdout:gsub("\r", ""), "\n")
							ctx.preview:set_lines(lines)

							-- Use pcall to ignore "Invalid Argument" for non-existent filetypes
							local ft = current_text:match("([^/]+)")
							pcall(function()
								ctx.preview:highlight({ ft = ft or "markdown" })
							end)
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

	vim.system({ "curl", "-s", config.options.url .. ":list" }, { text = true }, function(obj)
		if obj.code ~= 0 or not obj.stdout then
			return
		end

		local items = {}
		local raw_lines = vim.split(obj.stdout, "\n")

		for _, line in ipairs(raw_lines) do
			local clean = clean_text(line)
			if clean ~= "" and not clean:match("^#") then
				table.insert(items, {
					text = clean,
				})
			end
		end

		vim.schedule(function()
			if #items > 0 then
				cache = items
				launch(items)
			else
				snacks.notify.error("Cheat.sh list is empty")
			end
		end)
	end)
end

return M
