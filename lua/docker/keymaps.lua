local actions = require("docker.actions")
local operations = require("docker.operations")

---@param dbuf DockerBuffer
---@return DockerItem|nil The item under the cursor
local function item_under_cursor(dbuf)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  return operations.items_in_rows(dbuf, row, row)[1]
end

---Run the action for the item under the cursor.
---@param dbuf DockerBuffer
---@param action_name string
---@param ... any Extra arguments for the action
local function run_action(dbuf, action_name, ...)
  local item = item_under_cursor(dbuf)
  if not item then
    return
  end
  local action = (actions[item.kind] or {})[action_name]
  if not action then
    vim.notify(string.format("%s is not supported for %s", action_name, item.kind), vim.log.levels.WARN)
    return
  end
  action(dbuf, item, ...)
end

local M = {}

---@param buf_nr number
function M.setup_buffer_keymaps(buf_nr)
  local keymaps = require("docker.config").values.keymaps
  local dbuf = _G.docker_buffers[buf_nr]

  ---@param lhs string
  ---@param desc string
  ---@param fn function
  ---@param mode string|string[]|nil
  local function map(lhs, desc, fn, mode)
    vim.keymap.set(mode or "n", lhs, fn, { buffer = buf_nr, desc = "docker: " .. desc })
  end

  ---@param lhs string
  ---@param desc string
  ---@param action_name string
  ---@param ... any Extra arguments for the action
  local function map_action(lhs, desc, action_name, ...)
    local args = { ... }
    map(lhs, desc, function()
      run_action(dbuf, action_name, unpack(args))
    end)
  end

  map_action(keymaps.drill_down, "drill down into the item under the cursor", "drill_down")
  map_action(keymaps.show_logs, "show the logs of the item under the cursor", "show_logs", false)
  map_action(keymaps.follow_logs, "follow the logs of the item under the cursor", "show_logs", true)
  map_action(keymaps.exec, "open a shell in the container under the cursor", "exec")

  vim.bo[buf_nr].tagfunc = "v:lua.require'docker.navigation'.tagfunc"
  map(keymaps.inspect, "go to what the cell under the cursor refers to, mostly docker inspect", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local target = require("docker.navigation").tag_target(dbuf, { cursor[1] - 1, cursor[2] })
    if target then
      vim.cmd.edit(vim.fn.fnameescape(target))
    end
  end)

  map(keymaps.operations, "operations on the item under the cursor, or the selected ones", function()
    local mode = vim.api.nvim_get_mode().mode
    if mode == "n" then
      local row = vim.api.nvim_win_get_cursor(0)[1] - 1
      operations.select(dbuf, row, row)
      return
    end
    local first, last = vim.fn.line("v") - 1, vim.fn.line(".") - 1
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    operations.select(dbuf, math.min(first, last), math.max(first, last))
  end, { "n", "x" })

  map(keymaps.parent, "go to the parent buffer", function()
    local parent = require("docker.navigation").parent_name(dbuf)
    if parent then
      vim.cmd.edit(vim.fn.fnameescape(parent))
    end
  end)

  map(keymaps.help, "show this help", function()
    require("docker.help").show(buf_nr)
  end)

  map(keymaps.watch, "toggle reloading the list periodically", function()
    require("docker.refresh").toggle(dbuf)
  end)

  map(keymaps.refresh, "reload the buffer", function()
    dbuf:load()
  end)
end

return M
