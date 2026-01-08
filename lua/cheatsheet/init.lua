local config = require("cheatsheet.config")
local M = {}
local cache = nil

local function clean_text(str)
	if not str then
		return ""
	end
	return str:gsub("\27%[[0-9;]*[mK]", ""):gsub("[%c]", ""):gsub("%s+$", "")
end

function M.open_cheat(topic)
	local buf = vim.api.nvim_create_buf(false, true)
	local ft = topic:match("([^/]+)")
	vim.api.nvim_set_option_value("filetype", ft or "markdown", { buf = buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_buf_set_name(buf, "cheat://" .. topic)

	vim.cmd("vsplit")
	vim.api.nvim_set_current_buf(buf)

	-- Use config.options.url (guaranteed non-nil now)
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
	vim.system({ "curl", "-s", config.options.url .. ":list" }, { text = true }, function(obj)
		if obj.code ~= 0 or not obj.stdout then
			return
		end
		local items = {}
		for line in obj.stdout:gmatch("[^\r\n]+") do
			local clean = clean_text(line)
			if clean ~= "" and not clean:match("^#") then
				table.insert(items, { text = clean })
			end
		end
		vim.schedule(function()
			cache = items
			launch(items)
		end)
	end)
end

return M
