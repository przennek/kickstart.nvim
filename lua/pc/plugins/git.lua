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

-- Compare with Revision… (Git menu of IDEA): the commits that changed this file, with what each
-- changed in the preview; Enter diffs the file as it is now against that revision
local function compare_with_revision()
  local file = vim.fn.expand '%:p'
  if file == '' or vim.bo.buftype ~= '' then
    return vim.notify('Compare with Revision: open a file first', vim.log.levels.INFO)
  end
  if vim.fn.systemlist({ 'git', '-C', vim.fs.dirname(file), 'ls-files', '--error-unmatch', file })[1] == nil or vim.v.shell_error ~= 0 then
    return vim.notify('Compare with Revision: ' .. vim.fn.expand '%:t' .. ' is not in git', vim.log.levels.INFO)
  end
  require('telescope.builtin').git_bcommits {
    prompt_title = 'Compare ' .. vim.fn.expand '%:t' .. ' with revision',
    attach_mappings = function(prompt_bufnr)
      local actions = require 'telescope.actions'
      actions.select_default:replace(function()
        local entry = require('telescope.actions.state').get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          diff_with(entry.value, file)
        end
      end)
      return true
    end,
  }
end

-- Compare with Local in the Git log / file history (D): the revision under the cursor against the
-- working tree — that file (a file of the commit, or the file whose history this is), else the
-- whole commit
local function compare_with_local()
  local view = require('diffview.lib').get_current_view()
  local panel = view and view.panel
  local item = panel and panel.get_item_at_cursor and panel:get_item_at_cursor()
  local entry = panel and panel.get_log_entry_at_cursor and panel:get_log_entry_at_cursor()
  if not entry or not entry.commit then
    return vim.notify('Compare with Local: put the cursor on a revision', vim.log.levels.INFO)
  end
  local path = item and item ~= entry and item.path or nil
  local single = panel.log_options and panel.log_options.single_file
  if not path and single and single.path_args and #single.path_args == 1 and #entry.files == 1 then
    path = entry.files[1].path
  end
  local dir = view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel or vim.fn.getcwd()
  local hash = entry.commit.hash
  vim.cmd 'DiffviewClose'
  diff_with(hash, path and vim.fs.joinpath(dir, path) or nil)
end

