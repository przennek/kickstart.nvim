-- Search: file masks (Find in Path / Search Everywhere, Alt+M) and the files Go to File lists
-- (dotfiles yes, .git no). Run in the Java fixture (it has a .gitignore). Prints OK / FAIL and quits.
local fm = require 'pc.file_mask'
local bad = {}
local cases = {
  { '', 'src/A.java', true },
  { '*.java', 'src/A.java', true },
  { '*.java', 'pom.xml', false },
  { '*.java, *.xml', 'pom.xml', true },
  { '*.java, !*Test.java', 'src/ATest.java', false },
  { '!*Test.java', 'src/A.java', true },
  { '!*Test.java', 'src/ATest.java', false },
  { 'src/**/*.java', 'src/x/A.java', true },
  { 'src/**/*.java', 'test/A.java', false },
  { '.gitignore', '.gitignore', true },
  { '*.java', 'A.javax', false },
}
for _, c in ipairs(cases) do
  fm.set(c[1])
  if fm.matches(c[2]) ~= c[3] then
    table.insert(bad, ('mask %q on %s: %s'):format(c[1], c[2], tostring(not c[3])))
  end
end
fm.set '*.java, !*Test.java'
if table.concat(fm.rg_args(), ' ') ~= '--glob *.java --glob !*Test.java' then
  table.insert(bad, 'rg args: ' .. table.concat(fm.rg_args(), ' '))
end
fm.set ''
-- Go to File's command lists .gitignore and nothing from .git
local cmd = require('telescope.config').pickers.find_files.find_command
local files = vim.system(cmd, { text = true }):wait().stdout
if not files:find('\n%.gitignore\n') and not files:find('^%.gitignore\n') then
  table.insert(bad, 'Go to File: no .gitignore')
end
if files:find('%.git/') then
  table.insert(bad, 'Go to File: lists .git/')
end
io.stdout:write((#bad == 0 and 'OK search' or ('FAIL search: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
