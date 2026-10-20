local severity = vim.diagnostic.severity

---@param labels string The labels of `docker ps`, `key=value` comma separated
---@param key string
---@return string|nil
local function label(labels, key)
  return ("," .. (labels or "")):match("," .. vim.pesc(key) .. "=([^,]*)")
end

---The highlight of the STATUS and the diagnostic of a container.
---@param container table
---@return string highlight
---@return vim.Diagnostic|nil
local function status(container)
  local state, text = container.State, container.Status or ""
  if state == "running" then
    if text:find("(unhealthy)", 1, true) then
      return "DockerFailed", { message = "The container is unhealthy", severity = severity.ERROR }
    elseif text:find("(health: starting)", 1, true) then
      return "DockerPending"
    end
    return "DockerRunning"
  elseif state == "exited" then
    local code = tonumber(text:match("^Exited %((%-?%d+)%)"))
    if code and code ~= 0 then
      return "DockerFailed", { message = string.format("Exited with code %d", code), severity = severity.ERROR }
    end
    return "DockerSucceeded"
  elseif state == "restarting" then
    return "DockerPending", { message = "The container is restarting", severity = severity.WARN }
  elseif state == "dead" then
    return "DockerFailed", { message = "The container is dead", severity = severity.ERROR }
  end
  -- created, paused, removing
  return "DockerPending"
end

---@type Formatter
local M = {
  headers = { "NAME", "IMAGE", "STATUS", "PORTS", "PROJECT", "CREATED", "ID" },
  empty = "No containers found",

  format = function(containers)
    local rows = {}
    for _, container in ipairs(containers) do
      local highlight, diagnostic = status(container)
      table.insert(rows, {
        row = {
          container.Names,
          container.Image,
          container.Status,
          container.Ports or "",
          label(container.Labels, "com.docker.compose.project") or "",
          container.RunningFor or "",
          container.ID,
        },
        highlights = { STATUS = highlight },
        diagnostics = diagnostic and { diagnostic } or nil,
        item = vim.tbl_extend("force", container, { kind = "container", name = container.Names }),
      })
    end
    return rows
  end,
}

M.label = label

return M
