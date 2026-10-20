local constants = require("docker.constants")
local t = require("helpers")

require("docker").setup({ refresh_interval = 200 })
require("docker.cli")

---@param name string
local function open(name)
  vim.cmd.edit(vim.fn.fnameescape(name))
  t.wait_loaded()
end

---@param name string
local function wait_buf_name(name)
  t.wait_for(function()
    return vim.api.nvim_buf_get_name(0) == name
  end, "buffer " .. name .. ", current: " .. vim.api.nvim_buf_get_name(0))
end

---@param pattern string
---@param count integer|nil
local function wait_call(pattern, count)
  t.wait_for(function()
    return #t.calls_matching(pattern) >= (count or 1)
  end, "docker call matching " .. pattern)
end

---Answer every prompt with its first item, returning the prompts and the items shown.
---@return {prompt: string, items: string[]}[]
local function prompts()
  local seen = {}
  t.answer_prompts(function(items, opts)
    table.insert(seen, { prompt = opts.prompt, items = vim.tbl_map(opts.format_item or tostring, items) })
    return items[1]
  end)
  return seen
end

local CONTAINERS = "docker://context/ctx-a/containers"

before_each(function()
  t.reset_docker()
  _G.docker.context = nil
  t.respond("context show", { stdout = "ctx-a\n" })
  t.respond("*ps --all*", { fixture = "containers.ndjson" })
  t.respond("*images --format*", { fixture = "images.ndjson" })
  t.respond("*history*", { fixture = "history.ndjson" })
  t.respond("*volume ls*", { fixture = "volumes.ndjson" })
  t.respond("*network ls*", { fixture = "networks.ndjson" })
  t.respond("*compose ls*", { fixture = "compose.json" })
  t.respond("*container inspect shop-web-1", { fixture = "inspect-web.json" })
  t.capture_notify()
end)

after_each(function()
  t.restore_stubs()
  t.clean_buffers()
end)

