-- Find Action (Cmd+Shift+A -> Alt+Shift+A), like IDEA: every action defined in this config,
-- with its shortcuts, e.g. "Type hierarchy   Alt+8, gH". Enter runs it as if you pressed
-- the shortcut. Alt+Shift+A again switches to everything else (all Neovim and plugin
-- commands); a third time closes the list.
--
-- Actions are collected by wrapping vim.keymap.set before the rest of the config loads:
-- mappings with a description, made from ~/.config/nvim (or from the `keys` of the plugin
-- specs there), are recorded. Buffer-local ones (LSP, Java…) show up where they exist.

local M = {}

local config_dir = vim.fn.stdpath("config")
---@type table<string, {name: string, keys: table<string, {mode: string, lhs: string}>}>
local actions = {}

local function clean(desc)
	-- "LSP: [G]oto [D]efinition" -> "Goto Definition"
	local name = vim.trim((desc:gsub("^LSP: ", ""):gsub("%[(.-)%]", "%1")))
	return (name:gsub("^%l", string.upper))
end

local function record(modes, lhs, opts)
	if lhs:match("Mouse") then
		return
	end
	local name = clean(opts.desc)
	local action = actions[name] or { name = name, keys = {} }
	actions[name] = action
	for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do
		-- '' = normal + visual + operator-pending
		for _, m in ipairs(mode == "" and { "n", "x" } or { mode == "v" and "x" or mode }) do
			if m == "n" or m == "x" then
				action.keys[m .. lhs] = { mode = m, lhs = lhs }
			end
		end
	end
end

local set = vim.keymap.set
---@diagnostic disable-next-line: duplicate-set-field
vim.keymap.set = function(modes, lhs, rhs, opts)
	set(modes, lhs, rhs, opts)
	if opts and type(opts.desc) == "string" then
		local source = (debug.getinfo(2, "S") or {}).source or ""
		if source:find(config_dir, 1, true) or source:find("lazy/core/handler/keys.lua", 1, true) then
			record(modes, lhs, opts)
		end
	end
end

---------------------------------------------------------------------------
-- Shortcuts as you press them (tmux / Alacritty codes translated back)
---------------------------------------------------------------------------

local SPECIAL = {
	["<F37>"] = "Ctrl+Tab",
	["<F38>"] = "Ctrl+Shift+Tab",
	["<F39>"] = "Ctrl+Shift+F",
	["<F40>"] = "Ctrl+Enter",
	["<F41>"] = "Ctrl+Shift+R",
	["<F42>"] = "Ctrl+Shift+B",
	["<F43>"] = "Ctrl+Alt+M",
	["<F48>"] = "Alt+Shift+F12",
	["<C-S-F12>"] = "Alt+Shift+F12",
	["<M-M>"] = "Ctrl+Shift+M",
	["<M-h>"] = "Ctrl+Shift+P",
	["<M-l>"] = "Ctrl+Shift+N",
	["<M-~>"] = "Alt+Shift+`",
}
-- characters typed with Shift, shown as the key you press
local SHIFTED = { _ = "-", ["+"] = "=", ["{"] = "[", ["}"] = "]", ["~"] = "`", ["|"] = "\\", [":"] = ";", ["?"] = "/" }
local NAMES = {
	CR = "Enter",
	BS = "Backspace",
	Esc = "Esc",
	Space = "Space",
	Insert = "Insert",
	Home = "Home",
	Up = "↑",
	Down = "↓",
	Left = "←",
	Right = "→",
	Tab = "Tab",
}

