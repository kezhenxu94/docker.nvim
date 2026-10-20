local M = {}

M.DOCKER_NAMESPACE = vim.api.nvim_create_namespace("docker")
M.DOCKER_COLUMN_NAMESPACE = vim.api.nvim_create_namespace("docker_column")

M.DOCKER_DIAGNOSTICS_NAMESPACE = vim.api.nvim_create_namespace("docker_diagnostics")
M.DOCKER_STATUS_NAMESPACE = vim.api.nvim_create_namespace("docker_status")
M.DOCKER_PENDING_NAMESPACE = vim.api.nvim_create_namespace("docker_pending")
M.DOCKER_CHANGED_NAMESPACE = vim.api.nvim_create_namespace("docker_changed")

return M
