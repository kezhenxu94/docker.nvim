local DESCRIPTIONS = {
  containers = "Containers, running or not (docker ps --all)",
  images = "Images (docker images)",
  volumes = "Volumes (docker volume ls)",
  networks = "Networks (docker network ls)",
  compose = "Compose projects (docker compose ls --all)",
}

---The kinds docker.nvim lists, rows open their list.
---@type Formatter
local M = {
  headers = { "NAME", "DESCRIPTION" },

  format = function()
    local rows = {}
    for _, kind in ipairs(require("docker.cli").kinds()) do
      table.insert(rows, {
        row = { kind, DESCRIPTIONS[kind] or "" },
        item = { kind = "type", name = kind },
      })
    end
    return rows
  end,
}

return M
