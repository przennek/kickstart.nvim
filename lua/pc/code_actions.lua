-- Show Context Actions (Alt+Enter) / Generate (Alt+Insert): the language servers' code actions,
-- each once. jdtls sends the generate / organize actions twice (as quick assists and as source
-- actions); IDEA's menus have them once.

local M = {}

function M.show()
  local seen = {}
  vim.lsp.buf.code_action {
    filter = function(action)
      if seen[action.title] then
        return false
      end
      seen[action.title] = true
      return true
    end,
  }
end

return M
