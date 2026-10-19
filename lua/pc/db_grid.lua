-- Query results as a grid, like IDEA's result table (the text dadbod prints for PostgreSQL,
-- SQLite and MySQL is parsed into columns):
--   current cell and its column are highlighted, column headers stay on top (winbar) and
--   follow horizontal scrolling, the row count is shown next to them
--   Tab / Shift+Tab   next / previous cell
--   Enter, gh         full value of the cell in a popup (JSON pretty-printed)
--   R                 record view: every column of the current row
--   yc / yr / yC      copy cell / row (tab-separated) / whole column
--   s / S             sort by the current column (again: descending) / original order
--   E                 export: CSV / TSV / JSON / SQL INSERT / Markdown, to the clipboard or a file
--   i                 edit the cell: runs UPDATE … WHERE <primary key> after confirming
--                     (NULL = null; a table without a primary key matches on the whole row)
--   dd                delete the row (DELETE, after confirming)
-- dadbod-ui's own keys keep working (yic, yh, Ctrl+] foreign key, <leader>R layout).

local M = {}

local ns = vim.api.nvim_create_namespace 'pc-db-grid'
vim.api.nvim_set_hl(0, 'PcDbCell', { link = 'Visual', default = true })
vim.api.nvim_set_hl(0, 'PcDbHeader', { link = 'Title', default = true })
vim.api.nvim_set_hl(0, 'PcDbHeaderCurrent', { link = 'IncSearch', default = true })

---@class pc.Grid
---@field cols {from: integer, to: integer, name: string}[]  virtual columns, 1-based, inclusive
---@field header integer  line of the column names
---@field first integer   first data line
---@field last integer    last data line
---@field original string[]  data lines before sorting
---@field sort? {col: integer, desc: boolean}

---@type table<integer, pc.Grid>
local grids = {}

---------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------

-- Runs of '-' in the line under the header are the columns: psql "---+---",
-- sqlite "---  ---", mysql "+---+---+"
local function column_ranges(sep)
  local cols, vcol, start = {}, 0, nil
  for _, ch in ipairs(vim.fn.split(sep, '\\zs')) do
    vcol = vcol + 1
    if ch == '-' then
      start = start or vcol
    elseif start then
      table.insert(cols, { from = start, to = vcol - 1 })
      start = nil
    end
  end
  if start then
    table.insert(cols, { from = start, to = vcol })
  end
  return cols
end

local function parse(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, math.min(vim.api.nvim_buf_line_count(buf), 10), false)
  for i = 2, #lines do
    local sep = lines[i]
    if sep:match '^[%s%-%+|]+$' and sep:find '%-%-' and vim.trim(lines[i - 1]) ~= '' then
      local cols = column_ranges(sep)
      if #cols > 0 then
        local header_line = lines[i - 1]
        for _, c in ipairs(cols) do
          c.name = vim.trim(vim.fn.strcharpart(header_line, c.from - 1, c.to - c.from + 1))
        end
        local all = vim.api.nvim_buf_get_lines(buf, i, -1, false)
        local last = i
        for j, line in ipairs(all) do
          if line == '' or line:match '^%(%d+ rows?%)' or line:match '^%+[-+]+%+$' then
            break
          end
          last = i + j
        end
        return {
          cols = cols,
          header = i - 1,
          first = i + 1,
          last = last,
          original = vim.api.nvim_buf_get_lines(buf, i, last, false),
        }
      end
    end
  end
end

---------------------------------------------------------------------------
-- Cells
---------------------------------------------------------------------------

local function cell_text(line, col)
  return vim.trim(vim.fn.strcharpart(line, col.from - 1, col.to - col.from + 1))
end

local function current(buf)
  local g = grids[buf]
  if not g then
    return
  end
  local lnum = vim.fn.line '.'
  local vcol = vim.fn.virtcol '.'
  local index = 1
  for i, c in ipairs(g.cols) do
    if vcol >= c.from then
      index = i
    end
  end
  return g, lnum, index
end

local function row_values(buf, g, lnum)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
  return vim.tbl_map(function(c)
    return cell_text(line, c)
  end, g.cols)
