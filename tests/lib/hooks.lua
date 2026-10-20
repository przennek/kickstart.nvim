-- The plugin internals this config builds on still exist (a plugin update that changes them
-- makes this fail instead of a feature quietly stopping). Prints OK / FAIL and quits.
local problems = {}
local function need(what, value)
  if type(value) ~= 'function' then
    table.insert(problems, what)
  end
end
-- the debugger as the F-keys load it (nvim-dap, which sets up dap-ui)
require('lazy').load { plugins = { 'neo-tree.nvim', 'nvim-dap', 'toggleterm.nvim', 'telescope.nvim' } }
need('neo-tree manager.get_path_to_reveal (follow diffview / skip jdt:// buffers)', require('neo-tree.sources.manager').get_path_to_reveal)
need('dap-ui elements.watches.add (Copy Value / Add to Watches)', require('dapui').elements.watches.add)
need('toggleterm Terminal:open (Hide All restore)', require('toggleterm.terminal').Terminal.open)
need('vim.lsp.util.apply_workspace_edit (refactorings save files)', vim.lsp.util.apply_workspace_edit)
need('telescope sorter scoring_function (Search Everywhere)', require('telescope.config').values.generic_sorter({}).scoring_function)
local cfg = require('lazy.core.config').plugins['toggleterm.nvim']
if not (cfg and cfg.opts and cfg.opts.start_in_insert == false and cfg.opts.on_open) then
  table.insert(problems, 'toggleterm: typing mode set by on_open, not start_in_insert')
end
io.stdout:write((#problems == 0 and 'OK plugin hooks' or ('FAIL plugin hooks: ' .. table.concat(problems, '; '))) .. '\n')
vim.cmd 'qa!'