describe("lists", function()
  it("render the containers of the buffer's context, the header in the winbar", function()
    open(CONTAINERS)
    t.eq(4, #t.lines())
    t.ok(t.lines()[1]:find("^shop%-web%-1 +nginx:1%.27 +Up 2 hours"))
    t.ok(vim.wo.winbar:find("NAME +IMAGE +STATUS"))
    t.eq({ "--context ctx-a ps --all --format={{json .}}" }, t.calls())
  end)

  it("show unhealthy and failed containers as diagnostics", function()
    open(CONTAINERS)
    local diagnostics = vim.diagnostic.get(0, { namespace = constants.DOCKER_DIAGNOSTICS_NAMESPACE })
    t.eq(
      { { 1, "The container is unhealthy" }, { 2, "Exited with code 1" } },
      vim.tbl_map(function(d)
        return { d.lnum, d.message }
      end, diagnostics)
    )
  end)

  it("are pinned to the current context when opened without one", function()
    open("docker://containers")
    t.eq(CONTAINERS, vim.api.nvim_buf_get_name(0))
  end)

  it("filter by the params, project by the compose label", function()
    open(CONTAINERS .. "?project=shop")
    wait_call("label=com.docker.compose.project=shop")
  end)

  it("show the kinds for docker://, <CR> lists one", function()
    open("docker://")
    t.eq("docker://context/ctx-a/types", vim.api.nvim_buf_get_name(0))
    t.press_on("volumes", "<CR>")
    wait_buf_name("docker://context/ctx-a/volumes")
    t.wait_loaded()
    t.ok(t.lines()[1]:find("^shop_data"))
  end)

  it("show the error of docker", function()
    t.respond("*network ls*", { stderr = "Cannot connect to the Docker daemon", code = 1 })
    open("docker://context/ctx-a/networks")
    t.eq("✗ Cannot connect to the Docker daemon", t.status())
  end)

  it("keep the cursor on the same item when reloaded", function()
    open(CONTAINERS)
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    t.respond("*ps --all*", {
      stdout = table.concat(vim.list_slice(vim.split(t.fixture("containers.ndjson"), "\n"), 2), "\n"),
    })
    vim.api.nvim_feedkeys("R", "mx", false)
    t.wait_loaded()
    t.eq(3, #t.lines())
    t.ok(t.lines()[vim.api.nvim_win_get_cursor(0)[1]]:find("^migrate"))
  end)

  it("are reloaded periodically when watched", function()
    open(CONTAINERS)
    vim.api.nvim_feedkeys("gw", "mx", false)
    t.ok(vim.wo.winbar:find("⟳"))
    wait_call("ps %-%-all", 3)
    vim.api.nvim_feedkeys("gw", "mx", false)
  end)
end)

describe("navigation", function()
  it("<CR> on a container shows its logs, - goes back to the list", function()
    t.respond("*logs*", { stdout = "hello\nworld" })
    open(CONTAINERS)
    t.press_on("shop-web-1", "<CR>")
    wait_buf_name(CONTAINERS .. "/shop-web-1/logs")
    t.wait_loaded()
    t.eq({ "hello", "world" }, t.lines())
    t.eq({ "--context ctx-a logs --tail=1000 shop-web-1" }, t.calls_matching("logs"))
    vim.api.nvim_feedkeys("-", "mx", false)
    wait_buf_name(CONTAINERS)
  end)

  it("gL follows the logs, <C-c> stops", function()
    t.respond("*logs*", { script = "echo first; sleep 30" })
    open(CONTAINERS)
    t.press_on("shop-web-1", "gL")
    wait_buf_name(CONTAINERS .. "/shop-web-1/logs?follow=true")
    t.wait_for(function()
      return t.lines()[1] == "first"
    end, "the first line")
    local dbuf = _G.docker_buffers[vim.api.nvim_get_current_buf()]
    vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "mx", false)
    t.ok(vim.tbl_isempty(dbuf.jobs))
  end)

  it("gd inspects the item, read-only", function()
    open(CONTAINERS)
    t.press_on("shop-web-1", "gd")
    wait_buf_name(CONTAINERS .. "/shop-web-1")
    t.wait_loaded()
    t.eq("json", vim.bo.filetype)
    t.eq(false, vim.bo.modifiable)
    t.eq("[", t.lines()[1])
  end)

  it("<C-]> on IMAGE lists the image, <C-t> jumps back", function()
    open(CONTAINERS)
    t.press_on("nginx:1.27", "<C-]>")
    wait_buf_name("docker://context/ctx-a/images?reference=nginx:1.27")
    wait_call("images .*%-%-filter reference=nginx:1.27")
    vim.api.nvim_feedkeys(vim.keycode("<C-t>"), "mx", false)
    wait_buf_name(CONTAINERS)
  end)

  it("<CR> on a compose project lists its containers, - goes back to the projects", function()
    open("docker://context/ctx-a/compose")
    t.press_on("shop", "<CR>")
    wait_buf_name(CONTAINERS .. "?project=shop")
    vim.api.nvim_feedkeys("-", "mx", false)
    wait_buf_name("docker://context/ctx-a/compose")
  end)

  it("<CR> on an image shows its history", function()
    open("docker://context/ctx-a/images")
    t.press_on("latest", "<CR>")
    wait_buf_name("docker://context/ctx-a/images/1e5f3c5b981a/history")
    t.wait_loaded()
    t.eq(2, #t.lines())
  end)

  it("<CR> on a volume lists the containers using it", function()
    open("docker://context/ctx-a/volumes")
    t.press_on("shop_data", "<CR>")
    wait_buf_name(CONTAINERS .. "?volume=shop_data")
  end)
end)

describe(":w", function()
  it("removes the items of deleted lines after confirming", function()
    t.respond("*rm --force*", { stdout = "migrate" })
    local seen = prompts()
    open(CONTAINERS)
    t.press_on("migrate", "dd")
    vim.cmd("write")
    wait_call("rm %-%-force migrate")
    t.ok(seen[1].prompt:find("Remove container migrate", 1, true))
  end)

  it("untags images, removes untagged ones by ID, without confirming with :w!", function()
    t.respond("*rmi*", { stdout = "" })
    local seen = prompts()
    open("docker://context/ctx-a/images")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_feedkeys("2dd", "mx", false)
    vim.cmd("write!")
    wait_call("rmi", 2)
    -- In parallel
    local calls = t.calls_matching("rmi")
    table.sort(calls)
    t.eq({ "--context ctx-a rmi 9f8e7d6c5b4a", "--context ctx-a rmi nginx:latest" }, calls)
    t.eq({}, seen)
  end)

  it("takes compose projects down", function()
    t.respond("*down*", { stdout = "" })
    prompts()
    open("docker://context/ctx-a/compose")
    t.press_on("tools", "dd")
    vim.cmd("write")
    wait_call("compose %-%-project%-name tools down")
  end)

  it("refuses cell edits", function()
    local messages = t.capture_notify()
    open(CONTAINERS)
    t.press_on("migrate", "ciwrenamed<Esc>")
    vim.cmd("write")
    t.eq("NAME of container migrate is not editable", messages[1].msg)
    t.eq(1, #t.calls())
  end)

  it("does nothing when declined", function()
    t.answer_prompts(function()
      return "No"
    end)
    open(CONTAINERS)
    t.press_on("backup", "dd")
    vim.cmd("write")
    vim.wait(100)
    t.eq({}, t.calls_matching("rm "))
    t.eq(true, vim.bo.modified)
  end)
end)

describe("operations", function()
  it("gra offers the operations of the item, confirming the disruptive ones", function()
    t.respond("*stop*", { stdout = "shop-web-1" })
    local seen = {}
    t.answer_prompts(function(items, opts)
      local titles = vim.tbl_map(opts.format_item or tostring, items)
      table.insert(seen, { prompt = opts.prompt, items = titles })
      return items[vim.fn.index(titles, "Stop") + 1] or items[1]
    end)
    open(CONTAINERS)
    t.press_on("shop-web-1", "gra")
    wait_call("stop shop%-web%-1")
    t.eq(
      { "Logs", "Follow logs", "Exec", "Start", "Stop", "Restart", "Pause", "Unpause", "Kill", "Remove" },
      seen[1].items
    )
    t.eq("Stop container shop-web-1 (context: ctx-a)?", seen[2].prompt)
  end)

  it("gra on a visual selection runs the operation on every item", function()
    t.respond("*start*", { stdout = "" })
    local seen = {}
    t.answer_prompts(function(items, opts)
      table.insert(seen, vim.tbl_map(opts.format_item, items))
      return items[1]
    end)
    open(CONTAINERS)
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.api.nvim_feedkeys("Vjgra", "mx", false)
    wait_call("start", 2)
    local calls = t.calls_matching(" start ")
    table.sort(calls)
    t.eq({ "--context ctx-a start backup", "--context ctx-a start migrate" }, calls)
    t.eq("Start 2 containers", seen[1][1])
  end)
end)
