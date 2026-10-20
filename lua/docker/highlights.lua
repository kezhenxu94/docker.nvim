---@class Highlights
---@field DockerBody table<string, any>
---@field DockerPending table<string, any>
---@field DockerRunning table<string, any>
---@field DockerFailed table<string, any>
---@field DockerSucceeded table<string, any>
---@field DockerHeader table<string, any>
---@field DockerDeleted table<string, any>
---@field DockerChanged table<string, any>

local M = {}

---Linked with `default`, so colorschemes and `:highlight` take precedence.
---@type Highlights
local default_highlights = {
  DockerBody = { link = "Normal" },
  DockerPending = { link = "DiagnosticWarn" },
  DockerRunning = { link = "Normal" },
  DockerFailed = { link = "DiagnosticError" },
  DockerSucceeded = { link = "Comment" },
  DockerHeader = { link = "Title" },
  -- Rows deleted from a list, until `:w` deletes the resources
  DockerDeleted = { link = "DiffDelete" },
  -- Rows a watched reload changed
  DockerChanged = { link = "DiffChange" },
}

---@type Highlights
local user_highlights = {}

---@param opts {highlights: Highlights|nil}|nil Overrides, kept for later calls without opts (ColorScheme)
function M.setup(opts)
  if opts and opts.highlights then
    user_highlights = opts.highlights
  end

  for group, hl in pairs(default_highlights) do
    vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", hl, { default = true }))
  end
  for group, hl in pairs(user_highlights) do
    vim.api.nvim_set_hl(0, group, hl)
  end
end

return M
