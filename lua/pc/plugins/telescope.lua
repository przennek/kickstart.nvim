-- Fuzzy Finder (files, lsp, etc)
return {
	"nvim-telescope/telescope.nvim",
	event = "VimEnter",
	dependencies = {
		"nvim-lua/plenary.nvim",
		{ -- If encountering errors, see telescope-fzf-native README for installation instructions
			"nvim-telescope/telescope-fzf-native.nvim",

			-- `build` is used to run some command when the plugin is installed/updated.
			-- This is only run then, not every time Neovim starts up.
			build = "make",

			-- `cond` is a condition used to determine whether this plugin should be
			-- installed and loaded.
			cond = function()
				return vim.fn.executable("make") == 1
			end,
		},
		{ "nvim-telescope/telescope-ui-select.nvim" },

		-- Useful for getting pretty icons, but requires a Nerd Font.
		{ "nvim-tree/nvim-web-devicons", enabled = vim.g.have_nerd_font },
	},
	config = function()
		-- Telescope is a fuzzy finder that comes with a lot of different things that
		-- it can fuzzy find! It's more than just a "file finder", it can search
		-- many different aspects of Neovim, your workspace, LSP, and more!
		--
		-- The easiest way to use Telescope, is to start by doing something like:
		--  :Telescope help_tags
		--
		-- After running this command, a window will open up and you're able to
		-- type in the prompt window. You'll see a list of `help_tags` options and
		-- a corresponding preview of the help.
		--
		-- Two important keymaps to use while in Telescope are:
		--  - Insert mode: <c-/>
		--  - Normal mode: ?
		--
		-- This opens a window that shows you all of the keymaps for the current
		-- Telescope picker. This is really useful to discover what Telescope can
		-- do as well as how to actually do it!

		-- [[ Configure Telescope ]]
		-- See `:help telescope` and `:help telescope.setup()`
		-- Ctrl+T in any picker moves all its results to the Find window at the bottom (Alt+3)
		local function open_in_find_window(prompt_bufnr)
			require("telescope.actions").send_to_qflist(prompt_bufnr)
			require("trouble").open("quickfix")
		end

		-- Like IDEA popups: pressing the key that opened a picker again closes it
		-- (Alt+F2 projects, Alt+Shift+N files, Alt+E / Alt+Shift+E recent, Alt+F12 structure,
		-- Alt+2 / Shift+F11 bookmarks, Alt+Shift+A actions, Alt+Shift+V clipboard, F10 run
		-- configurations; F50 / F60 / F23 are how some of them arrive inside tmux).
		-- Alt+N stays special in Go to Class: it toggles non-project classes, as in IDEA.
		local close_with_opening_key = {}
		for _, key in ipairs({
			"<M-F2>",
			"<F50>",
			"<M-N>",
			"<M-e>",
			"<M-E>",
			"<M-F12>",
			"<F60>",
			"<M-2>",
			"<S-F11>",
			"<F23>",
			"<M-A>",
			"<M-V>",
			"<F10>",
		}) do
			close_with_opening_key[key] = "close"
		end
		-- Switcher: Ctrl+Tab / Ctrl+Shift+Tab (F37 / F38) move through the list, F4 opens
		close_with_opening_key["<F37>"] = "move_selection_next"
		close_with_opening_key["<F38>"] = "move_selection_previous"
		close_with_opening_key["<F4>"] = "select_default"

		require("telescope").setup({
			defaults = {
				mappings = {
					i = vim.tbl_extend("force", close_with_opening_key, { ["<C-t>"] = open_in_find_window }),
					n = vim.tbl_extend("force", close_with_opening_key, { ["<C-t>"] = open_in_find_window }),
				},
			},
			-- You can put your default mappings / updates / etc. in here
			--  All the info you're looking for is in `:help telescope.setup()`
			--
			-- defaults = {
			--   mappings = {
			--     i = { ['<c-enter>'] = 'to_fuzzy_refine' },
			--   },
			-- },
			-- pickers = {}
			extensions = {
				["ui-select"] = {
					require("telescope.themes").get_dropdown(),
				},
			},
		})

		-- Enable Telescope extensions if they are installed
		pcall(require("telescope").load_extension, "fzf")
		pcall(require("telescope").load_extension, "ui-select")

		-- See `:help telescope.builtin`
		local builtin = require("telescope.builtin")
		vim.keymap.set("n", "<leader>sh", builtin.help_tags, { desc = "[S]earch [H]elp" })
		vim.keymap.set("n", "<leader>sk", builtin.keymaps, { desc = "[S]earch [K]eymaps" })
		vim.keymap.set("n", "<leader>sf", builtin.find_files, { desc = "Go to File" })
		vim.keymap.set("n", "<leader>ss", builtin.builtin, { desc = "[S]earch [S]elect Telescope" })
		vim.keymap.set("n", "<leader>sw", builtin.grep_string, { desc = "[S]earch current [W]ord" })
		vim.keymap.set("n", "<leader>sg", builtin.live_grep, { desc = "Find in Path" })
		vim.keymap.set("n", "<leader>sd", builtin.diagnostics, { desc = "[S]earch [D]iagnostics" })
		vim.keymap.set("n", "<leader>sr", builtin.resume, { desc = "[S]earch [R]esume" })
		vim.keymap.set("n", "<leader>s.", function()
			builtin.oldfiles({ cwd_only = true })
		end, { desc = "Recent Files" })
		vim.keymap.set("n", "<leader><leader>", builtin.buffers, { desc = "Open files (buffers)" })
		vim.keymap.set("n", "<leader>sp", builtin.git_files, { desc = "[S]earch [P]roject (git files)" })
		vim.keymap.set("n", "<leader>s:", "<cmd>Telescope command_history<CR>", { desc = "[S]earch command history" })

		-- [[ IDEA-like navigation ]]
		-- GotoClass: workspace symbols narrowed to types
		-- Works from any buffer (file tree, diff, Markdown…): asks a buffer whose language
		-- server can search the workspace, preferring the current one.
		local function workspace_symbol_buf()
			local method = "workspace/symbol"
			local function capable(buf)
				for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
					if client:supports_method(method, buf) then
						return true
					end
				end
			end
			if capable(0) then
				return vim.api.nvim_get_current_buf()
			end
			for _, client in ipairs(vim.lsp.get_clients({ method = method })) do
				local buf = next(client.attached_buffers)
				if buf then
					return buf
				end
			end
		end
		-- Go to Class: project classes only, like IDEA. Alt+N again inside the picker toggles
		-- "include non-project items" (JDK, libraries, .venv…), keeping what you typed.
		local class_kinds = { Class = true, Interface = true, Enum = true, Struct = true, Module = true }
		local function in_project(filename, root)
			return vim.startswith(filename, root .. "/")
				and not filename:match("/%.venv/")
				and not filename:match("/site%-packages/")
				and not filename:match("/node_modules/")
				and not filename:match("/target/")
				and not filename:match("/build/")
		end
		local function goto_class(opts)
			opts = opts or {}
			local bufnr = workspace_symbol_buf()
			if not bufnr then
				vim.notify("No language server running yet: open a source file first", vim.log.levels.WARN)
				return
			end
			local root = vim.fn.getcwd()
			local channel = require("plenary.async.control").channel
			local cancel = function() end
			local function request(prompt)
				local tx, rx = channel.oneshot()
				cancel()
				cancel = vim.lsp.buf_request_all(bufnr, "workspace/symbol", { query = prompt }, tx)
				local items = {}
				for client_id, response in pairs(rx()) do
					local client = vim.lsp.get_client_by_id(client_id)
					if response.result and client then
						for _, item in
							ipairs(vim.lsp.util.symbols_to_items(response.result, bufnr, client.offset_encoding))
						do
							if class_kinds[item.kind] and (opts.include_all or in_project(item.filename, root)) then
								table.insert(items, item)
							end
						end
					end
				end
				return items
			end

			require("telescope.pickers")
				.new({ bufnr = bufnr, default_text = opts.default_text }, {
					prompt_title = opts.include_all and "Go to Class (all places)"
						or "Go to Class (project) · Alt+N: all places",
					finder = require("telescope.finders").new_dynamic({
						fn = request,
						entry_maker = require("telescope.make_entry").gen_from_lsp_symbols({ bufnr = bufnr }),
					}),
					previewer = require("telescope.config").values.qflist_previewer({}),
					sorter = require("telescope.config").values.generic_sorter({}),
					attach_mappings = function(prompt_bufnr, map)
						map({ "i", "n" }, "<M-n>", function()
							local text = require("telescope.actions.state").get_current_line()
							require("telescope.actions").close(prompt_bufnr)
							goto_class({ include_all = not opts.include_all, default_text = text })
						end)
						return true
					end,
				})
				:find()
		end
		vim.keymap.set("n", "<leader>sc", goto_class, { desc = "Go to Class" })
		vim.keymap.set("n", "<leader>sn", goto_class, { desc = "Go to Class" })
		vim.keymap.set("n", "<leader>c", goto_class, { desc = "Go to Class" })
		vim.keymap.set("n", "<M-n>", goto_class, { desc = "Go to Class" })
		vim.keymap.set("n", "<leader>sS", function()
			builtin.lsp_dynamic_workspace_symbols({ bufnr = workspace_symbol_buf() })
		end, { desc = "Go to Symbol" })
		vim.keymap.set("n", "<M-N>", builtin.find_files, { desc = "Go to File" })
		vim.keymap.set("n", "<leader>n", builtin.find_files, { desc = "Go to File" })
		-- Switcher: open files, most recently used first
		vim.keymap.set("n", "<leader>q", function()
			builtin.buffers({ sort_mru = true, ignore_current_buffer = true })
		end, { desc = "Switcher" })
		-- Find Action (Alt+Shift+A) is in lua/pc/actions.lua

		-- Slightly advanced example of overriding default behavior and theme
		vim.keymap.set("n", "<leader>/", function()
			-- You can pass additional configuration to Telescope to change the theme, layout, etc.
			builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
				winblend = 10,
				previewer = false,
			}))
		end, { desc = "Search in current file (fuzzy)" })

		-- It's also possible to pass additional configuration options.
		--  See `:help telescope.builtin.live_grep()` for information about particular keys
		vim.keymap.set("n", "<leader>s/", function()
			builtin.live_grep({
				grep_open_files = true,
				prompt_title = "Live Grep in Open Files",
			})
		end, { desc = "[S]earch [/] in Open Files" })

		-- Shortcut for searching your Neovim configuration files
		vim.keymap.set("n", "<leader>sN", function()
			builtin.find_files({ cwd = vim.fn.stdpath("config") })
		end, { desc = "[S]earch [N]eovim files" })
	end,
}
