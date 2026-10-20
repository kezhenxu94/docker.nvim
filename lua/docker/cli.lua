local log = require("docker.log")

local M = {}

_G.docker = _G.docker or {}

local function get_state_file_path()
  return vim.fn.stdpath("state") .. "/docker_state.json"
end

local function save_state()
  local file = io.open(get_state_file_path(), "w")
  if file then
    file:write(vim.json.encode({ context = _G.docker.context }))
    file:close()
  end
end

local function load_state()
  local file = io.open(get_state_file_path(), "r")
  if file then
    local json_str = file:read("*all")
    file:close()

    local ok, state = pcall(vim.json.decode, json_str)
    if ok and type(state) == "table" and type(state.context) == "string" then
      _G.docker.context = state.context
    end
  end
end

load_state()

-- Upper bound for synchronous calls (completion, the current context), an unreachable daemon cannot freeze Neovim
local SYNC_TIMEOUT_MS = 10000

---@param context string|nil The context to run against, nil for docker's current context
---@param args string[] docker arguments, without the global `--context` flag
---@return string[]
function M.cmd(context, args)
  if context then
    return vim.list_extend({ "docker", "--context", context }, args)
  end
  return vim.list_extend({ "docker" }, args)
end

---Run docker asynchronously, callbacks are invoked on the main loop.
---@param context string|nil
---@param args string[]
---@param callback fun(data: string|nil, code: integer, stderr: string)|nil Called with stdout on success, nil on failure
---@param on_error fun(data: string)|nil Called with stderr on failure
---@return vim.SystemObj|nil
local function docker(context, args, callback, on_error)
  local cmd = M.cmd(context, args)
  log.debug("docker", cmd)

  local ok, job = pcall(
    vim.system,
    cmd,
    { text = true },
    vim.schedule_wrap(function(out)
      local success = out.code == 0
      if not success and on_error then
        on_error(vim.trim(out.stderr or ""))
      end
      if callback then
        callback(success and out.stdout or nil, out.code, out.stderr or "")
      end
    end)
  )
  if not ok then
    vim.notify("Failed to run docker: " .. tostring(job), vim.log.levels.ERROR)
    return nil
  end
  return job
end

---Run docker synchronously.
---@param context string|nil
---@param args string[]
---@return string[] Lines of stdout, empty on failure
local function docker_sync(context, args)
  local ok, out = pcall(function()
    return vim.system(M.cmd(context, args), { text = true }):wait(SYNC_TIMEOUT_MS)
  end)
  if not ok or out.code ~= 0 then
    return {}
  end
  return vim.split(out.stdout, "\n", { trimempty = true })
end

local JSON = "--format={{json .}}"

---The list commands by kind
local LIST = {
  containers = { "ps", "--all", JSON },
  images = { "images", JSON },
  volumes = { "volume", "ls", JSON },
  networks = { "network", "ls", JSON },
  compose = { "compose", "ls", "--all", "--format=json" },
}

---The `inspect` commands by kind
local INSPECT = {
  containers = { "container", "inspect" },
  images = { "image", "inspect" },
  volumes = { "volume", "inspect" },
  networks = { "network", "inspect" },
}

---@return string[] The kinds that can be listed
function M.kinds()
  local kinds = vim.tbl_keys(LIST)
  table.sort(kinds)
  return kinds
end

---@param kind string
---@return boolean
function M.inspectable(kind)
  return INSPECT[kind] ~= nil
end

---Decode the output of a list command: JSON lines, or a JSON array for `compose ls`.
---@param output string
---@return table[]
function M.decode(output)
  output = vim.trim(output)
  if vim.startswith(output, "[") then
    return vim.json.decode(output)
  end
  local items = {}
  for _, line in ipairs(vim.split(output, "\n", { trimempty = true })) do
    table.insert(items, vim.json.decode(line))
  end
  return items
end

---@param context string|nil
---@param kind string
---@param filters table<string, any>|nil `--filter key=value`, `project` is the compose project label
---@param callback fun(data: string|nil)
---@param on_error fun(data: string)|nil
---@return vim.SystemObj|nil
function M.list(context, kind, filters, callback, on_error)
  local args = vim.list_extend({}, (assert(LIST[kind], "unknown kind: " .. kind)))
  local keys = vim.tbl_keys(filters or {})
  table.sort(keys)
  for _, key in ipairs(keys) do
    local filter = string.format("%s=%s", key, tostring(filters[key]))
    if key == "project" then
      filter = "label=com.docker.compose.project=" .. tostring(filters[key])
    end
    vim.list_extend(args, { "--filter", filter })
  end
  return docker(context, args, callback, on_error)
end

---@param context string|nil
---@param kind string
---@param name string
---@param callback fun(data: string|nil)
---@param on_error fun(data: string)|nil
---@return vim.SystemObj|nil
function M.inspect(context, kind, name, callback, on_error)
  local args = vim.list_extend({}, (assert(INSPECT[kind], "cannot inspect " .. kind)))
  table.insert(args, name)
  return docker(context, args, callback, on_error)
end

---@param context string|nil
---@param image string
---@param callback fun(data: string|nil)
---@param on_error fun(data: string)|nil
---@return vim.SystemObj|nil
function M.history(context, image, callback, on_error)
  return docker(context, { "history", JSON, image }, callback, on_error)