end

local function goto_cell(g, lnum, index)
  local col = g.cols[index]
  local line = vim.fn.getline(lnum)
  local text_start = col.from
  -- land on the first character of the value (values may be right-aligned)
  for v = col.from, col.to do
    local ch = vim.fn.strcharpart(line, v - 1, 1)
    if ch ~= ' ' and ch ~= '' then
      text_start = v
      break
    end
  end
  vim.fn.cursor(lnum, 1)
  vim.cmd(('normal! %d|'):format(text_start))
end

---------------------------------------------------------------------------
-- Header (winbar) and highlights
---------------------------------------------------------------------------

local function refresh_in_window(buf)
  local g, lnum, index = current(buf)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not g then
    return
  end
  local in_data = lnum >= g.first and lnum <= g.last
  if in_data then
    local c = g.cols[index]
    local from = vim.fn.virtcol2col(win, lnum, c.from)
    local to = vim.fn.virtcol2col(win, lnum, c.to)
    if from > 0 and to > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, from - 1, { end_col = to, hl_group = 'PcDbCell' })
    end
  end
  -- sticky header that follows horizontal scrolling, current column highlighted
  local leftcol = vim.fn.winsaveview().leftcol
  local width = vim.api.nvim_win_get_width(win)
  local parts, vcol = {}, leftcol
  for i, c in ipairs(g.cols) do
    if c.to > leftcol then
      local from = math.max(c.from, leftcol + 1)
      if from > vcol + 1 then
        table.insert(parts, string.rep(' ', from - vcol - 1))
      end
      local name = vim.fn.strcharpart(string.format('%-' .. (c.to - c.from + 1) .. 's', ' ' .. c.name), from - c.from, c.to - from + 1)
      local hl = (in_data and i == index) and 'PcDbHeaderCurrent' or 'PcDbHeader'
      table.insert(parts, '%#' .. hl .. '#' .. name:gsub('%%', '%%%%') .. '%*')
      vcol = c.to
      if vcol - leftcol > width then
        break
      end
    end
  end
  local count = g.last - g.first + 1
  local sorted = g.sort and ('  sorted by ' .. g.cols[g.sort.col].name .. (g.sort.desc and ' ↓' or ' ↑')) or ''
  vim.wo[win].winbar = table.concat(parts) .. '%=%#Comment#' .. count .. (count == 1 and ' row' or ' rows') .. sorted .. ' %*'
end

-- the result buffer usually sits in a preview window while the cursor is in the query
local function refresh(buf)
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_call(win, function()
      refresh_in_window(buf)
    end)
  end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function step(buf, dir)
  local g, lnum, index = current(buf)
  if not g then
    return
  end
  if lnum < g.first then
    return goto_cell(g, g.first, 1)
  end
  index = index + dir
  if index > #g.cols then
    index, lnum = 1, math.min(lnum + 1, g.last)
  elseif index < 1 then
    index, lnum = #g.cols, math.max(lnum - 1, g.first)
  end
  goto_cell(g, lnum, index)
end

-- JSON pretty-printer that keeps the key order (no jq needed)
local function pretty_json(text)
  local out, indent, in_string, escaped = {}, 0, false, false
  local function newline()
    table.insert(out, '\n' .. string.rep('  ', indent))
  end
  for ch in text:gmatch '.' do
    if in_string then
      table.insert(out, ch)
      if escaped then
        escaped = false
      elseif ch == '\\' then
        escaped = true
      elseif ch == '"' then
        in_string = false
      end
    elseif ch == '"' then
      in_string = true
      table.insert(out, ch)
    elseif ch == '{' or ch == '[' then
      indent = indent + 1
      table.insert(out, ch)
      newline()
    elseif ch == '}' or ch == ']' then
      indent = indent - 1
      newline()
      table.insert(out, ch)
    elseif ch == ',' then
      table.insert(out, ch)
      newline()
    elseif ch == ':' then
      table.insert(out, ': ')
    elseif not ch:match '%s' then
      table.insert(out, ch)
    end
  end
  return table.concat(out)
