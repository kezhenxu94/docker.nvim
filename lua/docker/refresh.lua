---Opt-in periodic reload of resource lists ("watch"), toggled per buffer.
local M = {}

---@type uv.uv_timer_t|nil
local timer

---Tables, as opposed to inspect / logs buffers.
---@param dbuf DockerBuffer
---@return boolean
function M.is_table(dbuf)
  return not dbuf.name or dbuf.subresource == "history"
end

---@param dbuf DockerBuffer
---@return boolean
local function should_refresh(dbuf)
  local buf = dbuf.buf_nr
  if not dbuf.watch or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].modified then
    return false
  end
  if dbuf.loading_job and not dbuf.loading_job:is_closing() then
    return false
  end
  if #vim.fn.win_findbuf(buf) == 0 then
    return false
  end
  -- Do not move lines under a visual selection or a pending operator
  return vim.api.nvim_get_current_buf() ~= buf or vim.api.nvim_get_mode().mode == "n"
end

function M.tick()
  local watching = false
  for _, dbuf in pairs(_G.docker_buffers or {}) do
    watching = watching or dbuf.watch == true
    if should_refresh(dbuf) then
      dbuf:load({ silent = true })
    end
  end
  if not watching then
    M.stop()
  end
end

---@return integer|false The interval in milliseconds, false when disabled
function M.interval()
  return require("docker.config").values.refresh_interval
end

local function start()
  local interval = M.interval()
  if timer or not interval then
    return
  end
  timer = assert(vim.uv.new_timer())
  timer:start(interval, interval, vim.schedule_wrap(M.tick))
end

function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

---Toggle watching the buffer.
---@param dbuf DockerBuffer
function M.toggle(dbuf)
  if not M.is_table(dbuf) then
    vim.notify("Only resource lists can be watched", vim.log.levels.WARN)
    return
  end
  if not M.interval() then
    vim.notify("Watching is disabled, set refresh_interval to enable it", vim.log.levels.WARN)
    return
  end
  dbuf.watch = not dbuf.watch
  if dbuf.watch then
    start()
  end
  require("docker.utils").update_winbar(dbuf)
end

---Apply a new interval to the running timer.
function M.restart()
  if timer then
    M.stop()
    start()
  end
end

return M
