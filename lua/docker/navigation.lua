local constants = require("docker.constants")
local utils = require("docker.utils")

local M = {}

---The buffer one level up: subresource / resource -> its list -> the unfiltered list -> the kinds.
---@param dbuf DockerBuffer
---@return string|nil
function M.parent_name(dbuf)
  if dbuf.name then
    return utils.buf_name({ context = dbuf.context, kind = dbuf.kind })
  end
  if dbuf.params then
    -- The containers of a compose project come from the projects
    local kind = dbuf.kind == "containers" and dbuf.params.project and "compose" or dbuf.kind
    return utils.buf_name({ context = dbuf.context, kind = kind })
  end
  if dbuf.kind ~= "types" then
    return utils.buf_name({ context = dbuf.context, kind = "types" })
  end
  return nil
end

---The cell at `pos`, or just the row's item between cells.
---@param dbuf DockerBuffer
---@param pos integer[] (0,0)-indexed position
---@return {item: DockerItem, column: string|nil}|nil
local function cell_at(dbuf, pos)
  local marks =
    vim.api.nvim_buf_get_extmarks(dbuf.buf_nr, constants.DOCKER_COLUMN_NAMESPACE, pos, pos, { overlap = true })
  for _, mark in ipairs(marks) do
    local column = dbuf.mark_columns[mark[1]]
    if column then
      return column
    end
  end

  local row_marks = vim.api.nvim_buf_get_extmarks(
    dbuf.buf_nr,
    constants.DOCKER_NAMESPACE,
    { pos[1], 0 },
    { pos[1], -1 },
    {}
  )
  local marked_line = row_marks[1] and dbuf.mark_mappings[row_marks[1][1]]
  return marked_line and { item = marked_line.item }
end

---The buffer the cell at `pos` refers to, like a tag: a container's IMAGE -> the image, its
---PROJECT -> the containers of the project, a compose project -> its containers, a kind -> its
---list, anything else -> its `docker inspect`.
---@param dbuf DockerBuffer
---@param pos integer[] (0,0)-indexed position
---@return string|nil
function M.tag_target(dbuf, pos)
  local cell = cell_at(dbuf, pos)
  local item = cell and cell.item
  if not item then
    return nil
  end
  local context = dbuf.context
  if item.kind == "type" then
    return utils.buf_name({ context = context, kind = item.name })
  end
  if item.kind == "container" and cell.column == "IMAGE" then
    return utils.buf_name({ context = context, kind = "images", params = { reference = item.Image } })
  end
  if item.kind == "container" and cell.column == "PROJECT" and cell.text ~= "" then
    return utils.buf_name({ context = context, kind = "containers", params = { project = cell.text } })
  end
  if item.kind == "compose" then
    return utils.buf_name({ context = context, kind = "containers", params = { project = item.name } })
  end
  local kind = ({ container = "containers", image = "images", volume = "volumes", network = "networks" })[item.kind]
  return kind and utils.buf_name({ context = context, kind = kind, name = item.name })
end

---'tagfunc' for docker buffers, so <C-]>, <C-w>], <C-t> and the tag stack work as usual.
---@param pattern string
---@param flags string
---@return table[]|vim.NIL
function M.tagfunc(pattern, flags)
  local dbuf = _G.docker_buffers[vim.api.nvim_get_current_buf()]
  -- Only jumps from the cursor are resolved here, `:tag {name}` uses the tags files
  if not dbuf or not flags:find("c", 1, true) then
    return vim.NIL
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local target = M.tag_target(dbuf, { cursor[1] - 1, cursor[2] })
  if not target then
    return {}
  end
  return { { name = pattern, filename = target, cmd = "1" } }
end

return M
