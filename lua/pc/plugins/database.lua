-- Database tool window + SQL console, like IDEA's Database plugin (vim-dadbod).
--   <leader>S        Database window: connections, schemas, tables, saved queries
--                    (add a connection with `A` there, e.g. postgres://user@localhost/db)
--   Alt+Enter        in a SQL buffer: execute the statement under the cursor / the selection
--                    (Console.Jdbc.Execute is Cmd+Enter in your macOS keymap)
-- Completion of tables and columns comes from the active connection.
return {
  'kristijanhusak/vim-dadbod-ui',
  dependencies = {
    { 'tpope/vim-dadbod', lazy = true },
    { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true },
  },
  cmd = { 'DBUI', 'DBUIToggle', 'DBUIAddConnection', 'DBUIFindBuffer' },
  keys = {
    { '<leader>S', '<cmd>DBUIToggle<CR>', desc = 'Database window' },
  },
  init = function()
    vim.g.db_ui_use_nerd_fonts = 1
    vim.g.db_ui_show_database_icon = 1
    vim.g.db_ui_execute_on_save = 0
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
        -- Execute the statement under the cursor (paragraph) / the selection.
        -- Query buffers opened from the Database window know their connection; any other SQL
        -- file uses b:db / g:db, and asks for a saved connection when there is none.
        -- Both work on the last visual selection ('< '>).
        local function execute()
          require('lazy').load { plugins = { 'vim-dadbod-ui' } }
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
          vim.cmd 'normal! vip\27'
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
