-- Language servers stay out of Git views: Diffview's index buffer (diffview:///repo/.git/:0:/path)
-- is a normal buffer with a filetype, so terraformls attached to it and quit on the diffview://
-- workspace folder, and Java / sonarlint diagnostics landed on it before its lines were there
-- ("Index out of bounds" when Diffview or a file from the tree opened). jdt:// (decompiled
-- classes) still gets jdtls.
-- sonarlint finds its jdtls by the same project root only, but a Maven project in a subfolder of
-- the repo has the repo as sonarlint's root and the pom.xml folder as jdtls' root ("Cannot find
-- sonarlint client that matches to Java LSP client" on every Java file); either root inside the
-- other matches now, and a jdtls that attaches before sonarlint is up waits for it.

local M = {}

local SCHEMES = { diffview = true, fugitive = true, gitsigns = true }

function M.git_view(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return true
  end
  local scheme = vim.api.nvim_buf_get_name(bufnr):match '^(%a[%w+.-]*)://'
  return scheme ~= nil and SCHEMES[scheme] == true
end

local start = vim.lsp.start
vim.lsp.start = function(config, opts)
  local bufnr = opts and opts.bufnr or 0
  if M.git_view(bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr) then
    return nil
  end
  return start(config, opts)
end

local attach = vim.lsp.buf_attach_client
vim.lsp.buf_attach_client = function(bufnr, client_id)
  if M.git_view(bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr) then
    return false
  end
  return attach(bufnr, client_id)
end

local function inside(a, b)
  return a == b or vim.fs.relpath(a, b) ~= nil or vim.fs.relpath(b, a) ~= nil
end

function M.sonarlint()
  local utils = require 'sonarlint.utils'
  local java = require 'sonarlint.java'

  local find_sonarlint = utils.get_sonarlint_client
  utils.get_sonarlint_client = function(jdtls_client)
    local found = find_sonarlint(jdtls_client)
    if found or not jdtls_client or not jdtls_client.config.root_dir then
      return found
    end
    for _, client in ipairs(utils.get_clients { name = 'sonarlint.nvim' }) do
      if client.config.root_dir and inside(client.config.root_dir, jdtls_client.config.root_dir) then
        return client
      end
    end
  end

  -- sonarlint starts after jdtls sometimes (both are JVMs); try again for half a minute, quietly
  local attached = java.jdtls_attached_callback
  java.jdtls_attached_callback = function(event, tries)
    local jdtls = vim.lsp.get_client_by_id(event.data.client_id)
    if not jdtls or jdtls.name ~= 'jdtls' then
      return
    end
    if utils.get_sonarlint_client(jdtls) then
      return attached(event)
    end
    if (tries or 0) < 30 then
      vim.defer_fn(function()
        java.jdtls_attached_callback(event, (tries or 0) + 1)
      end, 1000)
    end
  end
end

return M
