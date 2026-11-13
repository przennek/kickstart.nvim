-- What you meant (pc.cmdline_enter, pc.autosave): :Wq / :Qa! are :wq / :qa!; a search that finds
-- nothing as a pattern but is in the file as typed is searched as typed; a new file saves itself,
-- a deleted one is not brought back. Writes in the scratch directory. Prints OK / FAIL and quits.
local bad = {}
local function expect(name, got, want)
  if got ~= want then
    table.insert(bad, ('%s: got %s, wanted %s'):format(name, vim.inspect(got), vim.inspect(want)))
  end
end
local dir = vim.env.WORK .. '/ux'
vim.fn.mkdir(dir, 'p')
local new = dir .. '/new.txt'
os.remove(new)
vim.cmd.edit(new)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello' })
vim.api.nvim_exec_autocmds('BufLeave', { buffer = 0 })
expect('a new file saves itself', vim.uv.fs_stat(new) ~= nil, true)
os.remove(new)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'again' })
vim.api.nvim_exec_autocmds('BufLeave', { buffer = 0 })
expect('a deleted file stays deleted', vim.uv.fs_stat(new), nil)
vim.cmd 'bwipe!'

vim.fn.writefile({ 'alias ll=ls', 'items[0] = 1' }, dir .. '/z.txt')
vim.cmd.edit(dir .. '/z.txt')
local enter = require('pc.cmdline_enter').enter
local function on(kind, line)
  local gt, gl = vim.fn.getcmdtype, vim.fn.getcmdline
  vim.fn.getcmdtype = function()
    return kind
  end
  vim.fn.getcmdline = function()
    return line
  end
  local keys = enter()
  vim.fn.getcmdtype, vim.fn.getcmdline = gt, gl
  return keys
end
expect(':Wq', on(':', 'Wq'), '<C-u>wq<CR>')
expect(':Qa!', on(':', 'Qa!'), '<C-u>qa!<CR>')
expect(':wq as it is', on(':', 'wq'), '<CR>')
expect(':Vs', on(':', 'Vs'), '<C-u>vs<CR>')
expect(":'<,'>q", on(':', "'<,'>q"), '<C-u>q<CR>')
expect(":'<,'>Wq", on(':', "'<,'>Wq"), '<C-u>wq<CR>')
expect(':Gitsigns stays', on(':', 'Lazy'), '<CR>')
expect('/items[0] as typed', on('/', 'items[0]'), '<C-u>\\Vitems[0]<CR>')
expect('/alias as it is', on('/', 'alias'), '<CR>')
expect('/missing as it is', on('/', 'missing'), '<CR>')
io.stdout:write('\n' .. (#bad == 0 and 'OK what you meant' or ('FAIL what you meant: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