local function pretty(lhs)
	lhs = lhs:gsub("^ ", "<leader>"):gsub("^<Space>", "<leader>")
	if SPECIAL[lhs] then
		return SPECIAL[lhs]
	end
	-- F13+ are modified F-keys as they arrive inside tmux
	local f = tonumber(lhs:match("^<F(%d+)>$"))
	if f and f > 12 then
		local mods = ({ "Shift+", "Ctrl+", "Ctrl+Shift+", "Alt+", "Alt+Shift+" })[math.floor((f - 1) / 12)]
		return mods and (mods .. "F" .. ((f - 1) % 12 + 1)) or lhs
	end
	local out = lhs:gsub("<leader>", "␣ "):gsub("<([^>]+)>", function(key)
		-- "C-S-F8" -> mods "C-S", key "F8"; "M--" -> mods "M", key "-"
		local modstr, base = key:match("^(.*)%-(.+)$")
		if not modstr then
			modstr, base = "", key
		end
		local mods = {}
		for _, m in ipairs(vim.split(modstr, "-", { trimempty = true })) do
			table.insert(mods, ({ C = "Ctrl", M = "Alt", A = "Alt", S = "Shift", D = "Cmd" })[m] or m)
		end
		if #mods > 0 and SHIFTED[base] then
			table.insert(mods, "Shift")
			base = SHIFTED[base]
		elseif #base == 1 and base:match("%u") and #mods > 0 then
			table.insert(mods, "Shift")
		end
		table.insert(mods, NAMES[base] or (#base == 1 and base:upper() or base))
		return table.concat(mods, "+")
	end)
	return (out:gsub("␣ ", "␣"))
end

-- Actions available in the current buffer, with their shortcuts
local function available()
	local list = {}
	for _, action in pairs(actions) do
		local keys, seen, run = {}, {}, nil
		for _, k in pairs(action.keys) do
			local m = vim.fn.maparg(k.lhs, k.mode, false, true)
			if m and m.desc and clean(m.desc) == action.name then
				local p = pretty(k.lhs)
				if not seen[p] then
					seen[p] = true
					table.insert(keys, p)
				end
				if
					not run
					or (run.mode == "x" and k.mode == "n")
					or (#k.lhs < #run.lhs and k.mode == run.mode and not k.lhs:match("^<F%d%d>$"))
				then
					run = k
				end
			end
		end
		if run then
			table.sort(keys, function(a, b)
				return #a < #b
			end)
			table.insert(list, { name = action.name, keys = table.concat(keys, ", "), run = run })
		end
	end
	table.sort(list, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return list
end

local function execute(k, tries)
	-- the picker leaves insert mode asynchronously; run the action once back in normal mode
	if vim.fn.mode() ~= "n" and (tries or 0) < 20 then
		return vim.defer_fn(function()
			execute(k, (tries or 0) + 1)
		end, 10)
	end
	if k.mode == "x" then
		-- visual-only action from normal mode: work on the last selection
		vim.cmd("normal! gv")
	end
	local m = vim.fn.maparg(k.lhs, k.mode, false, true)
	if m.callback and m.expr ~= 1 then
		return m.callback()
	end
	vim.api.nvim_feedkeys(vim.keycode(k.lhs), "m", false)
end

M.list = available

function M.find_action()
	local pickers, finders = require("telescope.pickers"), require("telescope.finders")
	local actions_t, state = require("telescope.actions"), require("telescope.actions.state")
	local displayer = require("telescope.pickers.entry_display").create({
		separator = "  ",
		items = { { width = 0.6 }, { remaining = true } },
	})
	pickers
		.new({}, {
			prompt_title = "Actions · Alt+Shift+A: all commands",
			finder = finders.new_table({
				results = available(),
				entry_maker = function(a)
					return {
						value = a,
						ordinal = a.name .. " " .. a.keys,
						display = function()
							return displayer({ a.name, { a.keys, "Comment" } })
						end,
					}
				end,
			}),
			sorter = require("telescope.config").values.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions_t.select_default:replace(function()
					local entry = state.get_selected_entry()
					actions_t.close(prompt_bufnr)
					if entry then
						execute(entry.value.run)
					end
				end)
				-- second Alt+Shift+A: everything else, like IDEA's second Cmd+Shift+A
				map({ "i", "n" }, "<M-A>", function()
					local text = state.get_current_line()
					actions_t.close(prompt_bufnr)
					require("telescope.builtin").commands({ default_text = text })
				end)
				return true
			end,
		})
		:find()
end

set("n", "<M-A>", M.find_action, { desc = "Find Action" })
set("n", "<leader>sa", M.find_action, { desc = "Search actions" })

return M
