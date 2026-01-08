local config = require("cheatsheet.config")
local M = {}

---@type table[]?
local cache = nil

-- --- Helpers ---

---Removes control characters and specific icons
---@param str string
---@return string
local function sanitize(str)
	return (str:gsub("[%c]", ""):gsub("  ", ""):gsub("󰉋  ", ""))
end

---Reads a local file into a list of lines
---@param path string
---@return string[]?
local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*all")
	f:close()
	return vim.split(content:gsub("\r", ""), "\n")
end

-- --- Core Logic ---

---Logic to display the cheat sheet in a split window
---@param item table {text: string, is_local: boolean, path?: string}
function M.display(item)
	local topic = sanitize(item.text)
	local buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_name(buf, "cheat://" .. topic)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"

	local ft = topic:match("([^/]+)")
	pcall(function()
		vim.bo[buf].filetype = ft or "markdown"
	end)

	vim.cmd("vsplit")
	vim.api.nvim_set_current_buf(buf)

	if item.is_local and item.path then
		local lines = read_file(item.path)
		if lines then
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		end
	else
		vim.system({ "curl", "-s", config.options.url .. topic .. "?T" }, { text = true }, function(obj)
			vim.schedule(function()
				if obj.stdout and vim.api.nvim_buf_is_valid(buf) then
					local lines = vim.split(obj.stdout:gsub("\r", ""), "\n")
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
				end
			end)
		end)
	end
end

function M.setup(opts)
	config.setup(opts)
end

---The Snacks.picker implementation
function M.pick()
	local snacks = require("snacks")

	local function launch(items)
		snacks.picker.pick({
			source = "cheatsheet",
			title = " Cheat.sh ",
			items = items,
			layout = config.options.layout,
			format = "text",
			columns = { { member = "text", hl = "SnacksPickerLabel" } },
			win = {
				input = {
					keys = {
						["<c-s>"] = function(picker)
							local search = picker:filter().search
							if search ~= "" then
								picker:close()
								M.display({ text = search, is_local = false })
							end
						end,
					},
				},
			},
			preview = function(ctx)
				local item = ctx.item
				if not item or item.is_manual then
					return
				end

				if item.is_local then
					local lines = read_file(item.path)
					if lines then
						ctx.preview:set_lines(lines)
						ctx.preview:highlight({ ft = "markdown" })
					end
				else
					local topic = sanitize(item.text)
					vim.system({ "curl", "-s", config.options.url .. topic .. "?T" }, { text = true }, function(obj)
						vim.schedule(function()
							if
								obj.stdout
								and vim.api.nvim_buf_is_valid(ctx.buf)
								and ctx.item
								and ctx.item.text == item.text
							then
								local lines = vim.split(obj.stdout:gsub("\r", ""), "\n")
								ctx.preview:set_lines(lines)
								pcall(function()
									ctx.preview:highlight({ ft = topic:match("([^/]+)") or "markdown" })
								end)
							end
						end)
					end)
				end
			end,
			confirm = function(picker, item)
				picker:close()
				vim.schedule(function()
					if item.is_manual then
						vim.ui.input({ prompt = "Manual Query: " }, function(input)
							if input and input ~= "" then
								M.display({ text = input, is_local = false })
							end
						end)
					elseif not item.is_local and item.text:sub(-1) == "/" then
						vim.ui.input({ prompt = "Query " .. item.text }, function(input)
							if input and input ~= "" then
								M.display({ text = item.text .. input, is_local = false })
							end
						end)
					else
						M.display(item)
					end
				end)
			end,
		})
	end

	if cache then
		return launch(cache)
	end

	require("snacks").notify.info("Indexing Cheatsheets...")

	local final_items = { { text = "  Manual Query...", is_manual = true } }

	-- Add Local Files
	if config.options.local_path and vim.fn.isdirectory(config.options.local_path) == 1 then
		for _, path in ipairs(vim.fn.globpath(config.options.local_path, "*", false, true)) do
			table.insert(final_items, {
				text = "󰉋  " .. vim.fn.fnamemodify(path, ":t"),
				path = path,
				is_local = true,
			})
		end
	end

	-- Fetch Remote List
	vim.system({ "curl", "-s", config.options.url .. ":list" }, { text = true }, function(obj)
		if obj.code == 0 and obj.stdout then
			local remote_items = vim.iter(vim.split(obj.stdout, "\n"))
				:map(function(line)
					return line:gsub("[%c]", "")
				end)
				:filter(function(line)
					return line ~= "" and not line:match("^#")
				end)
				:map(function(line)
					return { text = line, is_local = false }
				end)
				:totable()

			vim.list_extend(final_items, remote_items)
		end

		vim.schedule(function()
			cache = final_items
			launch(final_items)
		end)
	end)
end

return M
