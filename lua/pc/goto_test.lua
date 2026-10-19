-- Go to Test (Cmd+Shift+T -> Alt+Shift+T) for Python and C; Java uses jdtls (java.lua).
-- foo.py <-> test_foo.py / foo_test.py,  foo.c <-> test_foo.c / foo_test.c, anywhere in
-- the project. Several candidates -> a list; none -> offer to create tests/test_foo.<ext>.

local M = {}

local function root(buf)
  return vim.fs.root(buf, { 'pyproject.toml', 'setup.py', 'Makefile', 'CMakeLists.txt', '.git' }) or vim.fn.getcwd()
end

local function find(dir, names)
  local args = { 'rg', '--files', dir }
  for _, n in ipairs(names) do
    vim.list_extend(args, { '-g', '**/' .. n })
  end
  local out = vim.system(args, { text = true }):wait()
  return vim.split(vim.trim(out.stdout or ''), '\n', { trimempty = true })
end

function M.go()
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local ext = vim.fn.fnamemodify(file, ':e')
  local stem = vim.fn.fnamemodify(file, ':t:r')
  local dir = root(buf)

  local subject = stem:match '^test_(.+)$' or stem:match '^(.+)_test$'
  local candidates, create
  if subject then
    candidates = find(dir, { subject .. '.' .. ext })
  else
    candidates = find(dir, { 'test_' .. stem .. '.' .. ext, stem .. '_test.' .. ext })
    create = vim.fs.joinpath(dir, 'tests', 'test_' .. stem .. '.' .. ext)
  end

  local function open(path)
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  if #candidates == 1 then
    return open(candidates[1])
  end
  if #candidates > 1 then
    return vim.ui.select(candidates, {
      prompt = subject and 'Go to subject' or 'Go to test',
      format_item = function(p)
        return vim.fs.relpath(dir, p) or p
      end,
    }, function(p)
      if p then
        open(p)
      end
    end)
  end
  if not create then
    return vim.notify('No file under test found for ' .. stem, vim.log.levels.WARN)
  end
  vim.ui.select({ 'Create ' .. (vim.fs.relpath(dir, create) or create) }, { prompt = 'No test found' }, function(choice)
    if choice then
      vim.fn.mkdir(vim.fs.dirname(create), 'p')
      open(create)
    end
  end)
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'python', 'c', 'cpp' },
  group = vim.api.nvim_create_augroup('pc-goto-test', { clear = true }),
  callback = function(event)
    vim.keymap.set('n', '<M-T>', M.go, { buffer = event.buf, desc = 'Go to test / subject' })
  end,
})

return M
