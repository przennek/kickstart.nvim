-- Debugger check: a breakpoint at BP_FILE:BP_LINE, then START (a Lua snippet run in the start
-- buffer: the test class, the nearest test, a program…); prints "STOPPED file:line" or "TIMEOUT".
vim.defer_fn(function()
  require('lazy').load { plugins = { 'nvim-dap' } }
  local dap = require 'dap'
  local start_buf = vim.api.nvim_get_current_buf()
  local start_pos = vim.api.nvim_win_get_cursor(0)
  vim.cmd.edit(vim.env.BP_FILE)
  vim.api.nvim_win_set_cursor(0, { tonumber(vim.env.BP_LINE), 0 })
  dap.set_breakpoint()
  vim.api.nvim_set_current_buf(start_buf)
  vim.api.nvim_win_set_cursor(0, start_pos)
  dap.listeners.after.event_stopped['tests'] = function(session, body)
    vim.defer_fn(function()
      local f = session.current_frame or {}
      local source = f.source or {}
      io.stdout:write(('STOPPED %s:%s (%s)\n'):format(source.name or (source.path and vim.fs.basename(source.path)) or '?', f.line or '?', body.reason))
      dap.terminate()
      vim.defer_fn(function()
        vim.cmd 'qa!'
      end, 1500)
    end, 1500)
  end
  assert(load(vim.env.START))()
  vim.defer_fn(function()
    io.stdout:write 'TIMEOUT\n'
    vim.cmd 'qa!'
  end, 60000)
end, tonumber(vim.env.WAIT or 25000))
