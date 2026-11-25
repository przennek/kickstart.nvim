-- Split lines on the seam of two monitors (pc.span), headless, no plugins:
--   nvim --headless --clean -u NONE -n -i NONE -c 'luafile tests/span.lua'
-- Exit status: the number of failures.
vim.o.columns = 601; vim.o.lines = 60
local here = vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)))
local M = dofile(here .. "/../lua/pc/span.lua")

local fails = 0
local function sep_cols()
  -- columns of vertical separators per screen row 2 (top)/ bottom
  local out = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local p = vim.fn.win_screenpos(w)
    table.insert(out, (p[2]-1 + vim.api.nvim_win_get_width(w)) .. '@' .. p[1])
  end
  table.sort(out); return table.concat(out, ' ')
end
local function check(label)
  M.apply()
  local seam = M.seam()
  local ok = false
  local function walk(node)
    if node[1] == 'row' then
      for k = 1, #node[2]-1 do
        local function ext(n) if n[1]=='leaf' then local p=vim.fn.win_screenpos(n[2]) return p[2]-1, vim.api.nvim_win_get_width(n[2]) end local c,_=ext(n[2][1]) local lc,lw=ext(n[2][#n[2]]) return c, lc+lw-c end
        local c,w = ext(node[2][k]); if c+w == seam then ok = true end
      end
    end
    if node[1] ~= 'leaf' then for _,k in ipairs(node[2]) do walk(k) end end
  end
  walk(vim.fn.winlayout())
  print((ok and 'ok   ' or 'FAIL ') .. label .. '  seam=' .. seam .. '  ' .. sep_cols())
  if not ok then fails = fails + 1 end
end
vim.cmd 'vsplit'; check('vs')
vim.cmd 'vsplit'; check('vs in the left half')
vim.cmd 'wincmd l'; vim.cmd 'wincmd l'; vim.cmd 'vsplit'; vim.cmd 'vsplit'; check('two more in the right half')
vim.cmd 'split'; check('sp in the right half')
vim.cmd 'only'; vim.cmd 'split'; vim.cmd 'vsplit'; check('sp then vs in the top')
vim.cmd 'wincmd j'; vim.cmd 'vsplit'; vim.cmd 'vsplit'; check('bottom row too')
vim.cmd 'topleft vertical 30 new'; vim.wo.winfixwidth = true; TREE = vim.api.nvim_get_current_win(); check('tree on the far left')
local function expect(label, got, want) local ok = got == want print((ok and 'ok   ' or 'FAIL ')..label..': '..tostring(got)) if not ok then fails = fails + 1 end end
expect('tree keeps 30', vim.api.nvim_win_get_width(TREE), 30)
vim.cmd 'botright vertical 40 new'; vim.wo.winfixwidth = true; PANEL = vim.api.nvim_get_current_win(); check('panel on the far right')
expect('panel keeps 40', vim.api.nvim_win_get_width(PANEL), 40)
expect('tree still 30', vim.api.nvim_win_get_width(TREE), 30)
vim.cmd 'close'; check('close it')
vim.o.columns = 611; check('terminal resized')
vim.cmd 'tabnew'; vim.cmd 'vsplit'; vim.cmd 'vsplit'; vim.cmd 'vertical resize 400'; check('dragged an editor window wide')
vim.cmd 'tabnew'; vim.cmd 'topleft vertical 30 new'; vim.wo.winfixwidth = true; local t = vim.api.nvim_get_current_win(); M.apply()
expect('tree + one editor: tree stays 30', vim.api.nvim_win_get_width(t), 30)
vim.cmd 'wincmd l'; vim.cmd 'vsplit'; check('tree + :vs: line on the seam'); expect('tree + :vs: tree 30', vim.api.nvim_win_get_width(t), 30)
vim.cmd 'tabnew'; vim.cmd 'vsplit'; vim.o.columns = 200
print((M.enabled() and 'FAIL ' or 'ok   ') .. 'narrow window: off')
os.exit(fails)
