-- Database tool window + SQL console, like IDEA's Database plugin (vim-dadbod).
--   <leader>S        Database window: lazysql (lua/pc/db_tui.lua) when installed, or dadbod-ui's
--                    tree below (Settings → Editor → Database): connections, schemas, tables
--                    (add a connection with `A` there, e.g. postgres://user@localhost/db)
--   Alt+Enter        in a SQL buffer: execute the statement under the cursor / the selection
--                    (Console.Jdbc.Execute is Cmd+Enter in your macOS keymap)
-- Named consoles, schema, history, cancel: lua/pc/db_console.lua (<leader>Q…).
-- Completion of tables and columns comes from the active connection.
return {
  'kristijanhusak/vim-dadbod-ui',
  dependencies = {
    -- :DB url query works before the Database window was ever opened
    { 'tpope/vim-dadbod', lazy = true, cmd = 'DB' },
    { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true },
  },
  cmd = { 'DBUI', 'DBUIToggle', 'DBUIFindBuffer' },
  keys = {
    {
      '<leader>S',
      function()
        -- lazysql (lua/pc/db_tui.lua) or dadbod-ui's tree: Settings → Editor → Database
        local tui = require 'pc.db_tui'
        if (vim.g.pc_settings or {}).db_window ~= 'dadbod-ui' and tui.available() then
          return tui.toggle()
        end
        local tw = require 'pc.tool_window'
        tw.activate(tw.filetypes 'dbui', function()
          vim.cmd 'DBUIToggle'
        end)()
      end,
      desc = 'Database window',
    },
  },
  init = function()
    -- dadbod's own ftdetect is not read when it is loaded lazily (:DB); the result grid needs it
    vim.filetype.add { extension = { dbout = 'dbout' } }
    vim.g.db_ui_use_nerd_fonts = 1
    vim.g.db_ui_show_database_icon = 1
    vim.g.db_ui_execute_on_save = 0
    -- its <leader>S (execute) in SQL buffers would hide the Database window key; executing is
    -- Alt+Enter here, save query / bind parameters stay below
    vim.g.db_ui_disable_mappings_sql = 1
    -- A server that stops answering (VPN dropped, firewall) fails the query after 10 s with
    -- "timeout expired" instead of leaving the console waiting (psql and lazysql read it)
    if not vim.env.PGCONNECT_TIMEOUT then
      vim.env.PGCONNECT_TIMEOUT = '10'
    end
    -- Connections and saved queries live outside the projects
    vim.g.db_ui_save_location = vim.fn.stdpath 'data' .. '/dadbod'

    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'sql', 'mysql', 'plsql' },
      group = vim.api.nvim_create_augroup('pc-dadbod', { clear = true }),
      callback = function(event)
        local cmp = package.loaded['cmp'] and require 'cmp'
        if cmp then
          cmp.setup.buffer {
            sources = { { name = 'vim-dadbod-completion' }, { name = 'luasnip' } },
          }
        end
        vim.keymap.set('n', '<leader>W', '<Plug>(DBUI_SaveQuery)', { buffer = event.buf, desc = 'Save query' })
        vim.keymap.set('n', '<leader>E', '<Plug>(DBUI_EditBindParameters)', { buffer = event.buf, desc = 'Edit bind parameters' })
        -- Execute the statement under the cursor (paragraph) / the selection.
        -- Query buffers opened from the Database window know their connection; any other SQL
        -- file uses b:db / g:db, and asks for a saved connection when there is none.
        -- Both work on the last visual selection ('< '>).
        -- Query consoles (<leader>Qq) run on their connection + schema.
        -- Lines of the statement under the cursor: inside its paragraph, a statement ends with ;
        -- and a new one starts with a statement keyword at column 0 — not after UNION / EXCEPT /
        -- INTERSECT, a comma or an opening parenthesis, and a SELECT continues a WITH / INSERT /
        -- CREATE (CTE, INSERT … SELECT, CREATE … AS SELECT)
        local STARTS = { 'select', 'with', 'insert', 'update', 'delete', 'merge', 'create', 'alter', 'drop', 'truncate', 'grant', 'revoke', 'explain', 'analyze', 'vacuum', 'begin', 'commit', 'rollback', 'set', 'show', 'copy', 'call', 'do', 'refresh', 'comment' }
        local function keyword(line)
          local word = line:match '^(%a+)'
          return word and vim.tbl_contains(STARTS, word:lower()) and word:lower() or nil
        end
        local function boundary(line, prev, head)
          if vim.trim(prev):match ';$' then
            return true
          end
          local word = keyword(line)
          if not word then
            return false
          end
          local tail = vim.trim(prev):lower()
          if tail:match '[,(]$' or tail:match '%f[%a]union$' or tail:match '%f[%a]all$' or tail:match '%f[%a]except$' or tail:match '%f[%a]intersect$' then
            return false
          end
          return not (word == 'select' and (head == 'with' or head == 'insert' or head == 'create'))
        end
        local function statement_lines()
          local cur = vim.fn.line '.'
          local total = vim.fn.line '$'
          local function blank(n)
            return vim.trim(vim.fn.getline(n)) == ''
          end
          local p1, p2 = cur, cur
          while p1 > 1 and not blank(p1 - 1) do
            p1 = p1 - 1
          end
          while p2 < total and not blank(p2 + 1) do
            p2 = p2 + 1
          end
          -- split the paragraph into statements, keep the one with the cursor
          local first, head = p1, keyword(vim.fn.getline(p1))
          for n = p1 + 1, p2 do
            if boundary(vim.fn.getline(n), vim.fn.getline(n - 1), head) then
              if n > cur then
                return first, n - 1
              end
              first, head = n, keyword(vim.fn.getline(n))
            end
          end
          return first, p2
        end

        local function execute()
          require('lazy').load { plugins = { 'vim-dadbod-ui' } }
          local console = require 'pc.db_console'
          local first, last = vim.fn.line "'<", vim.fn.line "'>"
          console.record(vim.api.nvim_buf_get_lines(0, first - 1, last, false), console.connection_name(0))
          local url = console.url(0)
          if url then
            return vim.cmd("'<,'>DB " .. url)
          end
          if vim.b.dbui_db_key_name then
            return vim.api.nvim_feedkeys(vim.keycode 'gv<Plug>(DBUI_ExecuteQuery)', 'm', false)
          end
          if vim.b.db or vim.g.db then
            return vim.cmd "'<,'>DB"
          end
          vim.ui.select(vim.fn['db_ui#connections_list'](), {
            prompt = 'Run on connection',
            format_item = function(c)
              return c.name
            end,
          }, function(c)
            if c then
              vim.b.db = c.url
              vim.cmd "'<,'>DB"
            end
          end)
        end
        vim.keymap.set('n', '<M-CR>', function()
          -- the statement under the cursor (like IDEA, also when two are not separated by an
          -- empty line), then executed as a selection
          local first, last = statement_lines()
          vim.fn.setpos("'<", { 0, first, 1, 0 })
          vim.fn.setpos("'>", { 0, last, vim.v.maxcol, 0 })
          execute()
        end, { buffer = event.buf, desc = 'Execute statement' })
        vim.keymap.set('x', '<M-CR>', function()
          vim.cmd 'normal! \27'
          execute()
        end, { buffer = event.buf, desc = 'Execute selection' })
      end,
    })
  end,
}
