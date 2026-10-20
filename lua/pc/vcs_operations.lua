-- VCS Operations popup like IDEA's (VCS → VCS Operations…): every git action in one list with
-- its shortcut, so the ones you don't remember are one search away.
--   <leader>V / :VcsOperations
--   <leader>vn   Copy Revision Number of the commit that last changed the current line (in the Git
--                log, Alt+9, y copies the hash of the commit under the cursor)
-- The entries run the existing mappings, so the popup and the shortcuts always do the same thing.

local M = {}

local ITEMS = {
  { 'Commit…', '<leader>vc' },
  { 'Commit and Push…', '<leader>vC' },
  { 'Amend last commit…', '<leader>vA' },
  { 'Commit window (status, stage, discard)', '<M-0>' },
  { 'Push…', '<leader>vP' },
  { 'Pull / Update Project', '<leader>vp' },
  { 'Branches…', '<leader>d' },
  { 'Show Log (y copy hash, gR revert commit)', '<M-9>' },
  { 'Show History of this file', '<leader>vh' },
  { 'Local History of this file', '<leader>vH' },
  { 'Annotate (blame)', '<leader>va' },
  { 'Copy Revision Number of this line', '<leader>vn' },
  { 'Show Diff of this file', '<M-d>' },
  { 'Diff working tree', '<leader>vd' },
  { 'Compare file with Branch…', '<leader>vw' },
  { 'Compare project with Branch…', '<leader>vW' },
  { 'Compare with Clipboard', '<leader>vy' },
  { 'Compare file with another file…', '<leader>v=' },
  { 'Changed Files…', '<leader>vf' },
  { 'Rollback change (hunk)', '<leader>vr' },
  { 'Rollback file', '<leader>vR' },
  { 'Stage change (hunk)', '<leader>vs' },
  { 'Stage file', '<leader>vS' },
  { 'Resolve Conflicts…', '<leader>vm' },
  { 'Continue merge / rebase', '<leader>vx' },
  { 'Abort merge / rebase', '<leader>vX' },
  { 'Stash / Unstash…', 'stash' },
}

local function shown(lhs)
  if lhs == 'stash' then
    return ''
  end
  return (lhs:gsub('<leader>', '␣'):gsub('<M%-(.)>', 'Alt+%1'))
end

function M.open()
  local buf = vim.api.nvim_get_current_buf()
  local items = vim.tbl_filter(function(item)
    -- per-buffer git mappings (hunks) only where gitsigns is attached
    local lhs = item[2]
    return lhs == 'stash' or vim.fn.maparg(vim.keycode(lhs:gsub('<leader>', ' ')), 'n') ~= '' or vim.fn.maparg(lhs, 'n') ~= ''
  end, ITEMS)
  vim.ui.select(items, {
    prompt = 'VCS Operations',
    format_item = function(item)
      return item[1] .. string.rep(' ', 42 - vim.fn.strdisplaywidth(item[1])) .. shown(item[2])
    end,
  }, function(item)
    if not item then
      return
    end
    if item[2] == 'stash' then
      return require('neogit').open { 'stash' }
    end
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_feedkeys(vim.keycode(item[2]:gsub('<leader>', ' ')), 'm', false)
  end)
end

--- Copy Revision Number: hash of the commit that last changed the current line
function M.copy_revision()
  local file = vim.api.nvim_buf_get_name(0)
  local line = vim.fn.line '.'
  local r = vim.system({ 'git', '-C', vim.fs.dirname(file), 'blame', '--porcelain', '-L', line .. ',' .. line, '--', file }, { text = true }):wait()
  local hash = r.code == 0 and r.stdout:match '^(%x+)'
  if not hash then
    return vim.notify('Copy Revision: not a file in a git repository', vim.log.levels.WARN)
  end
  if hash:match '^0+$' then
    return vim.notify('Copy Revision: this line is not committed yet', vim.log.levels.INFO)
  end
  local summary = r.stdout:match '\nsummary ([^\n]*)' or ''
  vim.fn.setreg('+', hash)
  vim.fn.setreg('"', hash)
  vim.notify(('Copied %s  %s'):format(hash:sub(1, 10), summary))
end

vim.keymap.set('n', '<leader>V', M.open, { desc = '[V]CS Operations…' })
vim.keymap.set('n', '<leader>vn', M.copy_revision, { desc = 'VCS: Copy revision [n]umber of this line' })
vim.api.nvim_create_user_command('VcsOperations', M.open, { desc = 'VCS Operations' })

return M
