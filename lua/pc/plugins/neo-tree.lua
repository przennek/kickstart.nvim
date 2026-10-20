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
          ['<space>'] = {
            'toggle_node',
            nowait = false, -- disable `nowait` if you have existing combos starting with this char that you want to use
          },
        },
      },
    },
  },
}
