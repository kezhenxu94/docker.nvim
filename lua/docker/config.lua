---@class DockerConfig
---@field keymaps table<string, string>|nil
---@field refresh_interval integer|false|nil
---@field exec_command string|nil
---@field logs {tail: integer, max_lines: integer}|nil
---@field highlights Highlights|nil
local M = {}

---@return DockerConfig
function M.defaults()
  return {
    -- Follows Neovim's conventions: tags (gd, <C-]> via 'tagfunc'), code actions (gra) and the
    -- built-in directory browser (<CR>, -, R)
    keymaps = {
      drill_down = "<cr>",
      inspect = "gd",
      parent = "-",
      refresh = "R",
      watch = "gw",
      show_logs = "gl",
      follow_logs = "gL",
      exec = "gs",
      operations = "gra",
      help = "g?",
    },
    -- How often watched lists (toggled with `gw`) reload, in milliseconds, false to disable watching
    refresh_interval = 10000,
    -- The command `gs` runs in containers
    exec_command = "sh",
    logs = {
      -- Number of lines to fetch, -1 for all
      tail = 1000,
      -- Lines kept while following, the oldest are dropped, -1 for all
      max_lines = 10000,
    },
  }
end

M.values = M.defaults()

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", M.defaults(), opts)
end

return M
