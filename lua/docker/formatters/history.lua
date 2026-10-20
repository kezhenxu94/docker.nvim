---The layers of an image, `docker history`.
---@type Formatter
local M = {
  headers = { "CREATED", "CREATED BY", "SIZE", "COMMENT" },

  format = function(layers)
    local rows = {}
    for i, layer in ipairs(layers) do
      table.insert(rows, {
        row = { layer.CreatedSince or "", layer.CreatedBy or "", layer.Size or "", layer.Comment or "" },
        -- Most layers are `<missing>`
        item = vim.tbl_extend("force", layer, { kind = "layer", name = string.format("%d:%s", i, layer.ID) }),
      })
    end
    return rows
  end,
}

return M
