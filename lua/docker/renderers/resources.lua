local constants = require("docker.constants")
local formatters = require("docker.formatters")
local log = require("docker.log")
local utils = require("docker.utils")

local M = {}

local MAX_COLUMN_WIDTH = 99
local COLUMN_SEPARATOR = "  "

---Identity of a row's item that survives reloads, so the cursor can stay on the same row.
---@param item DockerItem|nil
---@return string|nil
local function row_identity(item)
  if type(item) ~= "table" then
    return nil
  end
  -- An image with several tags has a row per tag
  return string.format("%s/%s", item.kind, item.ref or item.name)
end

---Remember the row under the cursor of every window showing the buffer.
---@param buffer DockerBuffer
---@return {win: integer, identity: string|nil, cursor: integer[]}[]
local function save_cursors(buffer)
  local saved = {}
  for _, win in ipairs(vim.fn.win_findbuf(buffer.buf_nr)) do
    local cursor = vim.api.nvim_win_get_cursor(win)
    local marks = vim.api.nvim_buf_get_extmarks(
      buffer.buf_nr,
      constants.DOCKER_NAMESPACE,
      { cursor[1] - 1, 0 },
      { cursor[1] - 1, -1 },
      {}
    )
    local marked_line = marks[1] and buffer.mark_mappings[marks[1][1]]
    table.insert(saved, { win = win, identity = marked_line and row_identity(marked_line.item), cursor = cursor })
  end
  return saved
end