-- Git Branches popup (<leader>d in .ideavimrc): type e.g. origin/main, then
--   Enter   Show Diff with Working Tree (all changed files, in the current split)
--   Ctrl+F  compare only the current file with that branch
--   Ctrl+O  checkout the branch
local function branches_popup()
  local file = vim.fn.expand '%:p'
  require('telescope.builtin').git_branches {
    prompt_title = 'Git Branches · Enter: diff with working tree · C-f: this file · C-o: checkout',
    attach_mappings = function(prompt_bufnr, map)
      local actions = require 'telescope.actions'
      local state = require 'telescope.actions.state'
      -- the diff opens in the split you are in (see lua/pc/split_diff.lua)
      actions.select_default:replace(function()
        local ref = state.get_selected_entry().value
        actions.close(prompt_bufnr)
        require('pc.split_diff').open(ref)
      end)
      map({ 'i', 'n' }, '<C-f>', function()
        local ref = state.get_selected_entry().value
        actions.close(prompt_bufnr)
        require('pc.split_diff').open(ref, file)
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

-- Runs one of Neogit's commit actions (commit, amend…) like neogit.action('commit', name),
-- which loses the async context after the refresh
local function commit_action(name)
  require 'neogit'
  local async = require 'neogit.lib.async'
  require('neogit.lib.git').repo:dispatch_refresh {
    source = 'action',
    callback = function()
      async.void(function()
        require('neogit.popups.commit.actions')[name] {
          close = function() end,
          state = { env = {} },
          get_arguments = function()
            return {}
          end,
          get_internal_arguments = function()
            return {}
          end,
        }
      end)()
    end,
  }
end

-- Revert Commit from the Git log (gR on a commit in Alt+9 / <leader>vl / <leader>vh)
local function revert_commit()
  local view = require('diffview.lib').get_current_view()
  local item = view and view.panel and view.panel.get_item_at_cursor and view.panel:get_item_at_cursor()
  if not item or not item.commit then
    return vim.notify('Revert: put the cursor on a commit in the log', vim.log.levels.INFO)
  end
  local hash, subject = item.commit.hash, item.commit.subject or ''
  if vim.fn.confirm(('Revert commit %s "%s"?'):format(hash:sub(1, 10), subject), '&Revert\n&Cancel', 2) ~= 1 then
    return
  end
  local dir = view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel or vim.fn.getcwd()
  local r = vim.system({ 'git', '-C', dir, 'revert', '--no-edit', hash }, { text = true }):wait()
  if r.code == 0 then
    vim.notify(('Reverted %s: %s'):format(hash:sub(1, 10), subject))
  else
    vim.notify('Revert stopped:\n' .. vim.trim(r.stderr ~= '' and r.stderr or r.stdout) .. '\n(conflicts: <leader>vm, then <leader>vx / <leader>vX)', vim.log.levels.WARN)
  end
  vim.cmd 'silent! checktime'
end

-- Commit and Push (IDEA's Cmd+Alt+K): Neogit's commit message editor, then git push of the
-- current branch (setting its upstream on the first push)
local function push_current_branch()
  local upstream = vim.system({ 'git', 'rev-parse', '--abbrev-ref', '@{u}' }, { text = true }):wait()
  local cmd = upstream.code == 0 and { 'git', 'push' } or { 'git', 'push', '-u', 'origin', 'HEAD' }
  vim.notify 'Pushing…'
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      local out = vim.trim(result.stderr ~= '' and result.stderr or result.stdout or '')
      if result.code == 0 then
        vim.notify('Pushed: ' .. (out:match '[^\n]*$' or ''))
      else
        vim.notify('Push failed:\n' .. out, vim.log.levels.ERROR)
      end
      pcall(function()
        require('neogit').dispatch_refresh()
      end)
    end)
  end)
end

local function commit_and_push()
  local id
  local function forget()
    if id then
      pcall(vim.api.nvim_del_autocmd, id)
      id = nil
    end
  end
  id = vim.api.nvim_create_autocmd('User', {
    pattern = 'NeogitCommitComplete',
    once = true,
    callback = function()
      id = nil
      push_current_branch()
    end,
  })
  -- a cancelled commit must not push on the next one
  vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'gitcommit', 'NeogitCommitMessage' },
    once = true,
    callback = function(event)
      vim.api.nvim_create_autocmd('BufUnload', {
        buffer = event.buf,
        once = true,
        callback = function()
          vim.defer_fn(forget, 10000)
        end,
      })
    end,
  })
  vim.defer_fn(forget, 30 * 60 * 1000)
  commit_action 'commit'
end

