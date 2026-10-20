---@type Formatter
local M = {
  headers = { "REPOSITORY", "TAG", "ID", "CREATED", "SIZE" },
  empty = "No images found",

  format = function(images)
    local rows = {}
    for _, image in ipairs(images) do
      local tagged = image.Repository ~= "<none>" and image.Tag ~= "<none>"
      table.insert(rows, {
        row = { image.Repository, image.Tag, image.ID, image.CreatedSince or "", image.Size or "" },
        highlights = not tagged and { REPOSITORY = "DockerSucceeded", TAG = "DockerSucceeded" } or nil,
        item = vim.tbl_extend("force", image, {
          kind = "image",
          name = image.ID,
          ref = tagged and string.format("%s:%s", image.Repository, image.Tag) or image.ID,
        }),
      })
    end
    return rows
  end,
}

return M