---Move the cursors back to the rows of the same items, or keep the line when the item is gone.
---@param saved {win: integer, identity: string|nil, cursor: integer[]}[]
---@param formatted_rows FormattedTableRow[]
local function restore_cursors(saved, formatted_rows)
  for _, entry in ipairs(saved) do
    if vim.api.nvim_win_is_valid(entry.win) then
      local line = math.min(entry.cursor[1], math.max(#formatted_rows, 1))
      for row_num, row in ipairs(formatted_rows) do
        if entry.identity and row_identity(row.raw) == entry.identity then
          line = row_num
          break
        end
      end
      pcall(vim.api.nvim_win_set_cursor, entry.win, { line, entry.cursor[2] })
    end
  end
end

-- Columns that change on every reload, not worth showing as a change
local VOLATILE_COLUMNS = { CREATED = true }
local FLASH_DURATION = 1500

---@param headers string[]
---@param cells string[]
---@return string
local function row_signature(headers, cells)
  local values = {}
  for i, header in ipairs(headers) do
    if not VOLATILE_COLUMNS[header] then
      table.insert(values, cells[i] or "")
    end
  end
  return table.concat(values, "\0")
end

---The signatures of the rendered rows by identity, nil before the first render.
---@param buffer DockerBuffer
---@return table<string, string>|nil
local function signatures(buffer)
  if vim.tbl_isempty(buffer.mark_mappings) then
    return nil
  end
  local result = {}
  for _, marked_line in pairs(buffer.mark_mappings) do
    local identity = row_identity(marked_line.item)
    if identity then
      result[identity] = marked_line.signature
    end
  end
  return result
end

---Highlight the rows for a moment.
---@param buffer DockerBuffer
---@param rows integer[] 0-indexed
local function flash(buffer, rows)
  for _, row in ipairs(rows) do
    vim.api.nvim_buf_set_extmark(buffer.buf_nr, constants.DOCKER_CHANGED_NAMESPACE, row, 0, {
      line_hl_group = "DockerChanged",
      priority = vim.hl.priorities.user,
    })
  end
  if #rows == 0 then
    return
  end
  local generation = (buffer.flash_generation or 0) + 1
  buffer.flash_generation = generation
  vim.defer_fn(function()
    -- A later reload flashes its own rows
    if buffer.flash_generation == generation and vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
      vim.api.nvim_buf_clear_namespace(buffer.buf_nr, constants.DOCKER_CHANGED_NAMESPACE, 0, -1)
    end
  end, FLASH_DURATION)
end

---@param buffer DockerBuffer The buffer to render into
---@return Formatter|nil
function M.formatter_for(buffer)
  return formatters[buffer.subresource or buffer.kind]
end

---@param buffer DockerBuffer The buffer to render into
---@return vim.SystemObj|nil
function M.load(buffer)
  log.debug("loading buffer", buffer.kind, buffer.name, buffer.subresource, buffer.params)

  local formatter = M.formatter_for(buffer)
  if not formatter then
    buffer:on_error()("Unknown kind: " .. (buffer.subresource or buffer.kind))
    return nil
  end
  if buffer.kind == "types" then
    M.render(buffer, formatter, {})
    return nil
  end

  local cli = require("docker.cli")
  local function on_result(result)
    -- The jobs of an unloaded buffer are killed, ending without output
    if result and vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
      M.render(buffer, formatter, cli.decode(result))
    end
  end

  local job
  if buffer.subresource == "history" then
    job = cli.history(buffer.context, buffer.name, on_result, buffer:on_error())
  else
    job = cli.list(buffer.context, buffer.kind, buffer.params, on_result, buffer:on_error())
  end
  if job then
    buffer.jobs[job.pid] = job
  end
  return job
end

---Render the rows of `data` as a table, keeping the cursors on the same rows.
---@param buffer DockerBuffer The buffer to render into
---@param formatter Formatter
---@param data table[] The decoded docker output
function M.render(buffer, formatter, data)
  local self = buffer
  -- Edits made while a background reload was running win over the reload
  if self.silent and vim.bo[self.buf_nr].modified then
    return
  end
  local headers = formatter.headers
  local cursors = save_cursors(self)
  local previous = signatures(self)

  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.DOCKER_NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.DOCKER_COLUMN_NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.DOCKER_PENDING_NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.DOCKER_CHANGED_NAMESPACE, 0, -1)
  vim.diagnostic.reset(constants.DOCKER_DIAGNOSTICS_NAMESPACE, self.buf_nr)
  self.mark_mappings = {}
  self.mark_columns = {}

  local rows = formatter.format(data, self)

  local header_row, formatted_rows = M.format_table(headers, rows)
  self.header_row = header_row

  local lines = {}
  for _, row in ipairs(formatted_rows) do
    table.insert(lines, row.formatted)
  end
  self:set_lines(lines, true)
  restore_cursors(cursors, formatted_rows)
  if #lines == 0 then
    self:set_status(formatter.empty or "Nothing found", "Comment")
  end

  local diagnostics = {}
  local changed = {}
  for row_num, row in ipairs(formatted_rows) do
    local row_mark = vim.api.nvim_buf_set_extmark(self.buf_nr, constants.DOCKER_NAMESPACE, row_num - 1, 0, {
      invalidate = true,
      line_hl_group = "DockerBody",
    })
    local signature = row_signature(headers, row.cells)
    self.mark_mappings[row_mark] = {
      item = row.raw,
      line = row.formatted,
      signature = signature,
    }
    local identity = row_identity(row.raw)
    if previous and identity and previous[identity] ~= signature then
      table.insert(changed, row_num - 1)
    end

    for i, range in ipairs(row.ranges) do
      -- Text typed at either end of the cell, as by `ciw`, stays in the cell
      local mark_id =
        vim.api.nvim_buf_set_extmark(self.buf_nr, constants.DOCKER_COLUMN_NAMESPACE, row_num - 1, range[1], {
          end_col = range[2],
          right_gravity = false,
          end_right_gravity = true,
          hl_group = row.highlights and row.highlights[headers[i]] or nil,
        })
      self.mark_columns[mark_id] = {
        item = row.raw,
        column = headers[i],
        text = vim.trim(row.formatted:sub(range[1] + 1, range[2])),
        row_mark = row_mark,
      }
    end

    for _, diagnostic in ipairs(row.diagnostics or {}) do
      table.insert(diagnostics, {
        bufnr = self.buf_nr,
        lnum = row_num - 1,
        col = 0,
        message = diagnostic.message,
        severity = diagnostic.severity,
      })
    end
  end

  if #diagnostics > 0 then
    vim.diagnostic.set(constants.DOCKER_DIAGNOSTICS_NAMESPACE, self.buf_nr, diagnostics, {})
  end
  -- After the diagnostics, whose signs may change the width of the sign column the header is aligned with
  utils.update_winbar(self)
  -- Only reloads of a watched list: a reload asked for shows the changes it was asked for
  if self.silent then
    flash(self, changed)
  end
end

---Show the rows deleted from the buffer, which `:w` deletes, where they were.
---@param buffer DockerBuffer
function M.show_pending(buffer)
  local buf = buffer.buf_nr
  vim.api.nvim_buf_clear_namespace(buf, constants.DOCKER_PENDING_NAMESPACE, 0, -1)

  -- Marks are created in the order of the rows
  local ids = vim.tbl_keys(buffer.mark_mappings)
  table.sort(ids)
  local deleted = {}
  for _, id in ipairs(ids) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(buf, constants.DOCKER_NAMESPACE, id, { details = true })
    if mark[3] and mark[3].invalid then
      deleted[mark[1]] = deleted[mark[1]] or {}
      table.insert(deleted[mark[1]], { { buffer.mark_mappings[id].line, "DockerDeleted" } })
    end
  end

  local last = vim.api.nvim_buf_line_count(buf) - 1
  for row, virt_lines in pairs(deleted) do
    vim.api.nvim_buf_set_extmark(buf, constants.DOCKER_PENDING_NAMESPACE, math.min(row, last), 0, {
      virt_lines = virt_lines,
      -- Rows deleted at the end go below the last line
      virt_lines_above = row <= last,
    })
  end

  -- Lines above the first line are only shown as filler of the top line
  if deleted[0] then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.api.nvim_win_call(win, function()
        if vim.fn.line("w0") == 1 then
          vim.fn.winrestview({ topfill = #deleted[0] })
        end
      end)
    end
  end
end

---@param text string
---@return integer The display width
local function display_width(text)
  -- Most cells are ASCII, where the width is the length
  if not text:find("[\128-\255]") then
    return #text
  end
  return vim.api.nvim_strwidth(text)
end

---@param text string
---@param width integer
---@return string `text` cut to `width` display cells, ending with "..."
local function truncate(text, width)
  if not text:find("[\128-\255]") then
    return text:sub(1, width - 3) .. "..."
  end
  local chars, used = {}, 0
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    used = used + vim.api.nvim_strwidth(char)
    if used > width - 3 then
      break
    end
    table.insert(chars, char)
  end
  return table.concat(chars) .. "..."
end

---@class FormattedTableRow
---@field formatted string The formatted line with proper column spacing
---@field cells string[] The values of the columns
---@field ranges integer[][] The 0-indexed byte range [start, end) of each column in `formatted`
---@field highlights table<string, string>|nil Highlight groups of cells, by header
---@field highlight string|nil The highlight group of the header row
---@field raw table The original row data
---@field diagnostics vim.Diagnostic[]|nil List of diagnostics for the row

---@param headers string[] List of column headers
---@param rows FormattedRow[] List of row data
---@return FormattedTableRow The formatted header row
---@return FormattedTableRow[] List of objects containing formatted line, highlight, and raw data
---@return number[] List of column widths
function M.format_table(headers, rows)
  local col_widths = {}
  for i, header in ipairs(headers) do
    col_widths[i] = #header
    for _, row in ipairs(rows) do
      col_widths[i] = math.max(col_widths[i], display_width(row.row[i] or ""))
    end
  end

  local formatted_rows = {}

  for _, row in ipairs(rows) do
    local formatted, ranges = M.align_row(row.row, col_widths)
    table.insert(formatted_rows, {
      formatted = formatted,
      ranges = ranges,
      cells = row.row,
      highlights = row.highlights,
      diagnostics = row.diagnostics,
      raw = row.item,
    })
  end

  return {
    formatted = M.align_row(headers, col_widths),
    highlight = "DockerHeader",
    raw = headers,
  },
    formatted_rows,
    col_widths
end

---@param row string[] The values of the columns
---@param col_widths number[] List of column widths
---@return string Formatted row string
---@return integer[][] The 0-indexed byte range [start, end) of each column
function M.align_row(row, col_widths)
  local formatted_cols, ranges = {}, {}
  local pos = 0
  for i, col_width in ipairs(col_widths) do
    local width = math.min(MAX_COLUMN_WIDTH, col_width)
    local col_str = row[i] or ""
    local col_display_width = display_width(col_str)
    if col_display_width > width then
      col_str = truncate(col_str, width)
      col_display_width = display_width(col_str)
    end
    col_str = col_str .. string.rep(" ", width - col_display_width)
    table.insert(formatted_cols, col_str)
    table.insert(ranges, { pos, pos + #col_str })
    pos = pos + #col_str + #COLUMN_SEPARATOR
  end
  return table.concat(formatted_cols, COLUMN_SEPARATOR), ranges
end

return M
