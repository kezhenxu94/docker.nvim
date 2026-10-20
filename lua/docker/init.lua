local M = {}

local initialized = false

---Define the commands and autocmds, called from plugin/docker.lua so that setup() is optional.
function M.init()
  if initialized then
    return
  end
  initialized = true

  require("docker.highlights").setup()
  require("docker.autocmds").setup()
  require("docker.commands").setup()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = require("docker.autocmds").augroup,
    callback = function()
      for _, buffer in pairs(_G.docker_buffers or {}) do
        buffer:stop_jobs()
      end
    end,
    desc = "Stop all docker jobs when exiting vim",
  })
end

---Configure docker.nvim, optional: see `require("docker.config").defaults()`.
---@param opts DockerConfig|nil
function M.setup(opts)
  opts = opts or {}

  require("docker.config").setup(opts)
  require("docker.refresh").restart()
  require("docker.highlights").setup(opts)
  M.init()
end

---@param kind string The kind to list
---@param filters table<string, string>|nil `docker … --filter key=value`
function M.get(kind, filters)
  require("docker.utils").open({ kind = kind, params = filters })
end

---@param context string|nil The context to switch to, prompts for it when nil
function M.ctx(context)
  local cli = require("docker.cli")
  if context then
    cli.use_context(context)
    vim.notify(string.format("Switched to context: %s", context))
    return
  end

  cli.contexts(function(result)
    if not result then
      vim.notify("No contexts found", vim.log.levels.ERROR)
      return
    end

    local current = cli.get_current_context()
    vim.ui.select(cli.decode(result), {
      prompt = string.format("Select context (current: %s)", current),
      format_item = function(item)
        return string.format("%s%s", item.Name == current and "* " or "  ", item.Name)
      end,
    }, function(choice)
      if choice then
        M.ctx(choice.Name)
      end
    end)
  end)
end

return M
