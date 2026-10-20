-- Startup check of one file: language servers attached, no errors, the main IDE keys exist.
-- Prints one line "OK …" or "FAIL …" and quits. WAIT (ms) and SERVERS (comma list) from the env.
vim.defer_fn(function()
  local names = vim.tbl_map(function(c)
    return c.name
  end, vim.lsp.get_clients { bufnr = 0 })
  local problems = {}
  for want in (vim.env.SERVERS or ''):gmatch '[^,]+' do
    if not vim.tbl_contains(names, want) then
      table.insert(problems, 'no ' .. want)
    end
  end
  for _, lhs in ipairs { '<Space>sg', '<Space>vE', '<Space>z', '<F5>', '<F8>', '<M-0>', '<M-CR>', 'gd' } do
    if vim.fn.maparg(lhs, 'n') == '' and vim.fn.maparg(vim.keycode(lhs), 'n') == '' then
      table.insert(problems, 'no map ' .. lhs)
    end
  end
  for _, line in ipairs(vim.split(vim.fn.execute 'messages', '\n')) do
    if line:match 'E%d+:' or line:match 'rror' then
      table.insert(problems, 'message: ' .. line)
    end
  end
  for _, e in ipairs(require('pc.notifications').entries()) do
    if e.level == 'ERROR' then
      table.insert(problems, 'notification: ' .. e.msg:gsub('\n', ' '))
    end
  end
  local diags = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
  if diags > 0 then
    table.insert(problems, diags .. ' error diagnostics')
  end
  io.stdout:write((#problems == 0 and 'OK ' or 'FAIL ') .. vim.fn.expand '%:t' .. ' [' .. table.concat(names, ',') .. '] ' .. table.concat(problems, '; ') .. '\n')
  vim.cmd 'qa!'
end, tonumber(vim.env.WAIT or 10000))
