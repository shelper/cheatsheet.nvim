local config = require("cheatsheet.config")
local M = {}

---@type table[]?
local cache = nil

-- --- Helpers ---

---@param str string
local function sanitize(str)
	if not str then
		return ""
	end
	-- -- 1. Remove common icons
	return vim.trim(str:gsub("󰉋 ", ""):gsub("󱓞 ", ""):gsub("[%c]", ""))
end

-- --- UI Actions ---

function M.display(item_text)
	local topic = sanitize(item_text)
	if topic == "" then
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "cheat://" .. topic)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	pcall(function()
		vim.bo[buf].filetype = topic:match("([^/]+)") or "markdown"
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

function M.pick(picker_opts)
	picker_opts = picker_opts or {}
	local snacks = require("snacks")

	local function launch(items)
		snacks.picker.pick({
			source = "cheatsheet",
			title = " Cheat.sh ",
			items = items,
			layout = config.options.layout,
			-- Pass the cleaned search string back to the input
			search = sanitize(picker_opts.search) or "",
			format = "text",
			win = {
				input = {
					keys = {
						["<c-f>"] = { "cheat_fetch", mode = { "n", "i" } },
					},
				},
			},
			actions = {
				cheat_fetch = function(picker)
					local search = sanitize(picker.input:get())
					if search == "" then
						return
					end

					-- Deduplication check
					if cache then
						for _, item in ipairs(cache) do
							if sanitize(item.text) == search then
								snacks.notify.info("'" .. search .. "' is already in the list.")
								return
							end
						end
					end

					snacks.notify.info("Fetching '" .. search .. "'...")
					vim.system({ "curl", "-s", config.options.url .. search .. "?T" }, { text = true }, function(obj)
						vim.schedule(function()
							local out = obj.stdout or ""
							if out ~= "" and not out:lower():match("unknown topic") then
								if cache then
									table.insert(cache, 1, { text = "󱓞 " .. search })
								end
								picker:close()
								-- Re-open with ONLY the keyword (no prompts)
								M.pick({ search = search })
							else
								snacks.notify.error("Topic not found on Cheat.sh.")
							end
						end)
					end)
				end,
			},
			preview = function(ctx)
				if not ctx.item then
					return
				end
				local topic = sanitize(ctx.item.text)

				vim.system({ "curl", "-s", config.options.url .. topic .. "?T" }, { text = true }, function(obj)
					vim.schedule(function()
						if obj.stdout and vim.api.nvim_buf_is_valid(ctx.buf) then
							local lines = vim.split(obj.stdout:gsub("\r", ""), "\n")
							ctx.preview:set_lines(lines)
							pcall(function()
								ctx.preview:highlight({ ft = topic:match("([^/]+)") or "markdown" })
							end)
						end
					end)
				end)
			end,
			confirm = function(picker, item)
				local search = sanitize(picker.input:get())
				picker:close()

				vim.schedule(function()
					-- Case: Manual search (Enter on empty match)
					if not item then
						if search == "" then
							return
						end

						-- Deduplicate
						local exists = false
						for _, it in ipairs(cache or {}) do
							if sanitize(it.text) == search then
								exists = true
								break
							end
						end

						snacks.notify.info("Fetching '" .. search .. "'...")
						vim.system(
							{ "curl", "-s", config.options.url .. search .. "?T" },
							{ text = true },
							function(obj)
								vim.schedule(function()
									local out = obj.stdout or ""
									if out ~= "" and not out:lower():match("unknown topic") then
										if not exists and cache then
											table.insert(cache, 1, { text = "󱓞 " .. search })
										end
										M.pick({ search = search })
									else
										snacks.notify.error("Not found.")
									end
								end)
							end
						)
						return
					end

					-- Case: Directory
					if item.text:sub(-1) == "/" then
						vim.ui.input({ prompt = "Query " .. item.text }, function(input)
							if input and input ~= "" then
								M.pick({ search = sanitize(item.text) .. input })
							end
						end)
					else
						M.display(item.text)
					end
				end)
			end,
		})
	end

	if cache then
		return launch(cache)
	end

	local final_items = {}
	if config.options.local_path and vim.fn.isdirectory(config.options.local_path) == 1 then
		local local_files = vim.fn.globpath(config.options.local_path, "*", false, true)
		for _, path in ipairs(local_files) do
			table.insert(final_items, { text = "󰉋 " .. vim.fn.fnamemodify(path, ":t") })
		end
	end

	vim.system({ "curl", "-s", config.options.url .. ":list" }, { text = true }, function(obj)
		if obj.code == 0 and obj.stdout then
			local raw_lines = vim.split(obj.stdout, "\n")
			for _, line in ipairs(raw_lines) do
				local clean_line = line:gsub("[%c]", "")
				if clean_line ~= "" and not clean_line:match("^#") then
					table.insert(final_items, { text = clean_line })
				end
			end
		end
		vim.schedule(function()
			cache = final_items
			launch(final_items)
		end)
	end)
end

return M
