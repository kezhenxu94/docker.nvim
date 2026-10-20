local constants = require("docker.constants")
local log = require("docker.log")
local M = {}

---@type table<number, DockerBuffer>
_G.docker_buffers = {}

---@class MarkedLine
---@field item DockerItem The item of the row
---@field line string The rendered line
---@field signature string The values of the row that a reload can change

---@class MarkedColumn
---@field item DockerItem The item of the row
---@field column string The column name of the marked column
---@field text string The rendered value, to tell edits
---@field row_mark integer|nil The mark of the row in `mark_mappings`

---@class DockerBuffer
---@field buf_nr number The buffer number
---@field header_row FormattedTableRow The header row of the buffer
---@field mark_mappings table<number, MarkedLine> Mapping of mark IDs to row data
---@field mark_columns table<number, MarkedColumn> Mapping of mark IDs to column field
---@field context string The docker context the buffer is bound to
---@field kind string The kind of the buffer, e.g. `containers`
---@field name string|nil The name of the resource in the buffer
---@field subresource string|nil The subresource in the buffer, e.g. `logs`
---@field params table<string, any>|nil The parameters of the buffer, the filters of lists
---@field jobs table<number, vim.SystemObj> The jobs running in the buffer
---@field loading_job vim.SystemObj|nil The currently running loading job
---@field silent boolean|nil Whether the current load is a background refresh
---@field watch boolean|nil Whether the buffer reloads periodically, see `docker.refresh`
---@field flash_generation integer|nil The latest reload whose changed rows are highlighted
---@field loaded_callbacks fun(err: string|nil)[] Called once the current load is done, see `on_loaded`
local DockerBuffer = {}
DockerBuffer.__index = DockerBuffer

---@class DockerBufNameParts
---@field context string
---@field kind string
---@field name string|nil
---@field subresource string|nil
---@field params table<string, any>|nil

---Parse a buffer name, see `require("docker.utils").buf_name` for the format.
---@param buf_name string
---@return DockerBufNameParts
function M.parse_name(buf_name)
  local path, query = buf_name:match("^docker://([^?]*)%??(.*)$")
  local segments = vim.split(path or "", "/", { plain = true, trimempty = true })
  log.debug("path", path, "query", query, "segments", segments)

  if segments[1] ~= "context" or #segments < 3 then
    error("Invalid buffer name format. Expected: docker://context/{context}/{kind}[/{name}[/{subresource}]]")
  end

  local params
  if query and query ~= "" then
    params = {}
    for param_str in query:gmatch("[^&]+") do
      local key, value = param_str:match("([^=]+)=?(.*)")
      if value == "" or value == "true" then
        value = true
      elseif value == "false" then
        value = false
      end
      params[key] = value
    end
  end

  return {
    context = vim.uri_decode(segments[2]),
    kind = segments[3],
    name = segments[4],
    subresource = segments[5],
    params = params,
  }
end

---Create a new DockerBuffer instance
---@param buf_nr number The buffer number
---@return DockerBuffer
function DockerBuffer:new(buf_nr)
  buf_nr = buf_nr or vim.api.nvim_get_current_buf()

  if _G.docker_buffers[buf_nr] then
    return _G.docker_buffers[buf_nr]
  end

  local parsed = M.parse_name(vim.api.nvim_buf_get_name(buf_nr))
  local this = setmetatable({
    buf_nr = buf_nr,
    mark_mappings = {},
    mark_columns = {},
    context = parsed.context,
    kind = parsed.kind,
    name = parsed.name,
    subresource = parsed.subresource,
    params = parsed.params,
    jobs = {},
    loaded_callbacks = {},
  }, DockerBuffer)
  _G.docker_buffers[buf_nr] = this

  this:setup()

  require("docker.keymaps").setup_buffer_keymaps(buf_nr)

  return this
end

function DockerBuffer:setup()
  -- Only tables are written (`:w` deletes the deleted rows). Logs can be edited, e.g. reformatted,
  -- the edits never block quitting, `:w {file}` saves them.
  local buftype = require("docker.refresh").is_table(self) and "acwrite" or "nofile"
  vim.api.nvim_set_option_value("buftype", buftype, { buf = self.buf_nr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = self.buf_nr })
end

---@param opts {silent: boolean|nil}|nil `silent` for background refreshes: no loading status, no error notification
function DockerBuffer:load(opts)
  opts = opts or {}
  -- Operations reload their buffer when done, it may have been unloaded or deleted meanwhile
  if not vim.api.nvim_buf_is_loaded(self.buf_nr) or _G.docker_buffers[self.buf_nr] ~= self then
    return
  end
  if self.loading_job and not self.loading_job:is_closing() then
    if not opts.silent then
      vim.notify("The buffer is currently being loaded", vim.log.levels.WARN)
    end
    return
  end

  self.silent = opts.silent
  local empty = vim.api.nvim_buf_line_count(self.buf_nr) == 1
    and vim.api.nvim_buf_get_lines(self.buf_nr, 0, 1, false)[1] == ""
  if empty then
    self:set_status("Loading…", "Comment")
  end
  self.loading_job = require("docker.renderers").load(self)
end

---Kill the jobs loading the buffer, their output has nowhere to go once it is unloaded.
function DockerBuffer:stop_jobs()
  local cli = require("docker.cli")
  cli.kill(self.loading_job)
  self.loading_job = nil
  for pid, job in pairs(self.jobs) do
    cli.kill(job)
    self.jobs[pid] = nil
  end
end

---Show a status after the first line, nil to clear it.
---@param text string|nil
---@param hl string|nil
function DockerBuffer:set_status(text, hl)
  if not vim.api.nvim_buf_is_loaded(self.buf_nr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.DOCKER_STATUS_NAMESPACE, 0, -1)
  if text then
    vim.api.nvim_buf_set_extmark(self.buf_nr, constants.DOCKER_STATUS_NAMESPACE, 0, 0, {
      virt_text = { { text, hl } },
      virt_text_pos = "eol",
    })
  end
end

---Call `fn` once the buffer is loaded, after it is rendered, or with the error of the load.
---@param fn fun(err: string|nil)
function DockerBuffer:on_loaded(fn)
  table.insert(self.loaded_callbacks, fn)
end

---@param err string|nil
function DockerBuffer:notify_loaded(err)
  local callbacks = self.loaded_callbacks
  self.loaded_callbacks = {}
  -- Renderers set the lines, then the marks
  vim.schedule(function()
    for _, fn in ipairs(callbacks) do
      fn(err)
    end
  end)
end

---Error callback for docker calls loading this buffer.
---@return fun(err: string)
function DockerBuffer:on_error()
  return function(err)
    self:notify_loaded(err)
    local message = vim.split(err ~= "" and err or "docker failed", "\n")[1]
    self:set_status("✗ " .. message, "ErrorMsg")
    if not self.silent then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end
end

---Replace the buffer content with lines, keeping it unmodified.
---@param lines string[]
---@param modifiable boolean|nil
function DockerBuffer:set_lines(lines, modifiable)
  self:set_status(nil)
  vim.bo[self.buf_nr].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, lines)
  vim.bo[self.buf_nr].modifiable = modifiable == true
  vim.bo[self.buf_nr].modified = false
  self:notify_loaded(nil)
end

M.DockerBuffer = DockerBuffer

return M
