local cli = require("docker.cli")
local t = require("helpers")

require("docker").setup({})

---Run `fn(done)` and wait for it to call `done`.
---@param fn fun(done: fun(...))
---@return any ... The arguments of `done`
local function await(fn)
  local result
  fn(function(...)
    result = { ... }
  end)
  t.wait_for(function()
    return result
  end, "callback")
  return unpack(result)
end

before_each(function()
  t.reset_docker()
end)

describe("decode", function()
  it("decodes JSON lines and JSON arrays", function()
    t.eq({ { Name = "a" }, { Name = "b" } }, cli.decode('{"Name":"a"}\n{"Name":"b"}\n'))
    t.eq({ { Name = "a" } }, cli.decode('[{"Name":"a"}]\n'))
    t.eq({}, cli.decode(""))
  end)
end)

describe("list", function()
  it("passes the context and the filters, project as the compose label", function()
    t.respond("*", { stdout = "" })
    await(function(done)
      cli.list("ctx-a", "containers", { project = "shop", status = "running" }, done)
    end)
    t.eq({
      "--context ctx-a ps --all --format={{json .}} --filter label=com.docker.compose.project=shop --filter status=running",
    }, t.calls())
  end)

  it("reports errors", function()
    t.respond("*", { stderr = "Cannot connect to the Docker daemon", code = 1 })
    local err = await(function(done)
      cli.list("ctx-a", "images", nil, nil, done)
    end)
    t.eq("Cannot connect to the Docker daemon", err)
  end)
end)

describe("logs", function()
  it("merges stdout and stderr", function()
    t.respond("*logs*", { script = "echo out; echo err >&2" })
    local logs = await(function(done)
      cli.logs("ctx-a", "containers", "web", { since = "1h" }, done)
    end)
    t.eq("out\nerr", logs)
    t.eq({ "--context ctx-a logs --tail=1000 --since=1h web" }, t.calls())
  end)

  it("of compose projects", function()
    t.respond("*", { stdout = "web-1  | hello" })
    await(function(done)
      cli.logs("ctx-a", "compose", "shop", { tail = 5 }, done)
    end)
    t.eq({ "--context ctx-a compose --project-name shop logs --no-color --tail=5" }, t.calls())
  end)
end)

describe("remove", function()
  it("uses the command of the kind", function()
    t.respond("*", { stdout = "" })
    for _, item in ipairs({
      { kind = "container", name = "web" },
      { kind = "image", name = "1e5f", ref = "nginx:latest" },
      { kind = "volume", name = "data" },
      { kind = "network", name = "net" },
      { kind = "compose", name = "shop" },
    }) do
      await(function(done)
        cli.remove("ctx-a", item, done)
      end)
    end
    t.eq({
      "--context ctx-a rm --force web",
      "--context ctx-a rmi nginx:latest",
      "--context ctx-a volume rm data",
      "--context ctx-a network rm net",
      "--context ctx-a compose --project-name shop down",
    }, t.calls())
  end)
end)

describe("contexts", function()
  it("uses the context switched to, docker's current one otherwise", function()
    t.respond("context show", { stdout = "default\n" })
    _G.docker.context = nil
    t.eq("default", cli.get_current_context())
    cli.use_context("remote")
    t.eq("remote", cli.get_current_context())
    t.eq(
      { context = "remote" },
      vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("state") .. "/docker_state.json")))
    )
  end)
end)
