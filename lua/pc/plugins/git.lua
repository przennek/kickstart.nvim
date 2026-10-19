-- Git, IDEA style. Everything VCS lives under <leader>v (the VCS menu),
-- plus the tool windows: Alt+0 = Commit, Alt+9 = Git log.

-- Compare with Branch: pick a local or remote branch, then diff the current file
-- (or the whole working tree) against it in Diffview
local function diff_with(ref, file)
  vim.cmd('DiffviewOpen ' .. ref .. (file and (' -- ' .. vim.fn.fnameescape(file)) or ''))
end

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
          diff_with(entry.value, file_only and file or nil)
        end)
        return true
      end,
    }
  end
end

-- Git Branches popup (<leader>d in .ideavimrc): type e.g. origin/main, then
--   Enter   Show Diff with Working Tree (whole project)
--   Ctrl+F  compare only the current file with that branch
--   Ctrl+O  checkout the branch
local function branches_popup()
  local file = vim.fn.expand '%:p'
  require('telescope.builtin').git_branches {
    prompt_title = 'Git Branches · Enter: diff with working tree · C-f: this file · C-o: checkout',
    attach_mappings = function(prompt_bufnr, map)
      local actions = require 'telescope.actions'
      local state = require 'telescope.actions.state'
      actions.select_default:replace(function()
        local ref = state.get_selected_entry().value
        actions.close(prompt_bufnr)
        diff_with(ref)
      end)
      map({ 'i', 'n' }, '<C-f>', function()
        local ref = state.get_selected_entry().value
        actions.close(prompt_bufnr)
        diff_with(ref, file)
      end)
      map({ 'i', 'n' }, '<C-o>', actions.git_checkout)
      return true
    end,
  }
end

-- Tool windows toggle like in IDEA: the same key closes what it opened
local function diffview_toggle(cmd)
  return function()
    if package.loaded['diffview'] and require('diffview.lib').get_current_view() then
      vim.cmd 'DiffviewClose'
    else
      vim.cmd(cmd)
    end
  end
end

local function commit_window_toggle()
  local status = require 'neogit.buffers.status'
  if status.is_open() then
    status.instance():close()
  else
    vim.cmd 'Neogit'
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
      { '<M-0>', commit_window_toggle, desc = 'VCS: Commit window (toggle)' },
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
      { '<M-9>', diffview_toggle 'DiffviewFileHistory', desc = 'VCS: Git log (toggle)' },
      { '<leader>vl', '<cmd>DiffviewFileHistory<CR>', desc = 'VCS: [L]og' },
      { '<leader>vh', '<cmd>DiffviewFileHistory %<CR>', desc = 'VCS: File [h]istory' },
      { '<leader>vh', ":'<,'>DiffviewFileHistory<CR>", mode = 'v', desc = 'VCS: Selection history' },
      { '<leader>vd', '<cmd>DiffviewOpen<CR>', desc = 'VCS: [D]iff working tree' },
      { '<leader>vw', compare_with_branch(true), desc = 'VCS: Compare file [w]ith branch' },
      { '<leader>vW', compare_with_branch(false), desc = 'VCS: Compare project [W]ith branch' },
      { '<leader>d', branches_popup, desc = 'Git branches (diff with working tree)' },
      -- Show Diff (Cmd+D): the current file against HEAD
      { '<M-d>', diffview_toggle 'DiffviewOpen -- %', desc = 'VCS: Show diff of this file (toggle)' },
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
    config = function(_, opts)
      require('diffview').setup(opts)

      -- A file opened from a diff window (Go to Class, gd, the project tree…) goes to an editor
      -- split next to the diff, like in IDEA, instead of replacing one side of the diff.
      -- Otherwise Diffview would later reuse that window for the next file (F7) and the
      -- class you were reading would be gone.
      vim.api.nvim_create_autocmd('BufWinEnter', {
        group = vim.api.nvim_create_augroup('pc-diffview-guard', { clear = true }),
        callback = function(event)
          local win = vim.api.nvim_get_current_win()
          vim.schedule(function()
            local view = require('diffview.lib').get_current_view()
            if not view or not view.cur_layout or not vim.api.nvim_win_is_valid(win) then
              return
            end
            if vim.api.nvim_win_get_buf(win) ~= event.buf or vim.bo[event.buf].buftype ~= '' then
              return
            end
            local owner
            for _, w in ipairs(view.cur_layout.windows) do
              if w.id == win then
                owner = w
              end
            end
            if not owner or not owner.file or owner.file.bufnr == event.buf then
              return
            end
            -- Put the diff's own buffer back and show the file in an editor split instead
            local cursor = vim.api.nvim_win_get_cursor(win)
            vim.api.nvim_win_set_buf(win, owner.file.bufnr)
            local target
            for _, other in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
              local owned = other == view.panel.winid
              for _, w in ipairs(view.cur_layout.windows) do
                owned = owned or w.id == other
              end
              if not owned and vim.api.nvim_win_get_config(other).relative == '' then
                target = other
              end
            end
            if target then
              vim.api.nvim_set_current_win(target)
            else
              vim.cmd 'botright vsplit'
            end
            vim.api.nvim_win_set_buf(0, event.buf)
            pcall(vim.api.nvim_win_set_cursor, 0, cursor)
            -- a split made from a diff window inherits its diff-only window options
            vim.wo.diff = false
            vim.wo.scrollbind = false
            vim.wo.cursorbind = false
            vim.wo.foldenable = false
            vim.wo.foldcolumn = '0'
          end)
        end,
      })
    end,
  },
  -- Adds git related signs to the gutter, as well as utilities for managing changes
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      -- Inline blame of the current line, like GitToolbox
      current_line_blame = true,
      current_line_blame_opts = { delay = 500 },
      current_line_blame_formatter = '<author>, <author_time:%Y-%m-%d> · <summary>',
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

        -- - / + = previous / next changed hunk, as in .ideavimrc (VcsShowPrev/NextChangeMarker)
        map('n', '-', function()
          gitsigns.nav_hunk 'prev'
        end, { desc = 'Previous change marker' })
        map('n', '+', function()
          gitsigns.nav_hunk 'next'
        end, { desc = 'Next change marker' })

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
