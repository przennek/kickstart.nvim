-- Highlight, edit, and navigate code
-- nvim-treesitter `main` branch (the old `master` one breaks on Neovim 0.12, e.g. in Markdown).
-- It only installs parsers and queries; highlighting/indent are started per filetype below.
-- Needs tree-sitter-cli, which Mason installs (see lsp.lua).
local parsers = { 'bash', 'c', 'cpp', 'diff', 'html', 'java', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'python', 'query', 'vim', 'vimdoc', 'xml', 'yaml', 'json' }

return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false,
  build = ':TSUpdate',
  config = function()
    local ts = require 'nvim-treesitter'
    ts.install(parsers)

    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('pc-treesitter', { clear = true }),
      callback = function(event)
        local lang = vim.treesitter.language.get_lang(event.match)
        if not lang then
          return
        end
        local function start()
          if vim.api.nvim_buf_is_valid(event.buf) and pcall(vim.treesitter.start, event.buf, lang) then
            vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end
        -- Autoinstall languages that are not installed yet
        if not vim.tbl_contains(ts.get_installed(), lang) and vim.tbl_contains(ts.get_available(), lang) then
          ts.install(lang):await(vim.schedule_wrap(start))
        else
          start()
        end
      end,
    })

    -- Extend Selection / Shrink Selection (Alt+W / Alt+Shift+W in IDEA), built on Neovim's
    -- node selection (:help v_an, v_in). Called directly because mini.ai takes over `an` / `in`.
    local function select_node(parent)
      return function()
        if vim.treesitter.get_parser(nil, nil, { error = false }) then
          require('vim.treesitter._select')[parent and 'select_parent' or 'select_child'](vim.v.count1)
        else
          vim.lsp.buf.selection_range(parent and vim.v.count1 or -vim.v.count1)
        end
      end
    end
    vim.keymap.set('x', '<M-w>', select_node(true), { desc = 'Extend selection' })
    vim.keymap.set('x', '<M-W>', select_node(false), { desc = 'Shrink selection' })
    vim.keymap.set('n', '<M-w>', 'v<M-w>', { remap = true, desc = 'Extend selection' })
  end,
}
