-- Language servers stay out of Git views (pc.lsp_guard): no server starts or attaches in a
-- Diffview index buffer, a real file still gets it; sonarlint finds its jdtls when one root is
-- inside the other. Fake servers, nothing started. Prints OK / FAIL and quits.
local guard = require 'pc.lsp_guard'
local bad = {}
local function expect(name, ok)
  if not ok then
    table.insert(bad, name)
  end
end
local view = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(view, 'diffview:///repo/.git/:0:/main.tf')
expect('diffview buffer is a Git view', guard.git_view(view))
expect('a file is not', not guard.git_view(vim.api.nvim_create_buf(true, false)))
expect('jdt:// is not', not guard.git_view((function()
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, 'jdt://contents/rt.jar/java.lang/String.class')
  return b
end)()))
expect('no server starts there', vim.lsp.start({ name = 'fake', cmd = { 'false' } }, { bufnr = view }) == nil)
expect('no client attaches there', vim.lsp.buf_attach_client(view, 1) == false)

-- sonarlint ↔ jdtls by root
package.loaded['sonarlint.utils'] = {
  get_sonarlint_client = function() end,
  get_clients = function()
    return { { name = 'sonarlint.nvim', config = { root_dir = '/repo' } } }
  end,
}
package.loaded['sonarlint.java'] = { jdtls_attached_callback = function() end }
guard.sonarlint()
local utils = require 'sonarlint.utils'
expect('jdtls in a subfolder finds sonarlint', utils.get_sonarlint_client { config = { root_dir = '/repo/app' } } ~= nil)
expect('another project does not', utils.get_sonarlint_client { config = { root_dir = '/other' } } == nil)

io.stdout:write('\n' .. (#bad == 0 and 'OK lsp guard' or ('FAIL lsp guard: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
