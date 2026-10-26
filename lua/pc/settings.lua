-- Settings like IDEA's (Ctrl+Alt+S): one place for every settings dialog (pc.form).
--   Ctrl+Alt+S / <leader>, / :Settings   Editor, Appearance, HTTP Proxy, Project
--                                        Structure, Maven, Run/Debug Configurations
-- Editor holds what IDEA keeps under Editor → General / Appearance (whitespace, soft wraps, line
-- numbers, caret line, inlay hints, breadcrumbs, indentation, format on save, inline blame,
-- notifications); it is saved in
-- stdpath('data')/pc_settings.json and applied at startup.

local M = {}

local FILE = vim.fn.stdpath 'data' .. '/pc_settings.json'

-- your IDEA: whitespace shown, soft wraps only in consoles, no inlay hints, no breadcrumbs
local DEFAULTS = {
  whitespace = true,
  soft_wraps = false,
  line_numbers = 'Relative',
  caret_row = true,
  scroll_offset = '1',
  inlay_hints = false,
  breadcrumbs = false,
  indent = '4',
  use_tabs = false,
  format_on_save = false,
  autosave = true,
  inline_blame = true,
  notify_echo_errors = true,
  notify_status_bar = true,
  telemetry = true,
}

local function read()
  local f = io.open(FILE)
  if not f then
    return vim.deepcopy(DEFAULTS)
  end
  local ok, cfg = pcall(vim.json.decode, f:read '*a')
  f:close()
  return vim.tbl_extend('force', DEFAULTS, ok and type(cfg) == 'table' and cfg or {})
end

--- Applies the editor settings to every window and to new ones
function M.apply(cfg)
  cfg = cfg or read()
  vim.g.pc_settings = cfg
  local function window(win)
    vim.wo[win].list = cfg.whitespace
    vim.wo[win].wrap = cfg.soft_wraps
    vim.wo[win].number = cfg.line_numbers == 'Absolute' or cfg.line_numbers == 'Hybrid'
    vim.wo[win].relativenumber = cfg.line_numbers == 'Relative' or cfg.line_numbers == 'Hybrid'
    vim.wo[win].cursorline = cfg.caret_row
  end
  vim.o.list, vim.o.wrap, vim.o.cursorline = cfg.whitespace, cfg.soft_wraps, cfg.caret_row
  vim.o.number = cfg.line_numbers == 'Absolute' or cfg.line_numbers == 'Hybrid'
  vim.o.relativenumber = cfg.line_numbers == 'Relative' or cfg.line_numbers == 'Hybrid'
  vim.o.scrolloff = tonumber(cfg.scroll_offset) or 1
  vim.o.shiftwidth = tonumber(cfg.indent) or 4
  vim.o.tabstop = tonumber(cfg.indent) or 4
  vim.o.expandtab = not cfg.use_tabs
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == '' then
      window(win)
    end
  end
  pcall(vim.lsp.inlay_hint.enable, cfg.inlay_hints)
  vim.g.pc_format_on_save = cfg.format_on_save
  if package.loaded.gitsigns then
    require('gitsigns').toggle_current_line_blame(cfg.inline_blame)
  end
  vim.g.pc_breadcrumbs = cfg.breadcrumbs
  if package.loaded.dropbar then
    pcall(vim.cmd, 'doautoall BufWinEnter')
    if not cfg.breadcrumbs then
      -- dropbar leaves an empty bar behind; the navigation bar key (Alt+Home) still works
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.wo[win].winbar:find 'dropbar' and not vim.w[win].pc_navbar then
          vim.wo[win].winbar = ''
        end
      end
    end
  end
end

-- new file windows follow the settings too (plugins' own windows keep theirs)
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = vim.api.nvim_create_augroup('pc-settings', { clear = true }),
  callback = function(event)
    local cfg = vim.g.pc_settings
    if not cfg or vim.bo[event.buf].buftype ~= '' then
      return
    end
    vim.wo.list, vim.wo.wrap, vim.wo.cursorline = cfg.whitespace, cfg.soft_wraps, cfg.caret_row
    vim.wo.number = cfg.line_numbers == 'Absolute' or cfg.line_numbers == 'Hybrid'
    vim.wo.relativenumber = cfg.line_numbers == 'Relative' or cfg.line_numbers == 'Hybrid'
  end,
})

function M.editor()
  require('pc.form').open {
    title = 'Settings: Editor',
    values = read(),
    fields = {
      { header = 'Appearance' },
      { key = 'whitespace', label = 'Show whitespaces', check = true },
      { key = 'soft_wraps', label = 'Soft-wrap lines', check = true },
      { key = 'line_numbers', label = 'Line numbers', choices = { 'Relative', 'Absolute', 'Hybrid', 'Off' } },
      { key = 'caret_row', label = 'Highlight caret row', check = true },
      { key = 'scroll_offset', label = 'Scroll offset (lines)' },
      { key = 'breadcrumbs', label = 'Breadcrumbs', check = true },
      { header = 'Code' },
      { key = 'inlay_hints', label = 'Inlay hints', check = true },
      { key = 'indent', label = 'Indent (new files)' },
      { key = 'use_tabs', label = 'Use tab character', check = true },
      { key = 'format_on_save', label = 'Reformat code on save', check = true },
      { key = 'autosave', label = 'Save files automatically', check = true },
      { header = 'Version Control' },
      { key = 'inline_blame', label = 'Inline blame of the line', check = true },
      { header = 'Notifications (<leader>tn)' },
      { key = 'notify_echo_errors', label = 'Show errors in the command line', check = true },
      { key = 'notify_status_bar', label = 'Show the last message in the status bar', check = true },
      { key = 'telemetry', label = 'Record my moves in the error log (:ErrorLog)', check = true },
    },
    buttons = {
      {
        label = 'OK',
        key = '<C-s>',
        run = function(values, form)
          local f = assert(io.open(FILE, 'w'))
          f:write(vim.json.encode(values))
          f:close()
          M.apply(values)
          form:close()
          vim.notify 'Editor settings saved'
        end,
      },
      {
        label = 'Reset',
        key = '<C-r>',
        run = function(_, form)
          for k, v in pairs(DEFAULTS) do
            form.values[k] = v
          end
          form:render()
        end,
      },
    },
  }
end

local PAGES = {
  { label = 'Editor', open = M.editor },
  { label = 'Appearance → Color Scheme', open = function()
    vim.cmd 'QuickSwitchScheme'
  end },
  { label = 'Appearance → HTTP Proxy', open = function()
    require('pc.proxy').open()
  end },
  { label = 'Project Structure (SDK)', open = function()
    require('pc.project_structure').open()
  end },
  { label = 'Build Tools → Maven', open = function()
    require('pc.maven').settings()
  end },
  { label = 'Invalidate Caches…', open = function()
    require('pc.invalidate_caches').open()
  end },
  { label = 'Run/Debug Configurations', open = function()
    require('pc.run_configs').edit()
  end },
}

function M.open()
  vim.ui.select(PAGES, {
    prompt = 'Settings',
    format_item = function(page)
      return page.label
    end,
  }, function(page)
    if page then
      page.open()
    end
  end)
end

vim.api.nvim_create_user_command('Settings', M.open, { desc = 'Settings' })
vim.keymap.set('n', '<M-C-s>', M.open, { desc = 'Settings' })
vim.keymap.set('n', '<leader>,', M.open, { desc = 'Settings' })

M.apply()

return M
