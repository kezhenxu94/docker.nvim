---@type Formatter
local M = {
  headers = { "NAME", "DRIVER", "SCOPE", "MOUNTPOINT" },
  empty = "No volumes found",

  format = function(volumes)
    local rows = {}
    for _, volume in ipairs(volumes) do
      table.insert(rows, {
        row = { volume.Name, volume.Driver or "", volume.Scope or "", volume.Mountpoint or "" },
        item = vim.tbl_extend("force", volume, { kind = "volume", name = volume.Name }),
      })
    end
    return rows
  end,
}

return M
