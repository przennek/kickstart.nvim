-- Colors like IDEA's Islands Dark (the JetBrains New UI dark scheme), plus Quick Switch Scheme:
--   <leader>ts / :QuickSwitchScheme   JetBrains Dark / Light, Tokyo Night or any installed scheme;
--                                     the choice is remembered between sessions

local STATE = vim.fn.stdpath 'data' .. '/pc_colorscheme'

local SCHEMES = {
  { name = 'JetBrains Dark (Islands Dark)', scheme = 'jb', background = 'dark' },
  { name = 'JetBrains Light', scheme = 'jb', background = 'light' },
  { name = 'Tokyo Night', scheme = 'tokyonight-night', background = 'dark' },
}

local function apply(choice)
  vim.o.background = choice.background or 'dark'
  local ok = pcall(vim.cmd.colorscheme, choice.scheme)
  if ok then
    pcall(vim.fn.writefile, { choice.scheme, vim.o.background }, STATE)
  end
  return ok
end

local function quick_switch()
  local items = vim.list_extend({}, SCHEMES)
  table.insert(items, { name = 'Other installed schemes…' })
  vim.ui.select(items, {
    prompt = 'Switch Color Scheme',
    format_item = function(item)
      local current = item.scheme == vim.g.colors_name and item.background == vim.o.background
      return (current and '● ' or '  ') .. item.name
    end,
  }, function(choice)
    if not choice then
      return
    elseif choice.scheme then
      apply(choice)
    else
      require('telescope.builtin').colorscheme {
        enable_preview = true,
        attach_mappings = function(prompt_bufnr)
          local actions = require 'telescope.actions'
          actions.select_default:replace(function()
            local entry = require('telescope.actions.state').get_selected_entry()
            actions.close(prompt_bufnr)
            if entry then
              apply { scheme = entry.value, background = vim.o.background }
            end
          end)
          return true
        end,
      }
    end
  end)
end

return {
  {
    'nickkadutskyi/jb.nvim',
    lazy = false,
    priority = 1000, -- Make sure to load this before all the other start plugins.
    config = function()
      require('jb').setup {}
      local ok, saved = pcall(vim.fn.readfile, STATE)
      local choice = ok and saved[1] and { scheme = saved[1], background = saved[2] } or SCHEMES[1]
      if not apply(choice) then
        apply(SCHEMES[1])
      end
      vim.keymap.set('n', '<leader>ts', quick_switch, { desc = '[T]oggle color [s]cheme (Quick Switch)' })
      vim.api.nvim_create_user_command('QuickSwitchScheme', quick_switch, { desc = 'Quick Switch Scheme' })
    end,
  },
  { 'folke/tokyonight.nvim', lazy = true },
}
