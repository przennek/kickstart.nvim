-- Presentation / Distraction Free Mode, like IDEA's (View → Appearance): only the code, centred,
-- without line numbers, gutter, status bar and tool windows (they stay as they were underneath).
--   <leader>z / :ZenMode   toggle; the same key leaves it, and so does going to
--                          another window; Alt+1…0, Alt+T, Alt+F12 leave it and open their window
-- Only Neovim changes: tmux and the terminal font are left alone.
local TOOL_KEYS = { '<A-1>', '<M-2>', '<M-3>', '<M-4>', '<M-5>', '<M-6>', '<M-7>', '<M-8>', '<M-9>', '<M-0>', '<M-t>', '<M-F12>', '<F60>' }
local zen_buf, zen_saved = nil, {}

return {
  'folke/zen-mode.nvim',
  cmd = 'ZenMode',
  keys = {
    {
      '<leader>z',
      function()
        require('zen-mode').toggle()
      end,
      desc = 'Toggle Presentation Mode',
    },
  },
  opts = {
    -- tool window keys leave the mode first, then do their job (Alt+1 focuses the tree…)
    on_open = function(win)
      local buf = vim.api.nvim_win_get_buf(win)
      -- the buffer's own mappings of these keys (Alt+8 in Java…) come back on close
      local saved = {}
      vim.api.nvim_buf_call(buf, function()
        for _, lhs in ipairs(TOOL_KEYS) do
          local m = vim.fn.maparg(lhs, 'n', false, true)
          if m.buffer == 1 then
            table.insert(saved, m)
          end
        end
      end)
      zen_buf, zen_saved = buf, saved
      for _, lhs in ipairs(TOOL_KEYS) do
        vim.keymap.set('n', lhs, function()
          require('zen-mode').close()
          vim.schedule(function()
            vim.api.nvim_feedkeys(vim.keycode(lhs), 'm', false)
          end)
        end, { buffer = buf, desc = 'Leave Presentation Mode, then ' .. lhs })
      end
    end,
    on_close = function()
      local buf = zen_buf
      zen_buf = nil
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
      end
      for _, lhs in ipairs(TOOL_KEYS) do
        pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
      end
      vim.api.nvim_buf_call(buf, function()
        for _, m in ipairs(zen_saved) do
          vim.fn.mapset('n', false, m)
        end
      end)
    end,
    window = {
      backdrop = 1,
      width = 120,
      height = 1,
      options = {
        number = false,
        relativenumber = false,
        signcolumn = 'no',
        foldcolumn = '0',
        statuscolumn = '',
        cursorline = false,
        list = false,
        winbar = '',
      },
    },
    plugins = {
      options = { enabled = true, ruler = false, showcmd = false, laststatus = 0 },
      gitsigns = { enabled = true },
      tmux = { enabled = false },
      alacritty = { enabled = false },
      kitty = { enabled = false },
      wezterm = { enabled = false },
      twilight = { enabled = false },
    },
  },
}
