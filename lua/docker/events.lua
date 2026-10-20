local cli = require("docker.cli")
local constants = require("docker.constants")
local log = require("docker.log")

local M = {}

---@param buffer DockerBuffer
---@param row_mark integer
---@return boolean Whether the row was deleted
local function deleted(buffer, row_mark)
  local mark =
    vim.api.nvim_buf_get_extmark_by_id(buffer.buf_nr, constants.DOCKER_NAMESPACE, row_mark, { details = true })
  return #mark == 3 and mark[3] and mark[3].invalid == true
end

---The errors of the edited cells, none can be edited.
---@param buffer DockerBuffer
---@return string[]
local function cell_edit_errors(buffer)
  local errors = {}
  -- Marks are created in the order of the cells
  local ids = vim.tbl_keys(buffer.mark_columns)
  table.sort(ids)
  for _, id in ipairs(ids) do
    local cell = buffer.mark_columns[id]
    if cell.row_mark and not deleted(buffer, cell.row_mark) then
      local mark =
        vim.api.nvim_buf_get_extmark_by_id(buffer.buf_nr, constants.DOCKER_COLUMN_NAMESPACE, id, { details = true })
      local text = vim.trim(
        table.concat(vim.api.nvim_buf_get_text(buffer.buf_nr, mark[1], mark[2], mark[3].end_row, mark[3].end_col, {}))
      )
      if text ~= cell.text then
        table.insert(errors, string.format("%s of %s %s is not editable", cell.column, cell.item.kind, cell.item.name))
      end
    end
  end
  return errors
end

---Remove the items, after confirming unless `force`.
---@param buffer DockerBuffer
---@param items DockerItem[]
---@param force boolean|nil
---@param callback fun(saved: boolean)
local function remove(buffer, items, force, callback)
  local function title(item)
    return string.format("%s %s %s", item.kind == "compose" and "Down" or "Remove", item.kind, item.ref or item.name)
  end

  local function run()
    local remaining = #items
    -- Reload once all are done, failed or not, to show what docker has now
    local function finished()
      remaining = remaining - 1
      if remaining == 0 then
        callback(true)
      end
    end
    for _, item in ipairs(items) do
      cli.remove(buffer.context, item, function(result)
        if result and vim.trim(result) ~= "" then
          vim.notify(vim.trim(result))
        end
        finished()
      end, function(err)
        vim.notify(string.format("Failed: %s\n%s", title(item), err), vim.log.levels.ERROR)
        finished()
      end)
    end
  end

  if force then
    run()
    return
  end
  local titles = vim.tbl_map(function(item)
    return "  " .. title(item)
  end, items)
  local prompt = string.format("Apply the changes (context: %s)?\n%s", buffer.context, table.concat(titles, "\n"))
  vim.schedule(function()
    require("docker.confirm")(prompt, function(confirmed)
      if confirmed then
        run()
      else
        callback(false)
      end
    end)
  end)
end

---Remove the items of the deleted rows.
---@param buffer DockerBuffer
---@param callback fun(saved: boolean)|nil `saved` tells whether the buffer should be reloaded
---@param opts {force: boolean|nil}|nil `force` (:w!) skips the confirmation
function M.on_buf_saved(buffer, callback, opts)
  callback = callback or function(_) end
  opts = opts or {}

  local errors = cell_edit_errors(buffer)
  if #errors > 0 then
    vim.notify(table.concat(errors, "\n"), vim.log.levels.ERROR)
    callback(false)
    return
  end

  local items = {}
  -- In the order of the rows
  local mark_ids = vim.tbl_keys(buffer.mark_mappings)
  table.sort(mark_ids)
  for _, mark_id in ipairs(mark_ids) do
    local item = buffer.mark_mappings[mark_id].item
    -- Kinds and image layers cannot be removed
    if deleted(buffer, mark_id) and item.kind ~= "type" and item.kind ~= "layer" then
      table.insert(items, item)
    end
  end
  log.debug("items to remove", #items)

  if #items == 0 then
    callback(true)
    return
  end
  remove(buffer, items, opts.force, callback)
end

return M
