local utils = require("docker.utils")

---Actions on the item of a row, by item kind. They receive the buffer the item was selected
---from, which provides the context.
---@class Actions
---@field drill_down fun(dbuf: DockerBuffer, item: DockerItem)|nil
---@field show_logs fun(dbuf: DockerBuffer, item: DockerItem, follow: boolean)|nil
---@field exec fun(dbuf: DockerBuffer, item: DockerItem)|nil

---@param dbuf DockerBuffer
---@param opts DockerBufName Without the context, the buffer's is used
local function open(dbuf, opts)
  utils.open(vim.tbl_extend("force", opts, { context = dbuf.context }))
end

---@param kind string
---@return fun(dbuf: DockerBuffer, item: DockerItem, follow: boolean)
local function show_logs(kind)
  return function(dbuf, item, follow)
    open(dbuf, { kind = kind, name = item.name, subresource = "logs", params = follow and { follow = true } or nil })
  end
end

---@param filter string The `docker ps --filter` of the containers of the item
---@return fun(dbuf: DockerBuffer, item: DockerItem)
local function open_containers(filter)
  return function(dbuf, item)
    open(dbuf, { kind = "containers", params = { [filter] = item.name } })
  end
end

---@type table<string, Actions>
return {
  type = {
    drill_down = function(dbuf, item)
      open(dbuf, { kind = item.name })
    end,
  },
  container = {
    drill_down = show_logs("containers"),
    show_logs = show_logs("containers"),
    exec = function(dbuf, item)
      require("docker.utils.exec").open(dbuf.context, item.name)
    end,
  },
  image = {
    drill_down = function(dbuf, item)
      open(dbuf, { kind = "images", name = item.name, subresource = "history" })
    end,
  },
  volume = {
    drill_down = open_containers("volume"),
  },
  network = {
    drill_down = open_containers("network"),
  },
  compose = {
    drill_down = open_containers("project"),
    show_logs = show_logs("compose"),
  },
}
