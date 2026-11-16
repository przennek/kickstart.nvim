-- Key names (pc.keys) and what Find Action shows of them: a modified F-key is mapped under both
-- spellings (in and outside tmux), the list of actions is the same every time and has no
-- plumbing entries. Prints OK / FAIL and quits.
local keys = require 'pc.keys'
local bad = {}
local function expect(what, got, want)
  if not vim.deep_equal(got, want) then
    table.insert(bad, ('%s: got %s, wanted %s'):format(what, vim.inspect(got), vim.inspect(want)))
  end
end

expect('S-F2', keys.f 'S-F2', { '<S-F2>', '<F14>' })
expect('C-F11', keys.f 'C-F11', { '<C-F11>', '<F35>' })
expect('C-S-F10', keys.f 'C-S-F10', { '<C-S-F10>', '<F46>' })
expect('M-F2', keys.f 'M-F2', { '<M-F2>', '<F50>' })
expect('M-S-F12', keys.f 'M-S-F12', { '<M-S-F12>', '<F72>' })
expect('plain F2', keys.f 'F2', { '<F2>' })
expect('no tmux number', keys.f 'C-M-F1', { '<C-M-F1>' })
expect('a ready key', keys.f '<leader>x', { '<leader>x' })
expect('flat', keys.flat { '<M-n>', 'M-F12', keys.CTRL_TAB }, { '<M-n>', '<M-F12>', '<F60>', '<F37>' })
expect('label', { keys.label '<F14>', keys.label '<F72>', keys.label '<F12>', keys.label '<F73>' }, { 'Shift+F2', 'Alt+Shift+F12' })
local specs = keys.lazy { { 'S-F11', 'rhs', desc = 'd', mode = 'x' }, { '<F11>', 'rhs' }, '<leader>q' }
expect('lazy specs', specs, { { '<S-F11>', 'rhs', desc = 'd', mode = 'x' }, { '<F23>', 'rhs', desc = 'd', mode = 'x' }, { '<F11>', 'rhs' }, '<leader>q' })

-- both spellings are mapped, to the same thing
for _, name in ipairs { 'S-F2', 'M-F1', 'S-F10', 'C-S-F10', 'C-S-F9', 'C-S-F12', 'M-F2', 'S-F12', 'S-F3', 'M-F3' } do
  local both = keys.f(name)
  local a, b = vim.fn.maparg(both[1], 'n', false, true), vim.fn.maparg(both[2], 'n', false, true)
  if not a.desc or a.desc ~= b.desc then
    table.insert(bad, name .. ': ' .. tostring(a.desc) .. ' / ' .. tostring(b.desc))
  end
end

-- Find Action: the same list twice, shortcuts as you press them, no plumbing
local function listing()
  return vim.tbl_map(function(a)
    return a.name .. ' = ' .. a.keys .. ' -> ' .. tostring(a.run.lhs)
  end, require('pc.actions').list())
end
local first = listing()
expect('the list is stable', listing(), first)
local shown = table.concat(first, '\n')
if shown:find('IDE shortcut', 1, true) then
  table.insert(bad, 'plumbing mappings are listed')
end
if not shown:find('Switch Project = ␣P, Alt+F2 ', 1, true) then
  table.insert(bad, 'Switch Project: ' .. (shown:match 'Switch Project[^\n]*' or 'not listed'))
end
if not shown:find('Hide / restore all tool windows = Alt+Shift+F12 ', 1, true) then
  table.insert(bad, 'Hide all: ' .. (shown:match 'Hide / restore[^\n]*' or 'not listed'))
end
io.stdout:write((#bad == 0 and 'OK keys' or ('FAIL keys: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