end

local function show_value(buf)
  local g, lnum, index = current(buf)
  if not g or lnum < g.first or lnum > g.last then
    return
  end
  local value = row_values(buf, g, lnum)[index]
  local ft = 'text'
  if value:match '^[%[{]' and pcall(vim.json.decode, value) then
    value, ft = pretty_json(value), 'json'
  end
  local lines = vim.split(value == '' and '(empty)' or value, '\n')
  vim.lsp.util.open_floating_preview(lines, ft, { border = 'rounded', title = ' ' .. g.cols[index].name .. ' ', focus_id = 'pc-db-value' })
end

local function record_view(buf)
  local g, lnum = current(buf)
  if not g or lnum < g.first or lnum > g.last then
    return
  end
  local values = row_values(buf, g, lnum)
  local width = 0
  for _, c in ipairs(g.cols) do
    width = math.max(width, vim.fn.strdisplaywidth(c.name))
  end
  local lines = {}
  for i, c in ipairs(g.cols) do
    table.insert(lines, string.format('%-' .. width .. 's  %s', c.name, values[i]))
  end
  vim.lsp.util.open_floating_preview(lines, 'text', { border = 'rounded', title = (' row %d '):format(lnum - g.first + 1), focus_id = 'pc-db-record' })
end

local function copy(text, what)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify(('Copied %s'):format(what))
end

local function copy_cell(buf)
  local g, lnum, index = current(buf)
  if g and lnum >= g.first and lnum <= g.last then
    copy(row_values(buf, g, lnum)[index], 'cell')
  end
end

local function copy_row(buf)
  local g, lnum = current(buf)
  if g and lnum >= g.first and lnum <= g.last then
    copy(table.concat(row_values(buf, g, lnum), '\t'), 'row')
  end
end

