local M = {}

---Start the shell of a `…/exec` buffer (see `require("docker.utils").buf_name`) in the current
---buffer, from BufReadCmd: the name is all it takes, like `term://` buffers.
---@param name string The buffer name
---@param parts DockerBufNameParts
function M.start(name, parts)
  if parts.kind ~= "containers" or not parts.name then
    vim.notify("Expected: docker://context/{context}/containers/{name}/exec[?cmd={command}]", vim.log.levels.ERROR)
    return
  end
  local params = parts.params or {}
  local command = type(params.cmd) == "string" and params.cmd or require("docker.config").values.exec_command
  vim.fn.jobstart(require("docker.cli").exec_cmd(parts.context, parts.name, command), { term = true })
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false

  -- jobstart() names the buffer `term://…`: keep the name, so editing it again finds the shell.
  -- :file leaves a buffer with the old name, unlike jobstart().
  local term_name = vim.api.nvim_buf_get_name(0)
  if term_name == name then
    return
  end
  vim.cmd("keepalt file " .. vim.fn.fnameescape(name))
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == term_name then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end

---Open a shell in a container, it is started by BufReadCmd unless it already exists.
---@param context string
---@param name string The container
function M.open(context, name)
  require("docker.utils").open({ context = context, kind = "containers", name = name, subresource = "exec" })
  vim.cmd("startinsert")
end

return M
