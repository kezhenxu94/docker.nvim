local cli = require("docker.cli")
local constants = require("docker.constants")
local log = require("docker.log")

---The logs of a container or a compose project.
---@type Renderer
local M = {

  ---@param buffer DockerBuffer The buffer to render into
  load = function(buffer)
    local self = buffer
    local params = self.params or {}

    log.debug("loading log buffer", self.kind, self.name, params)

    if self.kind ~= "containers" and self.kind ~= "compose" then
      self:on_error()("Logs are only available for containers and compose projects")
      return nil
    end

    local opts = {
      follow = params.follow == true,
      since = params.since,
      tail = tonumber(params.tail),
    }
    local follow = opts.follow
    ---@type integer|nil
    local status_mark

    ---@param text string
    local function set_status(text)
      status_mark = vim.api.nvim_buf_set_extmark(
        self.buf_nr,
        constants.DOCKER_NAMESPACE,
        vim.api.nvim_buf_line_count(self.buf_nr) - 1,
        0,
        { id = status_mark, virt_text = { { text, "Comment" } }, virt_text_pos = "overlay" }
      )
    end

    local job = cli.logs(self.context, self.kind, self.name, opts, function(result)
      if not vim.api.nvim_buf_is_loaded(self.buf_nr) then
        return
      end

      self:setup()

      local lines = vim.split(result, "\n")
      if not follow then
        self:set_lines(lines, true)
        return
      end

      self:set_status(nil)
      vim.bo[self.buf_nr].modifiable = true
      -- Replace the trailing placeholder line, then add a new one for the status
      local start = vim.api.nvim_buf_line_count(self.buf_nr)
      -- Windows at the end keep showing the new lines, like `tail -f`
      local at_end = vim.tbl_filter(function(win)
        return vim.api.nvim_win_get_cursor(win)[1] >= start - 1
      end, vim.fn.win_findbuf(self.buf_nr))
      vim.api.nvim_buf_set_lines(self.buf_nr, start - 1, -1, false, lines)
      vim.api.nvim_buf_set_lines(self.buf_nr, -1, -1, false, { "" })
      local max_lines = require("docker.config").values.logs.max_lines
      local excess = vim.api.nvim_buf_line_count(self.buf_nr) - 1 - max_lines
      if max_lines >= 0 and excess > 0 then
        vim.api.nvim_buf_set_lines(self.buf_nr, 0, excess, false, {})
      end
      set_status("Waiting for new logs... (Ctrl+C to stop)")
      for _, win in ipairs(at_end) do
        vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(self.buf_nr), 0 })
      end
    end, self:on_error())

    if not job then
      return nil
    end

    self.jobs[job.pid] = job
    log.debug("job", job.pid, "started")

    if follow then
      vim.keymap.set("n", "<C-c>", function()
        if self.jobs[job.pid] then
          log.debug("killing job", job.pid)
          cli.kill(job)
          self.jobs[job.pid] = nil
          set_status("Stopped following logs, to restart, re-edit this buffer with `:e`")
        end
      end, { buffer = self.buf_nr, desc = "Stop docker logs job" })
    end
    return job
  end,
}

return M
