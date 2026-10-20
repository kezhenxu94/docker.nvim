local commands = require("docker.commands")
local t = require("helpers")

require("docker").setup({})

describe(":Docker argument parsing", function()
  it("parses get with filters whose values contain =", function()
    t.eq(
      { "containers", { label = "app=web", status = "running" } },
      commands.command_handlers.get.parse({ "containers", "label=app=web", "status=running" })
    )
    t.eq({ "images" }, commands.command_handlers.get.parse({ "images" }))
  end)

  it("parses context", function()
    t.eq({ "remote" }, commands.command_handlers.context.parse({ "remote" }))
  end)

  it("completes the kinds", function()
    t.eq({ "compose", "containers" }, commands.command_handlers.get.complete("co", { "co" }))
  end)
end)

describe(":Docker", function()
  before_each(function()
    t.reset_docker()
    _G.docker.context = nil
    t.respond("context show", { stdout = "default\n" })
    t.respond("*ps --all*", { fixture = "containers.ndjson" })
  end)
  after_each(function()
    t.restore_stubs()
    t.clean_buffers()
  end)

  it("reports unknown subcommands", function()
    local messages = t.capture_notify()
    vim.cmd("Docker nope")
    t.eq({ { msg = "No such command: nope", level = vim.log.levels.ERROR } }, messages)
  end)

  it("get opens the list with the filters", function()
    vim.cmd("Docker get containers status=running")
    t.wait_loaded()
    t.eq("docker://context/default/containers?status=running", vim.api.nvim_buf_get_name(0))
    t.eq(4, #t.lines())
  end)

  it("context switches the context used for new buffers", function()
    local messages = t.capture_notify()
    vim.cmd("Docker context remote")
    t.eq("remote", require("docker.cli").get_current_context())
    t.eq("Switched to context: remote", messages[1].msg)
  end)

  it("context without a name prompts with the current one marked", function()
    t.respond("context ls*", { fixture = "contexts.ndjson" })
    local shown
    t.answer_prompts(function(items, opts)
      shown = vim.tbl_map(opts.format_item, items)
      return items[2]
    end)
    t.capture_notify()
    vim.cmd("Docker context")
    t.wait_for(function()
      return _G.docker.context == "remote"
    end, "context switch")
    t.eq({ "* default", "  remote" }, shown)
  end)
end)
