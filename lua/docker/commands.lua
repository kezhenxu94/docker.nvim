local M = {}

---@class CommandBase
---@field parse fun(args: string[]): table Parse command arguments into parameters
---@field complete fun(arglead: string, args: string[]): string[] Provide completions for the command

---@param candidates string[]
---@param arglead string|nil
---@return string[]
local function filter(candidates, arglead)
  return vim.tbl_filter(function(candidate)
    return vim.startswith(candidate, arglead or "")
  end, candidates)
end

---@type CommandBase
local GetCommand = {
  parse = function(args)
    local kind = table.remove(args, 1)
    local filters
    for _, arg in ipairs(args) do
      local key, value = arg:match("^([^=]+)=(.+)$")
      if key then
        filters = filters or {}
        filters[key] = value
      end
    end
    return { kind, filters }
  end,

  complete = function(arglead, args)
    if #args <= 1 then
      return filter(require("docker.cli").kinds(), arglead)
    end
    -- The common `docker ps --filter` keys, `project` is the compose project
    return filter({ "project=", "status=", "name=", "label=", "ancestor=", "network=", "volume=" }, arglead)
  end,
}

---@type CommandBase
local ContextCommand = {
  parse = function(args)
    return { args[1] }
  end,

  complete = function(arglead)
    return filter(require("docker.cli").context_names_sync(), arglead)
  end,
}

M.command_handlers = {
  get = GetCommand,
  context = ContextCommand,
}

M.commands = {
  get = function(...)
    require("docker").get(...)
  end,

  context = function(...)
    require("docker").ctx(...)
  end,
}

function M.setup()
  vim.api.nvim_create_user_command("Docker", function(opts)
    local args = vim.split(opts.args, " ", { trimempty = true })
    local command = table.remove(args, 1)

    local handler = M.command_handlers[command]
    if not handler then
      vim.notify("No such command: " .. (command or ""), vim.log.levels.ERROR)
      return
    end

    M.commands[command](unpack(handler.parse(args)))
  end, {
    nargs = "*",
    complete = function(arglead, cmdline)
      local args = vim.split(cmdline, " ", { trimempty = false })
      table.remove(args, 1) -- Remove the command name "Docker"

      if #args <= 1 then
        local commands = vim.tbl_keys(M.commands)
        table.sort(commands)
        return filter(commands, arglead)
      end

      local handler = M.command_handlers[table.remove(args, 1)]
      return handler and handler.complete(arglead, args) or {}
    end,
  })
end

return M
