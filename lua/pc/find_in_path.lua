-- Find in Path (Ctrl+Shift+F, <leader>sg) like IDEA's: the text is searched as typed (getPrice(
-- finds the call, not a regex error); Alt+X switches to a regular expression and back, keeping
-- the text. The choice is remembered for the next search. Alt+M sets the file mask (*.java,
-- !*Test.java: pc.file_mask). Hidden files (.gitignore, .github/…) are searched too, .git not.

local M = {}

local regex = false

--- Opens live grep; `opts` go to Telescope (prompt_title, default_text, attach_mappings…)
function M.open(opts)
  opts = vim.tbl_extend('force', {}, opts or {})
  local title = opts.prompt_title or 'Find in Path'
  local attach = opts.attach_mappings
  local file_mask = require 'pc.file_mask'
  opts.prompt_title = ('%s · %s%s · Alt+X: %s · Alt+M: mask'):format(title, regex and 'Regex' or 'Text', file_mask.label(), regex and 'text' or 'regex')
  opts.additional_args = function()
    local args = vim.list_extend({ '--hidden', '--glob', '!.git' }, file_mask.rg_args())
    return regex and args or vim.list_extend(args, { '--fixed-strings' })
  end
  opts.attach_mappings = function(prompt_bufnr, map)
    map({ 'i', 'n' }, '<M-x>', function()
      local text = require('telescope.actions.state').get_current_line()
      require('telescope.actions').close(prompt_bufnr)
      regex = not regex
      M.open(vim.tbl_extend('force', opts, { prompt_title = title, attach_mappings = attach, default_text = text }))
    end, { desc = 'Toggle regex' })
    map({ 'i', 'n' }, '<M-m>', function()
      local text = require('telescope.actions.state').get_current_line()
      require('telescope.actions').close(prompt_bufnr)
      file_mask.ask(function()
        M.open(vim.tbl_extend('force', opts, { prompt_title = title, attach_mappings = attach, default_text = text }))
      end)
    end, { desc = 'File mask' })
    return attach == nil or attach(prompt_bufnr, map)
  end
  require('telescope.builtin').live_grep(opts)
end

return M
