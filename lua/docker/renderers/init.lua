---@class Renderer
---@field load fun(buffer: DockerBuffer): vim.SystemObj|nil Load content for the buffer

---@type Renderer
local M = {
  load = function(buffer)
    if not buffer.name or buffer.subresource == "history" then
      return require("docker.renderers.resources").load(buffer)
    end
    if not buffer.subresource then
      return require("docker.renderers.inspect").load(buffer)
    end
    if buffer.subresource == "logs" then
      return require("docker.renderers.logs").load(buffer)
    end
    buffer:on_error()("Unknown subresource: " .. buffer.subresource)
    return nil
  end,
}

return M
