local DockerBuffer = require("docker.buffer").DockerBuffer
local log = require("docker.log")
local utils = require("docker.utils")
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local M = {}

M.augroup = augroup("docker_autocmds", { clear = true })

---The name of the buffer a name is an alias of, itself if none:
---without `context/<context>/` it is pinned to the current context, so the buffer keeps operating
---on the same daemon after the context is switched; no kind is the kinds, `types`.
---@param buf_name string
---@return string|nil name
---@return string|nil err
function M.canonical_name(buf_name)
  local rest = buf_name:sub(#"docker://" + 1):gsub("^/+", "")
  local context = rest:match("^context/[^/?]*/?")
  if context then
    rest = rest:sub(#context + 1)
    if not vim.endswith(context, "/") then
      context = context .. "/"
    end
  else
    local current = require("docker.cli").get_current_context()
    if not current then
      return nil, "No current docker context"
    end
    context = string.format("context/%s/", vim.uri_encode(current, "rfc2396"))
  end
  if rest == "" then
    rest = "types"
  end
  return "docker://" .. context .. rest
end

function M.setup()
  autocmd("BufReadCmd", {
    group = M.augroup,
    pattern = "docker://*",
    -- So that the BufReadCmd of the buffer an alias redirects to runs
    nested = true,
    callback = function(ev)
      local buf_nr = ev.buf
      local buf_name = vim.api.nvim_buf_get_name(buf_nr)
      log.debug("loading buffer", buf_name)

      local name, err = M.canonical_name(buf_name)
      if not name then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
      -- The name is an alias: edit the canonical buffer instead, the alias is wiped, it never
      -- becomes the alternate file or a jump.
      if name ~= buf_name then
        local canonical = vim.fn.bufadd(name)
        vim.bo[canonical].buflisted = true
        vim.cmd.buffer({ canonical, mods = { keepalt = true, keepjumps = true } })
        vim.schedule(function()
          pcall(vim.api.nvim_buf_delete, buf_nr, { force = true })
        end)
        return
      end

      local ok, parts = pcall(require("docker.buffer").parse_name, name)
      if not ok then
        vim.notify(parts, vim.log.levels.ERROR)
        return
      end
      if parts.subresource == "exec" then
        require("docker.utils.exec").start(name, parts)
        return
      end
      DockerBuffer:new(buf_nr):load()
    end,
  })

  -- An unloaded buffer (`:bunload`, leaving it with 'nohidden', `:e`) keeps its state, e.g. watching,
  -- for when it is loaded again, a deleted one (`:bdelete`, `:bwipeout`) starts over.
  autocmd("BufUnload", {
    group = M.augroup,
    pattern = "docker://*",
    callback = function(ev)
      local buffer = _G.docker_buffers[ev.buf]
      if buffer then
        buffer:stop_jobs()
      end
    end,
  })

  autocmd({ "BufDelete", "BufWipeout" }, {
    group = M.augroup,
    pattern = "docker://*",
    callback = function(ev)
      log.debug("deleting buffer", vim.api.nvim_buf_get_name(ev.buf), ev.buf)
      local buffer = _G.docker_buffers[ev.buf]
      if buffer then
        buffer:stop_jobs()
        _G.docker_buffers[ev.buf] = nil
      end
    end,
  })

  autocmd("BufWriteCmd", {
    group = M.augroup,
    pattern = "docker://*",
    callback = function(ev)
      local buffer = _G.docker_buffers[ev.buf]
      if not buffer then
        log.error("buffer not found", ev.buf)
        return
      end

      require("docker.events").on_buf_saved(buffer, function(saved)
        if saved then
          vim.schedule(function()
            buffer:load()
          end)
        end
      end, { force = vim.v.cmdbang == 1 })
    end,
  })

  autocmd({ "TextChanged", "TextChangedI" }, {
    group = M.augroup,
    pattern = "docker://*",
    callback = function(ev)
      local buffer = _G.docker_buffers[ev.buf]
      if buffer and not vim.tbl_isempty(buffer.mark_mappings) then
        require("docker.renderers.resources").show_pending(buffer)
      end
    end,
  })

  autocmd("BufWinEnter", {
    group = M.augroup,
    pattern = "docker://*",
    callback = function(ev)
      local buffer = _G.docker_buffers[ev.buf]
      -- Wrapped rows break the table layout and its alignment with the winbar header
      if buffer and require("docker.refresh").is_table(buffer) then
        vim.wo[0][0].wrap = false
      end
    end,
  })

  autocmd({ "WinScrolled", "WinResized" }, {
    group = M.augroup,
    callback = function()
      local buffer = _G.docker_buffers[vim.api.nvim_get_current_buf()]
      if buffer then
        utils.update_winbar(buffer)
      end
    end,
  })

  autocmd("ColorScheme", {
    group = M.augroup,
    callback = function()
      require("docker.highlights").setup()
    end,
  })
end

return M
