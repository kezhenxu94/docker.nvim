---The highlight of a project status, e.g. `running(2)`, `exited(1)`, `running(1), exited(2)`.
---@param status string
---@return string
local function highlight(status)
  if status:find(",", 1, true) or status:find("restarting", 1, true) then
    return "DockerPending"
  elseif vim.startswith(status, "running") then
    return "DockerRunning"
  end
  return "DockerSucceeded"
end

---The compose projects, `docker compose ls --all`.
---@type Formatter
local M = {
  headers = { "NAME", "STATUS", "CONFIG FILES" },
  empty = "No compose projects found",

  format = function(projects)
    local rows = {}
    for _, project in ipairs(projects) do
      table.insert(rows, {
        row = { project.Name, project.Status or "", project.ConfigFiles or "" },
        highlights = { STATUS = highlight(project.Status or "") },
        item = vim.tbl_extend("force", project, { kind = "compose", name = project.Name }),
      })
    end
    return rows
  end,
}

return M
