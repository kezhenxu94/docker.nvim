if vim.g.loaded_docker then
  return
end
vim.g.loaded_docker = true

if vim.fn.has("nvim-0.11") == 0 then
  vim.notify("docker.nvim requires Neovim >= 0.11", vim.log.levels.ERROR)
  return
end

require("docker").init()
