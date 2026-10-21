-- File mask like IDEA's Find in Path / Search Everywhere filter: "*.java, *.xml", "!*Test.java"
-- excludes. Alt+M in Find in Path and Search Everywhere asks for it (empty = all files); it is
-- remembered for the session and shown in the window title.

local M = {}

local mask = ''

--- The patterns of the mask: { { glob = '*.java', exclude = false }, … }
local function patterns()
  local list = {}
  for part in mask:gmatch '[^,%s]+' do
    local exclude = part:sub(1, 1) == '!'
    table.insert(list, { glob = exclude and part:sub(2) or part, exclude = exclude })
  end
  return list
end

function M.get()
  return mask
end

function M.set(text)
  mask = vim.trim(text or '')
end

--- " · *.java" for a title, '' without a mask
function M.label()
  return mask ~= '' and (' · ' .. mask) or ''
end

--- ripgrep arguments: --glob per pattern
function M.rg_args()
  local args = {}
  for _, p in ipairs(patterns()) do
    vim.list_extend(args, { '--glob', (p.exclude and '!' or '') .. p.glob })
  end
  return args
end

--- Does a project-relative path pass the mask? (a pattern without / matches the file name,
--- like ripgrep's globs)
function M.matches(rel)
  local list = patterns()
  if #list == 0 then
    return true
  end
  local included, any_include = false, false
  for _, p in ipairs(list) do
    local subject = p.glob:find('/', 1, true) and rel or vim.fs.basename(rel)
    local ok, lpeg = pcall(vim.glob.to_lpeg, p.glob)
    local hit = ok and lpeg:match(subject) ~= nil
    if p.exclude and hit then
      return false
    end
    if not p.exclude then
      any_include = true
      included = included or hit
    end
  end
  return included or not any_include
end

--- Asks for the mask, then calls `done` (also when it stays the same)
function M.ask(done)
  -- after the picker that asks has closed (it leaves Insert mode on its way out)
  vim.schedule(function()
    M._ask(done)
  end)
end

function M._ask(done)
  require('pc.input').open({ prompt = 'File mask (*.java, !*Test.java; empty = all)', default = mask, history = 'file mask' }, function(text)
    if text ~= nil then
      M.set(text)
    end
    done()
  end)
end

return M