local function copy_column(buf)
  local g, _, index = current(buf)
  if not g then
    return
  end
  local values = {}
  for lnum = g.first, g.last do
    table.insert(values, row_values(buf, g, lnum)[index])
  end
  copy(table.concat(values, '\n'), ('column %s (%d values)'):format(g.cols[index].name, #values))
end

local function set_rows(buf, g, rows)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, g.first - 1, g.last, false, rows)
  vim.bo[buf].modified = false
end

local function sort(buf, reset)
  local g, lnum, index = current(buf)
  if not g then
    return
  end
  if reset then
    g.sort = nil
    set_rows(buf, g, g.original)
    return refresh(buf)
  end
  local desc = g.sort and g.sort.col == index and not g.sort.desc
  g.sort = { col = index, desc = desc }
  local rows = vim.api.nvim_buf_get_lines(buf, g.first - 1, g.last, false)
  local col = g.cols[index]
  local numeric = true
  for _, r in ipairs(rows) do
    local v = cell_text(r, col)
    if v ~= '' and not tonumber(v) then
      numeric = false
      break
    end
  end
  table.sort(rows, function(a, b)
    local x, y = cell_text(a, col), cell_text(b, col)
    if numeric then
      x, y = tonumber(x) or -math.huge, tonumber(y) or -math.huge
    else
      x, y = x:lower(), y:lower()
    end
    if desc then
      return x > y
    end
    return x < y
  end)
  set_rows(buf, g, rows)
  goto_cell(g, math.max(lnum, g.first), index)
  refresh(buf)
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

local function all_rows(buf, g)
  local rows = {}
  for lnum = g.first, g.last do
    table.insert(rows, row_values(buf, g, lnum))
  end
  return rows
end

-- a column is numeric when every non-empty value is a number
local function numeric_columns(g, rows)
  local numeric = {}
  for i in ipairs(g.cols) do
    numeric[i] = true
    for _, r in ipairs(rows) do
      if r[i] ~= '' and not tonumber(r[i]) then
        numeric[i] = false
        break
      end
    end
  end
  return numeric
end

-- The query that produced the result and the connection it ran on (dadbod's b:db)
local function source(buf)
  local q = vim.b[buf].db
  if type(q) ~= 'table' or not q.db_url then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, q.input or '')
  return { url = q.db_url, query = ok and table.concat(lines, '\n') or '' }
end

-- "select … from orders where …" → orders; nil for joins and anything ambiguous
local function source_table(query)
  local q = query:lower():gsub('%-%-[^\n]*', ''):gsub('%s+', ' ')
  if q:find ' join ' or select(2, q:gsub(' from ', '')) ~= 1 then
    return nil
  end
  return query:match '[Ff][Rr][Oo][Mm]%s+([%w_."`]+)'
end

local function quote_sql(v)
  return "'" .. v:gsub("'", "''") .. "'"
end

local function csv_field(v, sep)
  if v:find('[' .. sep .. '"\n]') then
    return '"' .. v:gsub('"', '""') .. '"'
  end
  return v
end

local EXPORTS = {
  {
    name = 'CSV',
    ext = 'csv',
    render = function(g, rows)
      local out = { table.concat(
        vim.tbl_map(function(c)
          return csv_field(c.name, ',')
        end, g.cols),
        ','
      ) }
      for _, r in ipairs(rows) do
        table.insert(
          out,
          table.concat(
            vim.tbl_map(function(v)
              return csv_field(v, ',')
            end, r),
            ','
          )
        )
      end
      return out
    end,
  },
  {
    name = 'TSV',
    ext = 'tsv',
    render = function(g, rows)
      local out = { table.concat(
        vim.tbl_map(function(c)
          return c.name
        end, g.cols),
        '\t'
      ) }
      for _, r in ipairs(rows) do
        table.insert(out, table.concat(r, '\t'))
      end
      return out
    end,
  },
  {
    name = 'JSON',
    ext = 'json',
    render = function(g, rows)
      local numeric = numeric_columns(g, rows)
      local out = { '[' }
      for n, r in ipairs(rows) do
        local fields = {}
        for i, c in ipairs(g.cols) do
          local v = r[i]
          local json
          if numeric[i] then
            json = v == '' and 'null' or v
          elseif (v:match '^[%[{]' and pcall(vim.json.decode, v)) or v == 'true' or v == 'false' then
            json = v
          else
            json = vim.json.encode(v)
          end
          table.insert(fields, vim.json.encode(c.name) .. ': ' .. json)
        end
        table.insert(out, '  {' .. table.concat(fields, ', ') .. '}' .. (n < #rows and ',' or ''))
      end
      table.insert(out, ']')
      return out
    end,
  },
  {
    name = 'SQL INSERT',
    ext = 'sql',
    render = function(g, rows, tbl)
      local numeric = numeric_columns(g, rows)
      local names = table.concat(
        vim.tbl_map(function(c)
          return c.name
        end, g.cols),
        ', '
      )
      local out = {}
      for _, r in ipairs(rows) do
        local values = {}
        for i, v in ipairs(r) do
          values[i] = (numeric[i] and (v == '' and 'NULL' or v)) or quote_sql(v)
        end
        table.insert(out, ('INSERT INTO %s (%s) VALUES (%s);'):format(tbl, names, table.concat(values, ', ')))
      end
      return out
    end,
  },
  {
    name = 'Markdown',
    ext = 'md',
    render = function(g, rows)
      local function line(values)
        return '| '
          .. table.concat(
            vim.tbl_map(function(v)
              return (v:gsub('|', '\\|'))
            end, values),
            ' | '
          )
          .. ' |'
      end
      local out = {
        line(vim.tbl_map(function(c)
          return c.name
        end, g.cols)),
        '|' .. string.rep(' --- |', #g.cols),
      }
      for _, r in ipairs(rows) do
        table.insert(out, line(r))
      end
      return out
    end,
  },
}

local function export(buf)
  local g = grids[buf]
  if not g then
    return
  end
  local rows = all_rows(buf, g)
  local src = source(buf)
  local tbl = src and source_table(src.query) or 'result'
  vim.ui.select(EXPORTS, {
    prompt = ('Export %d rows'):format(#rows),
    format_item = function(e)
      return e.name
    end,
  }, function(e)
    if not e then
      return
    end
    local text = table.concat(e.render(g, rows, tbl), '\n') .. '\n'
    vim.ui.select({ 'Clipboard', 'File…' }, { prompt = 'Export ' .. e.name .. ' to' }, function(where)
      if where == 'Clipboard' then
        copy(text, ('%d rows as %s'):format(#rows, e.name))
      elseif where then
        vim.ui.input({ prompt = 'File: ', default = vim.fn.getcwd() .. '/' .. tbl:gsub('.*%.', '') .. '.' .. e.ext, completion = 'file' }, function(path)
          if path and path ~= '' then
            path = vim.fn.expand(path)
            vim.fn.writefile(vim.split(text, '\n', { plain = true }), path, 'b')
            vim.notify(('Exported %d rows to %s'):format(#rows, vim.fn.fnamemodify(path, ':~:.')))
          end
        end)
      end
    end)
  end)
end

---------------------------------------------------------------------------
-- Editing: UPDATE / DELETE on the table the query read from
---------------------------------------------------------------------------

-- Redraws the grid (psql style) from values, so edited cells of any width fit
local function render(buf, g, rows)
  local widths = {}
  for i, c in ipairs(g.cols) do
    widths[i] = vim.fn.strdisplaywidth(c.name)
    for _, r in ipairs(rows) do
      widths[i] = math.max(widths[i], vim.fn.strdisplaywidth(r[i]))
    end
  end
  local numeric = numeric_columns(g, rows)
  local function line(values, header)
    local cells = {}
    for i, v in ipairs(values) do
      local pad = string.rep(' ', widths[i] - vim.fn.strdisplaywidth(v))
      cells[i] = (numeric[i] and not header) and (pad .. v) or (v .. pad)
    end
    return ' ' .. table.concat(cells, ' | ')
  end
  local lines = {
    line(
      vim.tbl_map(function(c)
        return c.name
      end, g.cols),
      true
    ),
  }
  table.insert(
    lines,
    table.concat(
      vim.tbl_map(function(w)
        return string.rep('-', w + 2)
      end, widths),
      '+'
    )
  )
  for _, r in ipairs(rows) do
    table.insert(lines, line(r))
  end
  local last = g.last
  local after = vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1]
  if after and after:match '^%(%d+ rows?%)' then
    last = last + 1
  end
  table.insert(lines, ('(%d %s)'):format(#rows, #rows == 1 and 'row' or 'rows'))
  local readonly = vim.bo[buf].readonly
  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, g.header - 1, last, false, lines)
  vim.bo[buf].modified = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = readonly
end

-- WHERE that identifies a row: its primary key, or all its values when there is none
local function where_clause(g, values, pk)
  local conds = {}
  local keys = #pk > 0 and pk or vim.tbl_map(function(c)
    return c.name
  end, g.cols)
  for _, key in ipairs(keys) do
    local index
    for i, c in ipairs(g.cols) do
      if c.name == key then
        index = i
      end
    end
    if not index then
      return nil, 'the result has no column ' .. key .. ' (primary key)'
    end
    local v = values[index]
    -- psql prints NULL and '' alike
    table.insert(conds, v == '' and ("(%s is null or %s = '')"):format(key, key) or ('%s = %s'):format(key, quote_sql(v)))
  end
  return table.concat(conds, ' and ')
end

-- Runs a statement on the row under the cursor, after checking that its WHERE matches
-- exactly one row and confirming; then on_done(g, lnum, index, value) updates the grid
local function modify_row(buf, build, on_done)
  local g, lnum, index = current(buf)
  if not g or lnum < g.first or lnum > g.last then
    return
  end
  local src = source(buf)
  local tbl = src and source_table(src.query)
  if not tbl then
    return vim.notify('Editing works on results of a query from one table (no joins)', vim.log.levels.WARN)
  end
  local db_table = require 'pc.db_table'
  local pk, err = db_table.primary_key(src.url, tbl)
  if not pk then
    return vim.notify(tbl .. ': ' .. err, vim.log.levels.ERROR)
  end
  local values = row_values(buf, g, lnum)
  local where
  where, err = where_clause(g, values, pk)
  if not where then
    return vim.notify(err, vim.log.levels.WARN)
  end
  build(tbl, where, g, index, values, function(statement, value)
    local count
    count, err = db_table.scalar(src.url, ('select count(*) from %s where %s'):format(tbl, where))
    if not count then
      return vim.notify(err, vim.log.levels.ERROR)
    elseif count ~= '1' then
      return vim.notify(('Not changed: the row matches %s rows in %s'):format(count, tbl), vim.log.levels.WARN)
    end
    local prompt = statement .. (#pk == 0 and '\n(no primary key: the row is matched on all columns)' or '')
    if vim.fn.confirm(prompt, '&Execute\n&Cancel', 2) ~= 1 then
      return
    end
    local ok
    ok, err = db_table.run(src.url, statement .. ';\n')
    if not ok then
      return vim.notify(err, vim.log.levels.ERROR)
    end
    on_done(g, lnum, index, value)
  end)
end

local function edit_cell(buf)
  modify_row(buf, function(tbl, where, g, index, values, run)
    vim.ui.input({ prompt = g.cols[index].name .. ' = ', default = values[index] }, function(value)
      if value == nil or value == values[index] then
        return
      end
      local literal = value == 'NULL' and 'NULL' or quote_sql(value)
      run(('UPDATE %s SET %s = %s WHERE %s'):format(tbl, g.cols[index].name, literal, where), value == 'NULL' and '' or value)
    end)
  end, function(g, lnum, index, value)
    local rows = all_rows(buf, g)
    rows[lnum - g.first + 1][index] = value
    render(buf, g, rows)
    M.attach(buf)
    goto_cell(grids[buf], lnum, index)
  end)
end

local function delete_row(buf)
  modify_row(buf, function(tbl, where, _, _, _, run)
    run(('DELETE FROM %s WHERE %s'):format(tbl, where))
  end, function(g, lnum, index)
    local rows = all_rows(buf, g)
    table.remove(rows, lnum - g.first + 1)
    render(buf, g, rows)
    M.attach(buf)
    if #rows > 0 then
      goto_cell(grids[buf], math.min(lnum, grids[buf].last), index)
    end
  end)
end

---------------------------------------------------------------------------
-- Setup per result buffer
---------------------------------------------------------------------------

function M.attach(buf)
  local g = parse(buf)
  grids[buf] = g
  if not g then
    return
  end
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
  end
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, function()
      fn(buf)
    end, { buffer = buf, desc = desc, nowait = true })
  end
  map('<Tab>', function(b)
    step(b, 1)
  end, 'Next cell')
  map('<S-Tab>', function(b)
    step(b, -1)
  end, 'Previous cell')
  map('<CR>', show_value, 'Show cell value')
  map('gh', show_value, 'Show cell value')
  map('R', record_view, 'Record view')
  map('yc', copy_cell, 'Copy cell')
  map('yr', copy_row, 'Copy row')
  map('yC', copy_column, 'Copy column')
  map('s', sort, 'Sort by column')
  map('S', function(b)
    sort(b, true)
  end, 'Original order')
  map('E', export, 'Export data')
  map('i', edit_cell, 'Edit cell (UPDATE)')
  map('dd', delete_row, 'Delete row (DELETE)')
  local group = vim.api.nvim_create_augroup('pc-db-grid-' .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'WinScrolled', 'BufWinEnter' }, {
    group = group,
    buffer = buf,
    callback = function()
      refresh(buf)
    end,
  })
  -- start on the first cell
  if win ~= -1 then
    vim.api.nvim_win_call(win, function()
      goto_cell(g, g.first, 1)
    end)
  end
  refresh(buf)
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'dbout',
  group = vim.api.nvim_create_augroup('pc-db-grid', { clear = true }),
  callback = function(event)
    -- dadbod fills the buffer before setting the filetype; wait for dadbod-ui's own setup
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(event.buf) then
        M.attach(event.buf)
      end
    end)
  end,
})

return M
