---@class Formatter
---@field headers string[] List of column headers
---@field format fun(data: table[], buffer: DockerBuffer): FormattedRow[] Turns the decoded docker output into rows
---@field empty string|nil Status shown when there are no rows

---@class FormattedRow
---@field row string[] The column values
---@field item DockerItem The item of the row
---@field diagnostics vim.Diagnostic[]|nil List of diagnostics for the row
---@field highlights table<string, string>|nil Highlight groups of cells, by header

---@class DockerItem The decoded docker output of a row, with:
---@field kind string e.g. `container`, `image`, `type`
---@field name string How docker.nvim buffers and docker commands refer to it
---@field ref string|nil The image reference to remove, `name` (the ID) when untagged

---@type table<string, Formatter> By buffer kind, or subresource
return {
  types = require("docker.formatters.types"),
  containers = require("docker.formatters.containers"),
  images = require("docker.formatters.images"),
  history = require("docker.formatters.history"),
  volumes = require("docker.formatters.volumes"),
  networks = require("docker.formatters.networks"),
  compose = require("docker.formatters.compose"),
}
