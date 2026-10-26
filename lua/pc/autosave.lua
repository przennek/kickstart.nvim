-- Files save themselves, as in IDEA (no :wa before git / a build in the terminal):
--   leaving a window or a buffer, the terminal getting the focus, Neovim losing the focus
--   (another tmux pane / app), and 1 s after you stop typing / changing text
-- Settings → Editor → "Save files automatically" turns it off.

local M = {}

local function enabled()
  local cfg = vim.g.pc_settings
  return not (cfg and cfg.autosave == false)
end

local function changed_on_disk(buf, name)
  local loaded = vim.b[buf].pc_mtime
  local stat = vim.uv.fs_stat(name)
  return loaded ~= nil and stat ~= nil and (stat.mtime.sec .. '.' .. stat.mtime.nsec) ~= loaded
end

local function savable(buf)
  local bo = vim.bo[buf]
  local name = vim.api.nvim_buf_get_name(buf)
  return vim.api.nvim_buf_is_loaded(buf)
    and bo.modified
    and bo.buftype == ''
    and bo.modifiable
    and not bo.readonly
    and name ~= ''
    and not name:match '^%a[%w+.-]*://'
    -- a file deleted or moved away is not brought back
    and vim.uv.fs_stat(name) ~= nil
    -- changed on disk since loaded (git, an agent): yours or theirs stays your choice (pc.autoreload)
    and not changed_on_disk(buf, name)
end

--- Saves `buf` (default: every buffer) when it has unsaved changes
function M.save(buf)
  if not enabled() then
    return
  end
  for _, b in ipairs(buf and { buf } or vim.api.nvim_list_bufs()) do
    if savable(b) then
      vim.api.nvim_buf_call(b, function()
        vim.cmd 'silent! lockmarks keepjumps update'
      end)
    end
  end
end

local group = vim.api.nvim_create_augroup('pc-autosave', { clear = true })
vim.api.nvim_create_autocmd({ 'FocusLost', 'BufLeave', 'WinLeave', 'TermEnter', 'VimSuspend' }, {
  group = group,
  -- the write's own events (Local History, the reload watcher, LSP didSave) run as for :w
  nested = true,
  callback = function()
    M.save()
  end,
})

-- after typing: not while in Insert mode (a half-written line would be formatted / linted)
local timer = vim.uv.new_timer()
vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
  group = group,
  callback = function(event)
    if not enabled() or not savable(event.buf) then
      return
    end
    timer:stop()
    timer:start(
      1000,
      0,
      vim.schedule_wrap(function()
        if vim.api.nvim_buf_is_valid(event.buf) and not vim.fn.mode():match '^[iR]' then
          M.save(event.buf)
        end
      end)
    )
  end,
})

return M
