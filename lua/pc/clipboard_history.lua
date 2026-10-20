-- Paste from History (Alt+Shift+V, Cmd+Shift+V) like IDEA's: everything copied or cut in this
-- session, newest first, with the whole text in the preview; Enter pastes it at the cursor and
-- makes it the current clipboard (p pastes it again).

local M = {}

local MAX = 30
local entries = {} -- newest first: { lines, regtype }

local function key(e)
  return e.regtype .. '\0' .. table.concat(e.lines, '\n')
end

vim.api.nvim_create_autocmd('TextYankPost', {
  group = vim.api.nvim_create_augroup('pc-clipboard-history', { clear = true }),
  callback = function()
    local ev = vim.v.event
    if not (ev.operator == 'y' or ev.operator == 'd' or ev.operator == 'c') or #ev.regcontents == 0 then
      return
    end
    local entry = { lines = vim.deepcopy(ev.regcontents), regtype = ev.regtype }
    if vim.trim(table.concat(entry.lines, '')) == '' then
      return -- deleted empty lines are not worth keeping
    end
    for i = #entries, 1, -1 do
      if key(entries[i]) == key(entry) then
        table.remove(entries, i)
      end
    end
    table.insert(entries, 1, entry)
    if #entries > MAX then
      table.remove(entries)
    end
  end,
})

--- Copied / cut texts, newest first
function M.entries()
  return entries
end

function M.pick()
  if #entries == 0 then
    return vim.notify 'Paste from History: nothing copied yet'
  end
  local insert = vim.fn.mode() == 'i'
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local previewers = require 'telescope.previewers'
  local actions = require 'telescope.actions'
  local state = require 'telescope.actions.state'
  pickers
    .new({}, {
      prompt_title = 'Paste from History',
      finder = finders.new_table {
        results = entries,
        entry_maker = function(e)
          local first = vim.trim(e.lines[1] or '')
          local more = #e.lines > 1 and ('  (%d lines)'):format(#e.lines) or ''
          return { value = e, display = first .. more, ordinal = table.concat(e.lines, ' ') }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = 'Text',
        define_preview = function(self, entry)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, entry.value.lines)
          vim.bo[self.state.bufnr].filetype = vim.bo[buf].filetype
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not entry then
            return
          end
          local e = entry.value
          vim.schedule(function()
            if not vim.api.nvim_win_is_valid(win) then
              return
            end
            vim.api.nvim_set_current_win(win)
            -- at the cursor, like IDEA; whole lines go below the current line
            vim.api.nvim_put(e.lines, e.regtype:sub(1, 1), not insert or e.regtype == 'V', true)
            vim.fn.setreg('"', e.lines, e.regtype)
            if insert then
              vim.cmd 'startinsert'
            end
          end)
        end)
        return true
      end,
    })
    :find()
end

return M
