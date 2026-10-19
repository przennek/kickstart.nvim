-- Refactor > Extract / Inline for the languages jdtls doesn't cover (Python, C, C++, Go, TS…),
-- on the same keys as Java (java.lua):
--   <leader>ev  Extract Variable      <leader>em, Ctrl+Alt+M (F43 via Alacritty)  Extract Method
--   <leader>ei  Inline Variable
-- Select the code in visual mode first (in normal mode they take a motion, e.g. <leader>ev iw).
local function refactor(fn)
  return function()
    return require('refactoring')[fn]()
  end
end

return {
  'ThePrimeagen/refactoring.nvim',
  -- async.nvim is only needed on Neovim 0.12
  dependencies = { 'lewis6991/async.nvim' },
  ft = { 'python', 'c', 'cpp', 'go', 'typescript', 'typescriptreact', 'javascript', 'lua' },
  config = function()
    local function maps(buf)
      local map = function(lhs, fn, desc)
        vim.keymap.set({ 'n', 'x' }, lhs, refactor(fn), { buffer = buf, expr = true, desc = desc })
      end
      map('<leader>ev', 'extract_var', 'Extract variable')
      map('<leader>em', 'extract_func', 'Extract method')
      -- a terminal can't tell Ctrl+Alt+M from Alt+Enter; Alacritty sends Ctrl+Shift+F7 (F43) instead
      map('<F43>', 'extract_func', 'Extract method')
      map('<leader>ei', 'inline_var', 'Inline')
    end
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'python', 'c', 'cpp', 'go', 'typescript', 'typescriptreact', 'javascript', 'lua' },
      group = vim.api.nvim_create_augroup('pc-refactor', { clear = true }),
      callback = function(event)
        maps(event.buf)
      end,
    })
    -- the buffer that triggered loading
    maps(0)
  end,
}
