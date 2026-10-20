---`:checkhealth docker`
local M = {}

function M.check()
  vim.health.start("docker.nvim")

  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim >= 0.11")
  else
    vim.health.error("Neovim >= 0.11 is required")
  end

  if vim.fn.executable("docker") == 0 then
    vim.health.error("docker not found in $PATH", "Install docker: https://docs.docker.com/get-docker/")
    return
  end

  local cli = require("docker.cli")
  local context = cli.get_current_context()
  if not context then
    vim.health.warn("No current context", "Set one with `docker context use` or `:Docker context`")
    return
  end
  vim.health.info("Context: " .. context .. (_G.docker.context and " (switched with :Docker context)" or ""))

  local version = vim
    .system(cli.cmd(context, { "version", "--format", "{{.Client.Version}} {{.Server.Version}}" }), { text = true })
    :wait(30000)
  local client, server = vim.trim(version.stdout or ""):match("^(%S+) (%S+)$")
  if version.code == 0 and server then
    vim.health.ok(string.format("docker %s, the daemon of %s (%s) is reachable", client, context, server))
  else
    vim.health.warn("The daemon of " .. context .. " is not reachable: " .. vim.trim(version.stderr or ""))
  end

  local compose = vim.system(cli.cmd(context, { "compose", "version", "--short" }), { text = true }):wait(10000)
  if compose.code == 0 then
    vim.health.ok("docker compose " .. vim.trim(compose.stdout or ""))
  else
    vim.health.info("docker compose is not available, compose projects (docker://compose) are not listed")
  end
end

return M
