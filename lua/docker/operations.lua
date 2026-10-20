---Operations on the items of buffer rows, offered by `gra`.
local actions = require("docker.actions")
local cli = require("docker.cli")
local confirm = require("docker.confirm")
local constants = require("docker.constants")

local M = {}

---@class DockerOperation
---@field title string
---@field run fun()

---@param items DockerItem[]
---@return string
local function describe_targets(items)
  local names = vim.tbl_map(function(item)
    return string.format("%s %s", item.kind, item.ref or item.name)
  end, items)
  if #names > 3 then
    return string.format("%s and %d more", table.concat(vim.list_slice(names, 1, 3), ", "), #names - 3)
  end
  return table.concat(names, ", ")
end

---Run a docker command on every item, then reload the buffer.
---@param dbuf DockerBuffer
---@param items DockerItem[]
---@param call fun(item: DockerItem, callback: fun(data: string|nil), on_error: fun(err: string))
local function run(dbuf, items, call)
  local remaining = #items
  local function finished()
    remaining = remaining - 1
    if remaining == 0 then
      dbuf:load()
    end
  end
  for _, item in ipairs(items) do
    call(item, function(result)
      if result and vim.trim(result) ~= "" then
        vim.notify(vim.trim(result))
      end
      finished()
    end, function(err)
      vim.notify(err, vim.log.levels.ERROR)
      finished()
    end)
  end
end

---@param dbuf DockerBuffer
---@param items DockerItem[]
---@param verb string
---@param call fun(item: DockerItem, callback: fun(data: string|nil), on_error: fun(err: string))
local function confirmed(dbuf, items, verb, call)
  confirm(string.format("%s %s (context: %s)?", verb, describe_targets(items), dbuf.context), function(yes)
    if yes then
      run(dbuf, items, call)
    end
  end)
end

---@param verb string
---@return string
local function title(verb)
  return verb:sub(1, 1):upper() .. verb:sub(2)
end

---The kinds of items that can be removed, to name them in bulk operations
local PLURALS = {
  container = "containers",
  image = "images",
  volume = "volumes",
  network = "networks",
  compose = "compose projects",
}

---Verbs of `docker {verb} {container}`, and whether they need a confirmation
local CONTAINER_VERBS = {
  { "start", false },
  { "stop", true },
  { "restart", true },
  { "pause", false },
  { "unpause", false },
  { "kill", true },
}

---Verbs of `docker compose --project-name {project} {verb}`
local COMPOSE_VERBS = { { "start", false }, { "stop", true }, { "restart", true } }

---@param dbuf DockerBuffer
---@param items DockerItem[]
---@param verbs {[1]: string, [2]: boolean}[]
---@param call fun(context: string, verb: string, name: string, callback: function, on_error: function)
---@return DockerOperation[]
local function verb_operations(dbuf, items, verbs, call)
  local operations = {}
  for _, verb in ipairs(verbs) do
    local name, needs_confirm = verb[1], verb[2]
    table.insert(operations, {
      title = title(name),
      run = function()
        local fn = function(item, callback, on_error)
          call(dbuf.context, name, item.name, callback, on_error)
        end
        if needs_confirm then
          confirmed(dbuf, items, title(name), fn)
        else
          run(dbuf, items, fn)
        end
      end,
    })
  end
  return operations
end

---The operations for the items of the given buffer rows, all of the same kind.
---@param dbuf DockerBuffer
---@param items DockerItem[]
---@return DockerOperation[]
function M.for_items(dbuf, items)
  if #items == 0 then
    return {}
  end
  local kind = items[1].kind
  local operations = {}

  if #items == 1 then
    local item = items[1]
    local item_actions = actions[kind] or {}
    if item_actions.show_logs then
      table.insert(operations, {
        title = "Logs",
        run = function()
          item_actions.show_logs(dbuf, item, false)
        end,
      })
      table.insert(operations, {
        title = "Follow logs",
        run = function()
          item_actions.show_logs(dbuf, item, true)
        end,
      })
    end
    if item_actions.exec then
      table.insert(operations, {
        title = "Exec",
        run = function()
          item_actions.exec(dbuf, item)
        end,
      })
    end
    if kind == "image" then
      table.insert(operations, {
        title = "History",
        run = function()
          item_actions.drill_down(dbuf, item)
        end,
      })
    end
  end

  if kind == "container" then
    vim.list_extend(operations, verb_operations(dbuf, items, CONTAINER_VERBS, cli.container))
  elseif kind == "compose" then
    vim.list_extend(operations, verb_operations(dbuf, items, COMPOSE_VERBS, cli.compose))
  elseif kind == "image" then
    local tagged = vim.tbl_filter(function(item)
      return item.ref ~= item.name
    end, items)
    if #tagged == #items then
      table.insert(operations, {
        title = "Pull",
        run = function()
          vim.notify("Pulling " .. describe_targets(items))
          run(dbuf, items, function(item, callback, on_error)
            cli.pull(dbuf.context, item.ref, callback, on_error)
          end)
        end,
      })
    end
  end

  if PLURALS[kind] then
    local verb = kind == "compose" and "Down" or "Remove"
    table.insert(operations, {
      title = verb,
      run = function()
        confirmed(dbuf, items, verb, function(item, callback, on_error)
          cli.remove(dbuf.context, item, callback, on_error)
        end)
      end,
    })
  end

  if #items > 1 then
    -- Name the targets of bulk operations
    for _, operation in ipairs(operations) do
      operation.title = string.format("%s %d %s", operation.title, #items, PLURALS[kind] or kind)
    end
  end
  return operations
end

---The items of the rows in [first, last] (0-indexed, inclusive).
---@param dbuf DockerBuffer
---@param first integer
---@param last integer
---@return DockerItem[]
function M.items_in_rows(dbuf, first, last)
  local items = {}
  local marks = vim.api.nvim_buf_get_extmarks(dbuf.buf_nr, constants.DOCKER_NAMESPACE, { first, 0 }, { last, -1 }, {})
  for _, mark in ipairs(marks) do
    local marked_line = dbuf.mark_mappings[mark[1]]
    if marked_line then
      table.insert(items, marked_line.item)
    end
  end
  return items
end

---Pick an operation for the items of the rows in [first, last] (0-indexed, inclusive) and run it.
---@param dbuf DockerBuffer
---@param first integer
---@param last integer
function M.select(dbuf, first, last)
  local operations = M.for_items(dbuf, M.items_in_rows(dbuf, first, last))
  if #operations == 0 then
    vim.notify("No operations", vim.log.levels.WARN)
    return
  end
  vim.ui.select(operations, {
    prompt = "Operation",
    format_item = function(operation)
      return operation.title
    end,
  }, function(operation)
    if operation then
      operation.run()
    end
  end)
end

return M
