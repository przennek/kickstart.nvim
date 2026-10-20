-- Markdown preview like IDEA's editor-with-preview: rendered in the browser next to the editor,
-- scrolling along with the cursor and updating as you type; Mermaid diagrams, tables, code
-- highlighting and math are rendered too.
--   <leader>tm   toggle the preview (in Markdown files), :MarkdownPreview / :MarkdownPreviewStop
--   :Glow        quick preview inside Neovim (terminal rendering, no diagrams)
return {
  'iamcco/markdown-preview.nvim',
  cmd = { 'MarkdownPreview', 'MarkdownPreviewStop', 'MarkdownPreviewToggle' },
  ft = 'markdown',
  build = 'cd app && npm install --no-audit --no-fund',
  init = function()
    vim.g.mkdp_theme = 'dark'
    vim.g.mkdp_auto_close = 1 -- leaving the Markdown buffer closes its preview
    vim.g.mkdp_echo_preview_url = 1 -- the URL is shown too, for a browser on another machine
    vim.g.mkdp_page_title = '${name}'
    vim.g.mkdp_preview_options = { disable_sync_scroll = 0, sync_scroll_type = 'middle' }
  end,
  keys = {
    { '<leader>tm', '<cmd>MarkdownPreviewToggle<CR>', ft = 'markdown', desc = '[T]oggle [m]arkdown preview' },
  },
}
