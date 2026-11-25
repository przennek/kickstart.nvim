-- Neovim across two monitors (the user, 2026-11-25): Alacritty spans both screens and :vs / :sp
-- work as usual, but a vertical split line that crosses the middle of the window always sits on
-- the seam between the monitors, so no window is cut by the bezel. Two equal monitors: the seam
-- is the middle column of the window.
--   on      by itself when the window is at least g.pc_span_min_columns wide (a window over both
--           4K screens), or :SpanSeam on / off / toggle
--   kept    after :vs / :sp (also inside one half), closing windows, resizing the terminal,
--           opening the project tree: every row of side-by-side windows that crosses the middle
--           gets a split line exactly there; the windows of each half keep their proportions
--   offset  g.pc_span_seam_offset moves the seam by whole columns (window padding, a bezel)

local M = {}

vim.g.pc_span_min_columns = vim.g.pc_span_min_columns or 480
vim.g.pc_span_seam_offset = vim.g.pc_span_seam_offset or 0

local forced = nil -- true / false from :SpanSeam, nil = by the width

function M.enabled()
  if forced ~= nil then
    return forced
  end
  return vim.o.columns >= vim.g.pc_span_min_columns
end

--- The column (0-based) of the split line: half of the editor, the left half gets the rest
function M.seam()
  return math.floor(vim.o.columns / 2) + vim.g.pc_span_seam_offset
end

local function normal(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ''
end

-- left column (0-based) and width of a layout node
local function extent(node)
  if node[1] == 'leaf' then
    local pos = vim.fn.win_screenpos(node[2])
    return pos[2] - 1, vim.api.nvim_win_get_width(node[2])
  end
  local first = select(1, extent(node[2][1]))
  local last_col, last_w = extent(node[2][#node[2]])
  return first, last_col + last_w - first
end

-- a window of the node whose width is the node's width (any window of a column / leaf; for a
-- row the widths of its children add up, setting one leaf would only change that child)
local function width_win(node)
  if node[1] == 'leaf' then
    return node[2]
  end
  if node[1] == 'col' then
    return width_win(node[2][1])
  end
end

local function set_width(node, width)
  local win = width_win(node)
  if win then
    pcall(vim.api.nvim_win_set_width, win, math.max(1, width))
    return
  end
  -- a row inside a row does not happen (Neovim merges them); nothing to do
end

-- a panel of fixed width (the project tree, Structure…): all of its windows keep 'winfixwidth'
local function fixed(node)
  if node[1] == 'leaf' then
    return vim.wo[node[2]].winfixwidth
  end
  for _, kid in ipairs(node[2]) do
    if not fixed(kid) then
      return false
    end
  end
  return true
end

local function flexible(kids, from, to)
  for k = from, to do
    if not fixed(kids[k]) then
      return true
    end
  end
  return false
end

-- a child with split lines of its own over the seam: those go on the seam, not this row's
local function split_inside(kids, seam)
  for _, kid in ipairs(kids) do
    if kid[1] ~= 'leaf' then
      local col, w = extent(kid)
      if seam > col and seam < col + w - 1 then
        return true
      end
    end
  end
  return false
end

-- widths for children from..to filling `total` columns (with the separators between them):
-- fixed panels keep theirs, the others share the rest in their proportions; nil when it does
-- not fit
local function share(kids, from, to, total)
  local widths, flex_sum, fixed_sum = {}, 0, 0
  for k = from, to do
    local _, w = extent(kids[k])
    widths[k] = w
    if fixed(kids[k]) then
      fixed_sum = fixed_sum + w
    else
      flex_sum = flex_sum + w
    end
  end
  local room = total - (to - from) - fixed_sum
  if room < 1 then
    return nil
  end
  local last
  for k = from, to do
    if not fixed(kids[k]) then
      last = k
    end
  end
  local given = 0
  for k = from, to do
    if not fixed(kids[k]) then
      local w = k == last and (room - given) or math.max(1, math.floor(widths[k] * room / math.max(flex_sum, 1) + 0.5))
      widths[k] = w
      given = given + w
    end
  end
  return widths[last] >= 1 and widths or nil
end

-- puts a split line of this row on the seam when the row crosses it; then the same inside
local function place(node, seam)
  if node[1] == 'leaf' then
    return
  end
  local kids = node[2]
  if node[1] == 'row' and #kids > 1 then
    local left, width = extent(node)
    if seam > left and seam < left + width - 1 and not split_inside(kids, seam) then
      local best = nil
      local best_dist = math.huge
      -- the boundary nearest to the seam (after child k: the separator column is at its end)
      -- that has a window of flexible width on both sides
      for k = 1, #kids - 1 do
        local col, w = extent(kids[k])
        local dist = math.abs(col + w - seam)
        if dist < best_dist and flexible(kids, 1, k) and flexible(kids, k + 1, #kids) then
          best, best_dist = k, dist
        end
      end
      if best and best_dist > 0 then
        local lw = share(kids, 1, best, seam - left)
        local rw = share(kids, best + 1, #kids, left + width - seam - 1)
        if lw and rw then
          for k = 1, #kids - 1 do
            set_width(kids[k], k <= best and lw[k] or rw[k])
          end
        end
      end
    end
  end
  for _, kid in ipairs(kids) do
    place(kid, seam)
  end
end

local busy = false

--- Every row of the current tab that crosses the middle gets its split line on the seam
function M.apply()
  -- a split maximized with Ctrl+Shift+M (pc.splits) stays maximized until restored
  if busy or not M.enabled() or vim.t.pc_maximize_restore then
    return
  end
  busy = true
  local ok, err = pcall(function()
    -- twice: a width set in an outer row moves the inner ones
    for _ = 1, 2 do
      place(vim.fn.winlayout(), M.seam())
    end
  end)
  busy = false
  if not ok then
    vim.notify('SpanSeam: ' .. tostring(err), vim.log.levels.WARN)
  end
end

local pending = false
local function schedule()
  if pending then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    M.apply()
  end)
end

vim.api.nvim_create_autocmd({ 'VimResized', 'WinNew', 'WinClosed', 'TabEnter', 'WinResized' }, {
  group = vim.api.nvim_create_augroup('pc-span', { clear = true }),
  callback = function(event)
    if event.event == 'WinResized' and busy then
      return
    end
    if event.event == 'WinNew' and not normal(vim.api.nvim_get_current_win()) then
      return
    end
    schedule()
  end,
})

vim.api.nvim_create_user_command('SpanSeam', function(cmd)
  local arg = cmd.args
  if arg == 'on' then
    forced = true
  elseif arg == 'off' then
    forced = false
  elseif arg == 'auto' then
    forced = nil
  else
    forced = not M.enabled()
  end
  vim.notify(('Split line on the monitor seam: %s (column %d of %d)'):format(M.enabled() and 'on' or 'off', M.seam(), vim.o.columns))
  M.apply()
end, { nargs = '?', complete = function()
  return { 'on', 'off', 'auto', 'toggle' }
end, desc = 'Keep the vertical split line on the seam of two monitors' })

return M
