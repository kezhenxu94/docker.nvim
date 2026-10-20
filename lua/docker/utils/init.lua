local M = {}

---@class DockerBufName
---@field context string|nil The docker context the buffer is bound to, nil for the current context
---@field kind string e.g. `containers`
---@field name string|nil The resource name
---@field subresource string|nil The subresource, e.g. `logs`
---@field params table<string, any>|nil Query parameters

---Build a buffer name: docker://[context/<context>/]<kind>[/<name>[/<subresource>]][?<params>]
---Without a context the buffer is pinned to the current context when it is opened.
---@param opts DockerBufName
---@return string
function M.buf_name(opts)
  local parts = { "docker:/" }
  if opts.context then
    -- Encoded as context names may contain `/` and `:`
    vim.list_extend(parts, { "context", vim.uri_encode(opts.context, "rfc2396") })
  end
  table.insert(parts, opts.kind)
  if opts.name then
    table.insert(parts, opts.name)
    if opts.subresource then
      table.insert(parts, opts.subresource)
    end
  end

  local buf_name = table.concat(parts, "/")

  local query = {}
  for key, value in pairs(opts.params or {}) do
    table.insert(query, string.format("%s=%s", key, tostring(value)))
  end
  if #query > 0 then
    table.sort(query)
    buf_name = buf_name .. "?" .. table.concat(query, "&")
  end
  return buf_name
end

---Open (or switch to) the buffer for the given name parts.
---@param opts DockerBufName
function M.open(opts)
  -- Escape as `%` (from the encoded context) and `#` are expanded by :edit
  vim.cmd.edit(vim.fn.fnameescape(M.buf_name(opts)))
end

---The table header for the winbar of `win`, aligned with its number column and horizontal scroll.
---@param buf_nr integer
---@param win integer|nil Defaults to the current window
---@return string
function M.get_winbar(buf_nr, win)
  win = win or vim.api.nvim_get_current_win()
  local buffer = _G.docker_buffers[buf_nr]
  if not buffer or not buffer.header_row then
    return ""
  end

  local header_row = buffer.header_row
  local wininfo = vim.fn.getwininfo(win)[1]
  local winbar_padding = string.rep(" ", wininfo and wininfo.textoff or 0)

  local leftcol = vim.api.nvim_win_call(win, function()
    return vim.fn.winsaveview().leftcol
  end)
  local indicator = ""
  if buffer.watch then
    indicator = string.format(" ⟳ %gs ", require("docker.refresh").interval() / 1000)
  end
  local width = vim.api.nvim_win_get_width(win) - #winbar_padding - vim.fn.strdisplaywidth(indicator)
  local header = header_row.formatted:sub(leftcol + 1):sub(1, math.max(width, 0))

  return string.format("%s%%#%s#%s%%=%%#Comment#%s", winbar_padding, header_row.highlight, header, indicator)
end

---Update the winbar of every window showing the buffer.
---@param dbuf DockerBuffer
function M.update_winbar(dbuf)
  for _, win in ipairs(vim.fn.win_findbuf(dbuf.buf_nr)) do
    vim.wo[win].winbar = M.get_winbar(dbuf.buf_nr, win)
  end
end

return M
