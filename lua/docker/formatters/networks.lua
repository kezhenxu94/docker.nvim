---@type Formatter
local M = {
  headers = { "NAME", "ID", "DRIVER", "SCOPE" },
  empty = "No networks found",

  format = function(networks)
    local rows = {}
    for _, network in ipairs(networks) do
      table.insert(rows, {
        row = { network.Name, network.ID, network.Driver or "", network.Scope or "" },
        item = vim.tbl_extend("force", network, { kind = "network", name = network.Name }),
      })
    end
    return rows
  end,
}

return M
