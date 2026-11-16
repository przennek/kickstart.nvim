-- Names for the keys a terminal sends in odd ways. Pure data and small helpers, no side effects.
--
-- Why a modified F-key has two spellings
-- ---------------------------------------
-- Shift+F2 reaches Neovim as <S-F2> when Neovim runs directly in the terminal, but inside tmux
-- tmux re-encodes it as a plain, higher-numbered F-key: <F14>. A mapping must exist under both
-- names or the shortcut works only in one of the two places. Write the readable name once
-- ('S-F2') and let this module produce both spellings.
--
-- tmux numbers the modified F-keys in blocks of 12 after F1..F12:
--
--     modifier         F1..F12 become
--     Shift       S    F13..F24    (Shift+F2     = F2  + 12 = F14)
--     Ctrl        C    F25..F36    (Ctrl+F11     = F11 + 24 = F35)
--     Ctrl+Shift  C-S  F37..F48    (Ctrl+Shift+F10 = F10 + 36 = F46)
--     Alt         M    F49..F60    (Alt+F2       = F2  + 48 = F50)
--     Alt+Shift   M-S  F61..F72    (Alt+Shift+F2 = F2  + 60 = F62)
--
-- Any other combination (Ctrl+Alt+F1 …) has no number: it keeps its single spelling.
--
-- A second, unrelated use of high F-numbers: a terminal cannot send Ctrl+Tab, Ctrl+Enter,
-- Ctrl+Shift+<letter> or Ctrl+Alt+M at all, so Alacritty is configured to send Ctrl+Shift+F1…F7
-- for them instead. These arrive as F37…F43 in and out of tmux, which is the same number as
-- tmux's Ctrl+Shift+F1…F7 (the overlap is harmless: this config uses those F-keys for nothing
-- else). They are named below (keys.CTRL_TAB …) and are used as they are, with one spelling.

local M = {}

-- Modifier prefix (as in <S-F2>), what it is called when shown, and where its block starts.
-- The order is the numbering: the block of entry i starts at F(12 * i + 1).
local MODIFIERS = {
  { id = 'S', label = 'Shift+' },
  { id = 'C', label = 'Ctrl+' },
  { id = 'C-S', label = 'Ctrl+Shift+' },
  { id = 'M', label = 'Alt+' },
  { id = 'M-S', label = 'Alt+Shift+' },
}
local OFFSET, LABEL_OF_BLOCK = {}, {}
for i, m in ipairs(MODIFIERS) do
  OFFSET[m.id] = 12 * i
  LABEL_OF_BLOCK[i] = m.label
end

-- Keys Alacritty sends in place of those a terminal cannot send: constant, key, shown as
local ALACRITTY = {
  { 'CTRL_TAB', '<F37>', 'Ctrl+Tab' },
  { 'CTRL_SHIFT_TAB', '<F38>', 'Ctrl+Shift+Tab' },
  { 'CTRL_SHIFT_F', '<F39>', 'Ctrl+Shift+F' },
  { 'CTRL_ENTER', '<F40>', 'Ctrl+Enter' },
  { 'CTRL_SHIFT_R', '<F41>', 'Ctrl+Shift+R' },
  { 'CTRL_SHIFT_B', '<F42>', 'Ctrl+Shift+B' },
  { 'CTRL_ALT_M', '<F43>', 'Ctrl+Alt+M' },
}
--- key -> how it is shown to the user, for the Alacritty-translated keys: { ['<F37>'] = 'Ctrl+Tab', … }
M.alacritty_labels = {}
for _, a in ipairs(ALACRITTY) do
  M[a[1]] = a[2]
  M.alacritty_labels[a[2]] = a[3]
end

--- Both spellings of a modified F-key, from its readable name.
--- keys.f 'S-F2'     -> { '<S-F2>', '<F14>' }
--- keys.f 'M-S-F12'  -> { '<M-S-F12>', '<F72>' }
--- keys.f 'F2'       -> { '<F2>' }       (unmodified: one spelling)
--- keys.f 'C-M-F1'   -> { '<C-M-F1>' }   (tmux has no number for it: one spelling)
--- Anything that is not such a bare name (already '<…>', 'gd', '<leader>x') comes back unchanged.
---@param name string
---@return string[]
function M.f(name)
  local prefix, n = name:match '^([%a%-]*)F(%d+)$'
  if not prefix or (prefix ~= '' and prefix:sub(-1) ~= '-') then
    return { name }
  end
  n = tonumber(n)
  local spelling = '<' .. name .. '>'
  local offset = OFFSET[prefix:sub(1, -2)]
  if offset and n >= 1 and n <= 12 then
    return { spelling, '<F' .. (n + offset) .. '>' }
  end
  return { spelling }
end

--- A list of names and ready keys as one flat list of keys (names expand to both spellings).
--- keys.flat { '<M-n>', 'M-F12', keys.CTRL_TAB } -> { '<M-n>', '<M-F12>', '<F60>', '<F37>' }
---@param list string[]
---@return string[]
function M.flat(list)
  local out = {}
  for _, name in ipairs(list) do
    vim.list_extend(out, M.f(name))
  end
  return out
end

--- vim.keymap.set under both spellings of the key: keys.map('n', 'S-F2', rhs, opts).
--- Calls vim.keymap.set when called, so wrappers of it (pc.actions) see every mapping.
function M.map(modes, name, rhs, opts)
  for _, lhs in ipairs(M.f(name)) do
    vim.keymap.set(modes, lhs, rhs, opts)
  end
end

--- The same value under both spellings, for plugin options that map keys with a table:
--- keys.keyed('C-S-F10', fn) -> { ['<C-S-F10>'] = fn, ['<F46>'] = fn }
--- (merge it into the table with vim.tbl_extend).
---@param name string
---@param value any
---@return table<string, any>
function M.keyed(name, value)
  local out = {}
  for _, lhs in ipairs(M.f(name)) do
    out[lhs] = value
  end
  return out
end

--- A lazy.nvim `keys = {}` list in which a spec may name its key as 'S-F11' instead of
--- '<S-F11>': that spec becomes two, one per spelling, with the same function, desc, mode…
--- Specs with an ordinary key ('<leader>x', '<F11>') are kept as they are.
---   keys = keys.lazy {
---     { 'S-F11', show_bookmarks, desc = 'Show Bookmarks' },
---     { '<leader>sb', show_bookmarks, desc = 'Show Bookmarks' },
---   }
---@param specs table[]
---@return table[]
function M.lazy(specs)
  local out = {}
  for _, spec in ipairs(specs) do
    local name = type(spec) == 'table' and spec[1] or spec
    for _, lhs in ipairs(type(name) == 'string' and M.f(name) or { name }) do
      local copy = spec
      if type(spec) == 'table' then
        copy = vim.tbl_extend('force', {}, spec)
        copy[1] = lhs
      elseif lhs ~= spec then
        copy = lhs
      end
      table.insert(out, copy)
    end
  end
  return out
end

--- How a tmux-numbered key is shown: keys.label '<F14>' -> 'Shift+F2'; nil for any other key.
--- (Alacritty's F37…F43 are in keys.alacritty_labels; they win over this where the two overlap.)
---@param lhs string
---@return string?
function M.label(lhs)
  local n = tonumber(lhs:match '^<F(%d+)>$')
  local prefix = n and n > 12 and LABEL_OF_BLOCK[math.floor((n - 1) / 12)]
  return prefix and (prefix .. 'F' .. ((n - 1) % 12 + 1)) or nil
end

return M
