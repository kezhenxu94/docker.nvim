local cli = require("docker.cli")

---The `docker inspect` JSON of the buffer's resource, read-only.
---@type Renderer
local M = {
  load = function(buffer)
    if not cli.inspectable(buffer.kind) then
      buffer:on_error()("Cannot inspect " .. buffer.kind)
      return nil
    end
    vim.bo[buffer.buf_nr].filetype = "json"

    local job = cli.inspect(buffer.context, buffer.kind, buffer.name, function(json)
      if json and vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
        buffer:set_lines(vim.split(vim.trim(json), "\n"), false)
      end
    end, buffer:on_error())

    if job then
      buffer.jobs[job.pid] = job
    end
    return job
  end,
}

return M
