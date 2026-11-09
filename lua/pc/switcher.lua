-- Switcher (Ctrl+Tab, Space q), like IDEA's: the open files, most recently used first, and the
-- tool windows below them (Terminal, Project, Agent…). It listed files only, empty with one file
-- open: the log had Space q, Esc, then Alt+T / Alt+E typed by hand.

local M = {}

local TOOLS = {
  { 'Terminal', '<M-t>', 'Alt+T' },
  { 'Agent', '<M-i>', 'Alt+I' },
  { 'Project', '<M-1>', 'Alt+1' },
  { 'Commit', '<M-0>', 'Alt+0' },
  { 'Git log', '<M-9>', 'Alt+9' },
  { 'Problems', '<M-6>', 'Alt+6' },
  { 'Structure', '<M-7>', 'Alt+7' },
  { 'Run', '<M-4>', 'Alt+4' },
  { 'Debug', '<M-5>', 'Alt+5' },
  { 'Find', '<M-3>', 'Alt+3' },
  { 'Bookmarks', '<M-2>', 'Alt+2' },
  { 'Database', '<M-D>', 'Alt+Shift+D' },
  { 'Recent Files', '<M-e>', 'Alt+E' },
}

local function files()
  local current = vim.api.nvim_get_current_buf()
  local list = {}
  for _, info in ipairs(vim.fn.getbufinfo { buflisted = 1 }) do
    if info.bufnr ~= current and info.name ~= '' and vim.bo[info.bufnr].buftype == '' then
      table.insert(list, info)
    end
  end
  table.sort(list, function(a, b)
    return a.lastused > b.lastused
  end)
  return list
end

function M.open()
  local pickers, finders, conf = require 'telescope.pickers', require 'telescope.finders', require('telescope.config').values
  local actions, state = require 'telescope.actions', require 'telescope.actions.state'
  local entries = {}
  for _, info in ipairs(files()) do
    local name = vim.fn.fnamemodify(info.name, ':~:.')
    table.insert(entries, { display = name .. (info.changed == 1 and ' ●' or ''), ordinal = name, buf = info.bufnr })
  end
  for _, tool in ipairs(TOOLS) do
    table.insert(entries, { display = ('%-14s %s'):format(tool[1], tool[3]), ordinal = tool[1], key = tool[2] })
  end
  pickers
    .new({}, {
      prompt_title = 'Switcher',
      finder = finders.new_table {
        results = entries,
        entry_maker = function(item)
          return { value = item, display = item.display, ordinal = item.ordinal }
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt)
        actions.select_default:replace(function()
          local item = state.get_selected_entry().value
          actions.close(prompt)
          if item.buf then
            vim.api.nvim_set_current_buf(item.buf)
          else
            vim.schedule(function()
              vim.api.nvim_feedkeys(vim.keycode(item.key), 'm', false)
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