-- Annotate (blame) like IDEA's: the same key shows and hides it; q in the blame window closes it
local function annotate_toggle()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'fugitiveblame' then
      return vim.api.nvim_win_close(win, false)
    end
  end
  vim.cmd 'Git blame'
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('pc-annotate', { clear = true }),
  pattern = 'fugitiveblame',
  callback = function(event)
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = event.buf, nowait = true, desc = 'Close Annotate' })
  end,
})

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
      { '<leader>va', annotate_toggle, desc = 'VCS: [A]nnotate (blame)' },
    },
  },
  -- Commit window, branches, push / pull
  {
    'NeogitOrg/neogit',
    dependencies = { 'nvim-lua/plenary.nvim', 'sindrets/diffview.nvim', 'nvim-telescope/telescope.nvim' },
    cmd = 'Neogit',
    keys = {
      {
        '<M-0>',
        function()
          local tw = require 'pc.tool_window'
          tw.activate(tw.filetypes 'NeogitStatus', commit_window_toggle)()
        end,
        desc = 'VCS: Commit window',
      },
      { '<leader>vv', '<cmd>Neogit<CR>', desc = 'VCS: Status / commit window' },
      { '<leader>vc', '<cmd>Neogit commit<CR>', desc = 'VCS: [C]ommit' },
      { '<leader>vC', commit_and_push, desc = 'VCS: [C]ommit and Push' },
      { '<leader>vA', function() commit_action 'amend' end, desc = 'VCS: [A]mend last commit' },
      -- Update Project: merge pull with autostash (Neogit's pull popup: p in the Alt+0 window)
      { '<leader>vp', function() require('pc.vcs_operations').update_project() end, desc = 'VCS: Update Project (pull)' },
      { '<leader>vP', '<cmd>Neogit push<CR>', desc = 'VCS: [P]ush' },
      { '<leader>vB', '<cmd>Telescope git_branches<CR>', desc = 'VCS: [B]ranches' },
      { '<leader>vf', '<cmd>Telescope git_status<CR>', desc = 'VCS: Changed [f]iles' },
    },
    opts = {
      integrations = { diffview = true, telescope = true },
      graph_style = 'unicode',
      -- Commit window (Alt+0) slides in at the bottom like an IDEA tool window, not a full tab
      kind = 'split_below_all',
    },
    init = function()
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'NeogitStatus',
        group = vim.api.nvim_create_augroup('pc-neogit-height', { clear = true }),
        callback = function()
          if #vim.api.nvim_tabpage_list_wins(0) > 1 then
            vim.api.nvim_win_set_height(0, math.max(12, math.floor(vim.o.lines * 0.4)))
            vim.wo.winfixheight = true
          end
        end,
      })
    end,
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
      { '<leader>vm', function() require('pc.merge').open() end, desc = 'VCS: Resolve conflicts ([m]erge tool)' },
      { '<leader>vx', function() require('pc.merge').continue() end, desc = 'VCS: Continue merge / rebase' },
      { '<leader>vX', function() require('pc.merge').abort() end, desc = 'VCS: Abort merge / rebase' },
      { '<leader>vw', compare_with_branch(true), desc = 'VCS: Compare file [w]ith branch' },
      { '<leader>vW', compare_with_branch(false), desc = 'VCS: Compare project [W]ith branch' },
      { '<leader>vo', compare_with_revision, desc = 'VCS: Compare file with revision ([o]lder version)' },
      { '<leader>d', branches_popup, desc = 'Git Branches' },
      -- Show Diff (Cmd+D): the current file against HEAD
      { '<M-d>', function() require('pc.split_diff').toggle_file_diff() end, desc = 'VCS: Show diff of this file (toggle)' },
    },
    opts = function()
      -- q closes a diff / history tab, like Esc on an IDEA dialog
      local close = { 'n', 'q', '<cmd>DiffviewClose<CR>', { desc = 'Close Diffview' } }
      local esc = { 'n', '<Esc>', '<cmd>DiffviewClose<CR>', { desc = 'Close Diffview' } }
      -- Merge tool: Accept Left / Right like IDEA, under <leader>m (<leader>c is Go to Class)
      local actions = require 'diffview.actions'
      local view = { close, esc }
      for _, lhs in ipairs { 'co', 'ct', 'cb', 'ca', 'cO', 'cT', 'cB', 'cA' } do
        table.insert(view, { 'n', '<leader>' .. lhs, false })
      end
      for key, side in pairs { l = 'ours', r = 'theirs', b = 'base', a = 'all', n = 'none' } do
        table.insert(view, { 'n', '<leader>m' .. key, actions.conflict_choose(side), { desc = 'Conflict: accept ' .. side } })
        table.insert(view, { 'n', '<leader>m' .. key:upper(), actions.conflict_choose_all(side), { desc = 'Conflicts in file: accept ' .. side } })
      end
      table.insert(view, {
        'n',
        '<leader>mm',
        function()
          require('pc.merge').resolve_simple()
        end,
        { desc = 'Resolve simple conflicts' },
      })
      return {
        keymaps = {
          view = view,
          file_panel = { close, esc },
          file_history_panel = {
            close,
            esc,
            { 'n', 'gR', revert_commit, { desc = 'Revert this commit' } },
            { 'n', 'D', compare_with_local, { desc = 'Compare with Local' } },
          },
        },
      }
    end,
  },
  -- Adds git related signs to the gutter, as well as utilities for managing changes
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      -- Inline blame of the current line, like GitToolbox
      current_line_blame = not vim.g.pc_settings or vim.g.pc_settings.inline_blame ~= false,
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