end

---@class DockerLogsOpts
---@field follow boolean|nil Follow the logs (tail -f style)
---@field since string|nil Only logs newer than a duration or a timestamp, e.g. 1h
---@field tail integer|nil Number of lines, defaults to `logs.tail` of the config, -1 for all

---The logs of a container or a compose project, stdout and stderr in order.
---@param context string|nil
---@param kind "containers"|"compose"
---@param name string
---@param opts DockerLogsOpts
---@param callback fun(data: string) Called with complete lines (newline separated)
---@param on_error fun(data: string)|nil
---@return vim.SystemObj|nil
function M.logs(context, kind, name, opts, callback, on_error)
  local args = kind == "compose" and { "compose", "--project-name", name, "logs", "--no-color" } or { "logs" }
  table.insert(args, "--tail=" .. tostring(opts.tail or require("docker.config").values.logs.tail))
  if opts.since then
    table.insert(args, "--since=" .. opts.since)
  end
  if opts.follow then
    table.insert(args, "--follow")
  end
  if kind ~= "compose" then
    table.insert(args, name)
  end
  -- The output of the container goes to both, merged to keep the order
  local cmd = { "sh", "-c", table.concat(vim.tbl_map(vim.fn.shellescape, M.cmd(context, args)), " ") .. " 2>&1" }
  log.debug("docker.logs", cmd)

  ---Emit only complete lines, as output arrives in arbitrary chunks
  local pending = ""
  local function on_stdout(_, data)
    if not data then
      if pending ~= "" then
        vim.schedule_wrap(callback)(pending)
        pending = ""
      end
      return
    end
    pending = pending .. data
    local last_newline = pending:match(".*()\n")
    if last_newline then
      vim.schedule_wrap(callback)(pending:sub(1, last_newline - 1))
      pending = pending:sub(last_newline + 1)
    end
  end

  local output = {}
  local ok, job = pcall(vim.system, cmd, {
    text = true,
    stdout = opts.follow and on_stdout or function(_, data)
      table.insert(output, data)
    end,
  }, function(out)
    if opts.follow then
      return
    end
    local text = table.concat(output):gsub("\n$", "")
    if out.code ~= 0 and on_error then
      vim.schedule_wrap(on_error)(text)
    elseif out.code == 0 then
      vim.schedule_wrap(callback)(text)
    end
  end)
  if not ok then
    vim.notify("Failed to run docker: " .. tostring(job), vim.log.levels.ERROR)
    return nil
  end
  return job
end

---Remove a resource, see the formatters for the items.
---@param context string|nil
---@param item {kind: string, name: string, ref: string|nil}
---@param callback fun(data: string|nil)|nil
---@param on_error fun(data: string)|nil
---@return vim.SystemObj|nil
function M.remove(context, item, callback, on_error)
  local args = ({
    container = { "rm", "--force", item.name },
    -- By the tag, an image with several tags is only untagged
    image = { "rmi", item.ref or item.name },
    volume = { "volume", "rm", item.name },
    network = { "network", "rm", item.name },
    compose = { "compose", "--project-name", item.name, "down" },
  })[item.kind]
  return docker(context, assert(args, "cannot remove " .. item.kind), callback, on_error)
end

---@param context string|nil
---@param verb "start"|"stop"|"restart"|"pause"|"unpause"|"kill"
---@param name string
---@param callback fun(data: string|nil)|nil
---@param on_error fun(data: string)|nil
---@return vim.SystemObj|nil
function M.container(context, verb, name, callback, on_error)
  return docker(context, { verb, name }, callback, on_error)
end

---@param context string|nil
---@param verb "start"|"stop"|"restart"
---@param project string
---@param callback fun(data: string|nil)|nil
---@param on_error fun(data: string)|nil
---@return vim.SystemObj|nil
function M.compose(context, verb, project, callback, on_error)
  return docker(context, { "compose", "--project-name", project, verb }, callback, on_error)
end

---@param context string|nil
---@param ref string
---@param callback fun(data: string|nil)|nil
---@param on_error fun(data: string)|nil
---@return vim.SystemObj|nil
function M.pull(context, ref, callback, on_error)
  return docker(context, { "pull", "--quiet", ref }, callback, on_error)
end

---The command of a shell in a container.
---@param context string|nil
---@param name string
---@param command string
---@return string[]
function M.exec_cmd(context, name, command)
  return M.cmd(context, { "exec", "--interactive", "--tty", name, command })
end

---@return string|nil The context switched to via `:Docker context`, or docker's current context
function M.get_current_context()
  return _G.docker.context or docker_sync(nil, { "context", "show" })[1]
end

---@param callback fun(data: string|nil)
---@return vim.SystemObj|nil
function M.contexts(callback)
  return docker(nil, { "context", "ls", JSON }, callback)
end

---@return string[] The names of the contexts
function M.context_names_sync()
  return docker_sync(nil, { "context", "ls", "--format={{.Name}}" })
end

---Use a context for docker.nvim only, docker's current context is left as is.
---@param name string
function M.use_context(name)
  _G.docker.context = name
  save_state()
end

---Kill a job if it is still running.
---@param job vim.SystemObj|nil
function M.kill(job)
  if job and not job:is_closing() then
    job:kill(15)
  end
end

return M
