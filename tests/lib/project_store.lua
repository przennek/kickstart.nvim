-- Project settings in .idea/nvim (pc.project_store): an entry of the old stdpath('data') file
-- moves into the project, the directory is ignored by git, outside a project nothing goes into
-- $HOME; run configurations and bookmarks land there. Run in a copy of the Java fixture (a git
-- repository). Prints OK / FAIL and quits.
local root = vim.fn.getcwd()
local data = vim.env.WORK .. '/store-data'
vim.fn.mkdir(data, 'p')
-- the old files are written in a scratch directory, not in the real stdpath('data')
local stdpath = vim.fn.stdpath
vim.fn.stdpath = function(what)
  return what == 'data' and data or stdpath(what)
end
local store = require 'pc.project_store'
local bad = {}
local function expect(what, got, want)
  if not vim.deep_equal(got, want) then
    table.insert(bad, ('%s: got %s, wanted %s'):format(what, vim.inspect(got), vim.inspect(want)))
  end
end
local function json(path)
  local ok, value = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
  return ok and value or nil
end

-- an old entry moves into the project, the other projects' entries stay
vim.fn.writefile({ vim.json.encode { [root] = { sdk = '/jdk/21' }, ['/elsewhere'] = { sdk = '/jdk/17' } } }, data .. '/pc_project.json')
expect('migrated value', store.get(root, 'project', 'pc_project.json'), { sdk = '/jdk/21' })
expect('in .idea', json(root .. '/.idea/nvim/project.json'), { sdk = '/jdk/21' })
expect('old entry gone', json(data .. '/pc_project.json'), { ['/elsewhere'] = { sdk = '/jdk/17' } })
expect('read again', store.get(root, 'project', 'pc_project.json'), { sdk = '/jdk/21' })
expect('git ignores it', vim.trim(vim.fn.system { 'git', '-C', root, 'status', '--porcelain', '--untracked-files=all' }), '')

-- outside a project: the old file, no ~/.idea
local home = vim.fs.normalize '~'
local had_idea = vim.uv.fs_stat(home .. '/.idea') ~= nil
store.set(home, 'run_anything', { 'ls' }, 'pc_run_anything.json')
expect('home value', store.get(home, 'run_anything', 'pc_run_anything.json'), { 'ls' })
expect('no ~/.idea/nvim', had_idea or vim.uv.fs_stat(home .. '/.idea') == nil, true)
expect('home in the data file', json(data .. '/pc_run_anything.json'), { [home] = { 'ls' } })

-- removing
store.set(root, 'project', nil, 'pc_project.json')
expect('removed', store.get(root, 'project', 'pc_project.json'), nil)

-- run configurations of the project
vim.cmd.edit 'src/main/java/example/shop/OrderService.java'
local rc = require 'pc.run_configs'
expect('no run configurations', rc.list(), {})
vim.fn.writefile({ vim.json.encode { [root] = { { name = 'App', type = 'Shell command', command = 'make' } } } }, data .. '/run_configs.json')
expect('old run configuration', rc.list()[1] and rc.list()[1].name, 'App')
expect('run configurations in .idea', vim.uv.fs_stat(root .. '/.idea/nvim/run_configs.json') ~= nil, true)

-- a bookmark goes to the project's file
require('lazy').load { plugins = { 'bookmarks.nvim' } }
require('bookmarks.config').config.save_file = data .. '/bookmarks'
vim.api.nvim_win_set_cursor(0, { 3, 0 })
require('bookmarks').bookmark_toggle()
require('bookmarks.actions').saveBookmarks()
vim.wait(2000, function()
  local marks = json(root .. '/.idea/nvim/bookmarks.json')
  return marks and marks.data and marks.data['src/main/java/example/shop/OrderService.java'] ~= nil
end)
local marks = json(root .. '/.idea/nvim/bookmarks.json') or {}
expect('bookmark in .idea', marks.data and marks.data['src/main/java/example/shop/OrderService.java'] ~= nil, true)
expect('git still clean', vim.trim(vim.fn.system { 'git', '-C', root, 'status', '--porcelain', '--untracked-files=all' }), '')

io.stdout:write('\n' .. (#bad == 0 and 'OK project store' or ('FAIL project store: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
