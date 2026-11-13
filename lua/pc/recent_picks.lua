-- What you picked last in Go to File and Go to Class, per project.
--
-- Both windows open with an empty input field, but the list starts with the files / classes you
-- picked there before, the last one first, so Alt+Shift+N / Alt+N followed by Enter goes back to
-- where you were. When you type, the recent ones win among the matches (see `rank_first`).
--
-- "Project" is Neovim's working directory when the window was opened. Picks are kept in
-- <state>/pc-recent-picks.json (survives restarts): { [project] = { files = {...}, classes = {...} } },
-- at most 30 of each. Files are absolute paths; a class is the LSP item the picker showed
-- (name text, file, line, column, kind), enough to preview and jump without asking the server.
-- Entries whose file has been deleted are not shown.

local M = {}

local FILE = vim.fn.stdpath 'state' .. '/pc-recent-picks.json'
local MAX = 30
local data -- loaded on first use

local function load()
  if not data then
    local ok, decoded = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(FILE), '\n'))
    end)
    data = ok and type(decoded) == 'table' and decoded or {}
  end
  return data
end

local function list(root, kind)
  local project = load()[root]
  return project and type(project[kind]) == 'table' and project[kind] or {}
end

local function exists(path)
  return type(path) == 'string' and vim.uv.fs_stat(path) ~= nil
end

local function class_key(item)
  return item.filename .. ':' .. item.lnum .. ':' .. item.text
end

-- put `value` first in the project's list `kind`; `same` tells which stored entries it replaces
local function remember(root, kind, value, same)
  -- read again first: another Neovim (another project) may have written its picks since
  data = nil
  local project = load()
  project[root] = project[root] or {}
  local kept = vim.tbl_filter(function(v)
    return not same(v)
  end, list(root, kind))
  table.insert(kept, 1, value)
  project[root][kind] = vim.list_slice(kept, 1, MAX)
  -- a failed write only costs the memory across restarts
  pcall(vim.fn.writefile, { vim.json.encode(project) }, FILE)
end

--- Remembers that Go to File opened `path` in the project `root`
function M.file_picked(root, path)
  path = vim.fs.normalize(path)
  remember(root, 'files', path, function(v)
    return v == path
  end)
end

--- Remembers that Go to Class went to `item` (an LSP item: filename, lnum, col, kind, text)
function M.class_picked(root, item)
  local stored = { filename = item.filename, lnum = item.lnum, col = item.col, kind = item.kind, text = item.text }
  remember(root, 'classes', stored, function(v)
    return type(v) == 'table' and v.filename and class_key(v) == class_key(stored)
  end)
end

--- Files picked before in this project that still exist, last one first
function M.files(root)
  return vim.tbl_filter(exists, list(root, 'files'))
end

--- Classes picked before in this project whose file still exists, last one first
function M.classes(root)
  return vim.tbl_filter(function(item)
    return type(item) == 'table' and type(item.text) == 'string' and item.lnum and exists(item.filename)
  end, list(root, 'classes'))
end

M.class_key = class_key

--- Makes `sorter` put the recent picks ahead of the other entries: with nothing typed that is
--- their order (lower score = higher in the list; the finder's own order decides for the rest),
--- when typing, a recent match beats a non-recent one of about the same quality.
--- `rank(entry)` gives the entry's position among the recent ones, or nil.
function M.rank_first(sorter, rank)
  local score = sorter.scoring_function
  sorter.scoring_function = function(self, prompt, line, entry, ...)
    local result = score(self, prompt, line, entry, ...)
    local r = type(entry) == 'table' and rank(entry)
    if not r or type(result) ~= 'number' or result < 0 then
      return result
    end
    -- the 0.5 beats the others; the rank keeps the more recent one ahead of the less recent
    return prompt == '' and r * 1e-6 or result * (0.5 + r * 1e-3)
  end
  return sorter
end

return M
