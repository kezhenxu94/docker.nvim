local buffer = require("docker.buffer")
local t = require("helpers")
local utils = require("docker.utils")

require("docker").setup({})
require("docker.cli")

describe("parse_name", function()
  it("parses the context, kind, name, subresource and params", function()
    t.eq({
      context = "ctx/a:b",
      kind = "containers",
      name = "web",
      subresource = "logs",
      params = { follow = true, tail = "10" },
    }, buffer.parse_name("docker://context/ctx%2Fa%3Ab/containers/web/logs?follow&tail=10"))
  end)

  it("requires a context", function()
    t.ok(not pcall(buffer.parse_name, "docker://containers"))
  end)
end)

describe("buf_name", function()
  it("round trips with parse_name", function()
    local name = utils.buf_name({
      context = "ctx/a",
      kind = "containers",
      params = { project = "shop", status = "running" },
    })
    t.eq("docker://context/ctx%2fa/containers?project=shop&status=running", name)
    t.eq({
      context = "ctx/a",
      kind = "containers",
      params = { project = "shop", status = "running" },
    }, buffer.parse_name(name))
  end)
end)

describe("canonical_name", function()
  local autocmds = require("docker.autocmds")

  before_each(function()
    t.reset_docker()
    _G.docker.context = nil
    t.respond("context show", { stdout = "ctx-a\n" })
  end)

  it("pins names without a context to the current one", function()
    t.eq(
      "docker://context/ctx-a/containers?status=running",
      autocmds.canonical_name("docker://containers?status=running")
    )
  end)

  it("uses the context switched to with :Docker context", function()
    _G.docker.context = "remote"
    t.eq("docker://context/remote/images", autocmds.canonical_name("docker://images"))
  end)

  it("lists the kinds without a kind", function()
    t.eq("docker://context/ctx-a/types", autocmds.canonical_name("docker://"))
    t.eq("docker://context/ctx-a/types", autocmds.canonical_name("docker://context/ctx-a"))
  end)

  it("keeps canonical names", function()
    t.eq("docker://context/ctx-a/volumes", autocmds.canonical_name("docker://context/ctx-a/volumes"))
  end)
end)
