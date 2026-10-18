-- Git, IDEA style. Everything VCS lives under <leader>v (the VCS menu),
-- plus the tool windows: Alt+0 = Commit, Alt+9 = Git log.

-- Compare with Branch: pick a local or remote branch, then diff the current file
-- (or the whole working tree) against it in Diffview
local function compare_with_branch(file_only)
  return function()
    local file = vim.fn.expand '%:p'
    require('telescope.builtin').git_branches {
      prompt_title = file_only and ('Compare ' .. vim.fn.expand '%:t' .. ' with branch') or 'Compare project with branch',
      attach_mappings = function(prompt_bufnr)
        local actions = require 'telescope.actions'
        actions.select_default:replace(function()
          local entry = require('telescope.actions.state').get_selected_entry()
          actions.close(prompt_bufnr)
          local cmd = 'DiffviewOpen ' .. entry.value
          if file_only then
            cmd = cmd .. ' -- ' .. vim.fn.fnameescape(file)
          end
          vim.cmd(cmd)
        end)
        return true
      end,
    }
  end
end

return {
  -- The git fugitive (Annotate = :Git blame)
  {
    'tpope/vim-fugitive',
    keys = {
      { '<leader>va', '<cmd>Git blame<CR>', desc = 'VCS: [A]nnotate (blame)' },
    },
  },
  -- Commit window, branches, push / pull
  {
    'NeogitOrg/neogit',
    dependencies = { 'nvim-lua/plenary.nvim', 'sindrets/diffview.nvim', 'nvim-telescope/telescope.nvim' },
    cmd = 'Neogit',
    keys = {
      { '<M-0>', '<cmd>Neogit<CR>', desc = 'VCS: Commit window' },
      { '<leader>vv', '<cmd>Neogit<CR>', desc = 'VCS: Status / commit window' },
      { '<leader>vc', '<cmd>Neogit commit<CR>', desc = 'VCS: [C]ommit' },
      { '<leader>vp', '<cmd>Neogit pull<CR>', desc = 'VCS: [p]ull' },
      { '<leader>vP', '<cmd>Neogit push<CR>', desc = 'VCS: [P]ush' },
      { '<leader>vB', '<cmd>Telescope git_branches<CR>', desc = 'VCS: [B]ranches' },
      { '<leader>vf', '<cmd>Telescope git_status<CR>', desc = 'VCS: Changed [f]iles' },
    },
    opts = {
      integrations = { diffview = true, telescope = true },
      graph_style = 'unicode',
    },
  },
  -- Diffs and history
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
    keys = {
      { '<M-9>', '<cmd>DiffviewFileHistory<CR>', desc = 'VCS: Git log' },
      { '<leader>vl', '<cmd>DiffviewFileHistory<CR>', desc = 'VCS: [L]og' },
      { '<leader>vh', '<cmd>DiffviewFileHistory %<CR>', desc = 'VCS: File [h]istory' },
      { '<leader>vh', ":'<,'>DiffviewFileHistory<CR>", mode = 'v', desc = 'VCS: Selection history' },
      { '<leader>vd', '<cmd>DiffviewOpen<CR>', desc = 'VCS: [D]iff working tree' },
      { '<leader>vw', compare_with_branch(true), desc = 'VCS: Compare file [w]ith branch' },
      { '<leader>vW', compare_with_branch(false), desc = 'VCS: Compare project [W]ith branch' },
    },
    opts = function()
      -- q closes a diff / history tab, like Esc on an IDEA dialog
      local close = { 'n', 'q', '<cmd>DiffviewClose<CR>', { desc = 'Close Diffview' } }
      return {
        keymaps = {
          view = { close },
          file_panel = { close },
          file_history_panel = { close },
        },
      }
    end,
  },
  -- Adds git related signs to the gutter, as well as utilities for managing changes
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      on_attach = function(bufnr)
        local gitsigns = require 'gitsigns'

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        -- Navigation
        map('n', ']c', function()
          if vim.wo.diff then
            vim.cmd.normal { ']c', bang = true }
          else
            gitsigns.nav_hunk 'next'
          end
        end, { desc = 'Jump to next git [c]hange' })

        map('n', '[c', function()
          if vim.wo.diff then
            vim.cmd.normal { '[c', bang = true }
          else
            gitsigns.nav_hunk 'prev'
          end
        end, { desc = 'Jump to previous git [c]hange' })

        -- Actions
        -- visual mode
        map('v', '<leader>vs', function()
          gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'VCS: stage hunk' })
        map('v', '<leader>vr', function()
          gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'VCS: rollback hunk' })
        -- normal mode
        map('n', '<leader>vs', gitsigns.stage_hunk, { desc = 'VCS: [s]tage hunk' })
        map('n', '<leader>vr', gitsigns.reset_hunk, { desc = 'VCS: [r]ollback hunk' })
        map('n', '<leader>vS', gitsigns.stage_buffer, { desc = 'VCS: [S]tage file' })
        map('n', '<leader>vu', gitsigns.undo_stage_hunk, { desc = 'VCS: [u]ndo stage hunk' })
        map('n', '<leader>vR', gitsigns.reset_buffer, { desc = 'VCS: [R]ollback file' })
        map('n', '<leader>vi', gitsigns.preview_hunk, { desc = 'VCS: [i]nspect hunk' })
        map('n', '<leader>vb', gitsigns.blame_line, { desc = 'VCS: [b]lame line' })
        map('n', '<leader>vD', function()
          gitsigns.diffthis '@'
        end, { desc = 'VCS: [D]iff file against last commit' })
        -- Toggles
        map('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git show [b]lame line' })
        map('n', '<leader>tD', gitsigns.toggle_deleted, { desc = '[T]oggle git show [D]eleted' })
      end,
    },
  },
}
