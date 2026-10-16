-- Optional ACP client configuration, maintained by agent-config.
-- Requires CodeCompanion.nvim and its documented dependencies.
if vim.fn.has("nvim-0.11") == 0 then
  return
end

local ok, codecompanion = pcall(require, "codecompanion")
if not ok then
  return
end

-- Choose at launch: AGENT_CONFIG_ACP_AGENT=claude_code|bob
-- Default to an agent available on this machine, without hiding the other.
local chosen = vim.env.AGENT_CONFIG_ACP_AGENT
if chosen ~= "bob" and chosen ~= "claude_code" then
  chosen = vim.fn.executable("bob") == 1 and "bob" or "claude_code"
end

codecompanion.setup({
  adapters = {
    acp = {
      -- Claude uses CodeCompanion's upstream claude_code preset.
      bob = function()
        local helpers = require("codecompanion.adapters.acp.helpers")
        return {
          name = "bob",
          formatted_name = "IBM Bob",
          type = "acp",
          roles = { llm = "assistant", user = "user" },
          commands = { default = { "bob", "acp" } },
          defaults = { mcpServers = {}, timeout = 20000 },
          parameters = {
            protocolVersion = 1,
            clientCapabilities = {
              fs = { readTextFile = true, writeTextFile = true },
            },
            clientInfo = { name = "CodeCompanion.nvim", version = "1.0.0" },
          },
          handlers = {
            setup = function() return true end,
            auth = function() return true end,
            form_messages = function(self, messages, capabilities)
              return helpers.form_messages(self, messages, capabilities)
            end,
            on_exit = function(self, code) end,
          },
        }
      end,
    },
  },
  interactions = { chat = { adapter = chosen } },
})

vim.keymap.set("n", "<leader>a", "<cmd>CodeCompanionChat Toggle<cr>", {
  desc = "Toggle AI chat",
})
