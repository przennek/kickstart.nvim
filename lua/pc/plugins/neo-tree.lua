-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

-- Alt+1 (Project tool window): reveal the current file without ever asking to change the cwd.
--  * diff buffers (diffview://…/.git/<rev>/path) reveal the same path in the repo
--  * files outside the cwd open the tree rooted at their project / directory
--    (the tree is not bound to the cwd, so Neovim's cwd stays where it is)
--  * buffers that aren't files (decompiled jdt:// classes, terminals…) just open the project tree
local function project_tree()
  local name = vim.api.nvim_buf_get_name(0)
  local repo, rel = name:match '^diffview://(.-)/%.git/[^/]+/(.+)$'
  local file = repo and (repo .. '/' .. rel) or name
  local command = require 'neo-tree.command'
  local cwd = vim.fn.getcwd()

  if vim.bo.buftype ~= '' and not repo or not vim.uv.fs_stat(file) then
    return command.execute { action = 'focus', source = 'filesystem', dir = cwd }
  end
  local dir = cwd
  if not vim.startswith(file, cwd .. '/') then
    dir = vim.fs.root(file, { '.git', 'pom.xml', 'build.gradle', 'pyproject.toml', 'Makefile' }) or vim.fs.dirname(file)
  end
  command.execute { action = 'focus', source = 'filesystem', dir = dir, reveal_file = file }
end

local function run_context_in_tree(state, debug)
  local node = state.tree:get_node()
  if node.type == 'directory' then
    return require('pc.test_runner').run_tests(node.path, debug)
  end
  vim.cmd 'wincmd p'
  vim.cmd.edit(vim.fn.fnameescape(node.path))
  local run = require 'pc.run'
  if debug then
    run.debug_context()
  else
    run.run_context()
  end
end

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  cmd = 'Neotree',
  lazy = false,
  keys = {
    { '<A-1>', project_tree, desc = 'Project (reveal current file)' },
  },
  opts = {
    filesystem = {
      hijack_netrw_behavior = 'open_current',
      -- Opening the tree somewhere else must not change Neovim's cwd
      bind_to_cwd = false,
      -- Autoscroll from source (on in your IDEA project view): the tree follows the open file
      follow_current_file = { enabled = true },
      -- files added / removed outside nvim (an agent, git, the terminal) show up at once
      use_libuv_file_watcher = true,
      window = {
        mappings = {
          ['<A-1>'] = 'close_window',
          -- New… (Ctrl+Enter, sent as F40 by Alacritty) and Jump to Source (F4)
          ['<F40>'] = function(state)
            -- New… menu (Java Class, Python File / Package, File, Directory) in the node's directory
            local node = state.tree:get_node()
            local dir = node.type == 'directory' and node.path or vim.fs.dirname(node.path)
            require('pc.new_element').menu(dir)
          end,
          ['<C-CR>'] = function(state)
            local node = state.tree:get_node()
            local dir = node.type == 'directory' and node.path or vim.fs.dirname(node.path)
            require('pc.new_element').menu(dir)
          end,
          ['<F4>'] = 'open',
          -- Copy (F5): the file under the cursor, as Copy Class / Copy File
          ['<F5>'] = function(state)
            local node = state.tree:get_node()
            if node.type == 'file' then
              vim.cmd 'wincmd p'
              require('pc.copy_class').copy(node.path)
            end
          end,
          -- Run / Debug context (Ctrl+Shift+F10 / F9, as F46 / F45): on a directory all its
          -- tests (IDEA's Run 'All Tests'), on a file what the editor would run
          ['<C-S-F10>'] = function(state)
            run_context_in_tree(state, false)
          end,
          ['<F46>'] = function(state)
            run_context_in_tree(state, false)
          end,
          ['<C-S-F9>'] = function(state)
            run_context_in_tree(state, true)
          end,
          ['<F45>'] = function(state)
            run_context_in_tree(state, true)
          end,
          -- Compare Two Files: = on one file, then = on another
          ['='] = function(state)
            require('pc.compare_files').mark(state.tree:get_node().path)
          end,
          ['<space>'] = {
            'toggle_node',
            nowait = false, -- disable `nowait` if you have existing combos starting with this char that you want to use
          },
        },
      },
    },
  },
  config = function(_, opts)
    require('neo-tree').setup(opts)
    -- Following the current file: a Diffview buffer (Git log, branch diff) is its file in the
    -- repo; other non-file buffers (jdt://, fugitive://…) are skipped instead of being joined
    -- to the cwd as a path that doesn't exist
    local manager = require 'neo-tree.sources.manager'
    local path_to_reveal = manager.get_path_to_reveal
    manager.get_path_to_reveal = function(include_terminals)
      local name = vim.api.nvim_buf_get_name(0)
      local repo, rel = name:match '^diffview://(.-)/%.git/[^/]+/(.+)$'
      if repo then
        return repo .. '/' .. rel
      end
      if name:match '^%a[%w+.-]*://' and not (include_terminals and name:match '^term://') then
        return nil
      end
      return path_to_reveal(include_terminals)
    end
  end,
}
