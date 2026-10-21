-- Files the IDE creates / renames / moves go into git (pc.git_track): a new file, a renamed
-- tracked file, a moved directory; not ignored files, not a rename of an untracked file.
-- Run in the Java fixture (a git repository). Prints OK / FAIL and quits.
local gt = require 'pc.git_track'
local root = vim.fn.getcwd()
local bad = {}
local function status(rel)
  return vim.trim(vim.fn.system({ 'git', '-C', root, 'status', '--porcelain', '--', rel }):sub(1, 2))
end
local function expect(what, got, want)
  if got ~= want then
    table.insert(bad, ('%s: got %q, wanted %q'):format(what, got, want))
  end
end
local pkg = root .. '/src/main/java/example/shop'
-- a new file
vim.fn.writefile({ 'class N {}' }, pkg .. '/N.java')
gt.add(pkg .. '/N.java')
expect('new file', status 'src/main/java/example/shop/N.java', 'A')
-- a renamed tracked file
gt.move(pkg .. '/App.java', pkg .. '/Main.java', function()
  vim.uv.fs_rename(pkg .. '/App.java', pkg .. '/Main.java')
end)
expect('renamed file', status 'src/main/java/example/shop/Main.java', 'A')
-- moving a file that was only added (never committed) leaves no deleted entry behind
gt.move(pkg .. '/N.java', pkg .. '/M.java', function()
  vim.uv.fs_rename(pkg .. '/N.java', pkg .. '/M.java')
end)
expect('moved new file: old entry gone', status 'src/main/java/example/shop/N.java', '')
expect('moved new file: new one added', status 'src/main/java/example/shop/M.java', 'A')
-- an ignored file
vim.fn.mkdir(root .. '/target', 'p')
vim.fn.writefile({ 'x' }, root .. '/target/out.txt')
gt.add(root .. '/target/out.txt')
expect('ignored file', status 'target/out.txt', '')
-- a rename of an untracked file stays untracked
vim.fn.writefile({ 'x' }, root .. '/scratch.txt')
gt.move(root .. '/scratch.txt', root .. '/scratch2.txt', function()
  vim.uv.fs_rename(root .. '/scratch.txt', root .. '/scratch2.txt')
end)
expect('renamed untracked file', status 'scratch2.txt', '??')
-- a moved directory (the index still knows the old path afterwards, as after a tree move)
vim.uv.fs_rename(root .. '/src/test', root .. '/src/check')
gt.add(root .. '/src/check', root .. '/src/test', gt.tracked(root .. '/src/test'))
expect('moved directory', status 'src/check/java/example/shop/OrderServiceTest.java', 'A')
io.stdout:write((#bad == 0 and 'OK git track' or ('FAIL git track: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
