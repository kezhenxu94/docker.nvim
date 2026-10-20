local cli = require("docker.cli")
local formatters = require("docker.formatters")
local t = require("helpers")

---@param kind string
---@param fixture string
---@return FormattedRow[]
local function format(kind, fixture)
  return formatters[kind].format(cli.decode(t.fixture(fixture)))
end

describe("containers", function()
  local rows = format("containers", "containers.ndjson")

  it("formats the columns, with the compose project", function()
    t.eq(
      { "shop-web-1", "nginx:1.27", "Up 2 hours", "0.0.0.0:8080->80/tcp", "shop", "2 hours ago", "a1b2c3d4e5f6" },
      rows[1].row
    )
    t.eq("", rows[3].row[5])
    t.eq({ kind = "container", name = "shop-web-1" }, { kind = rows[1].item.kind, name = rows[1].item.name })
  end)

  it("highlights the status, unhealthy and failed containers are diagnostics", function()
    t.eq(
      { "DockerRunning", "DockerFailed", "DockerFailed", "DockerSucceeded" },
      vim.tbl_map(function(row)
        return row.highlights.STATUS
      end, rows)
    )
    t.eq(nil, rows[1].diagnostics)
    t.eq("The container is unhealthy", rows[2].diagnostics[1].message)
    t.eq("Exited with code 1", rows[3].diagnostics[1].message)
    t.eq(nil, rows[4].diagnostics)
  end)

  it("reads a label, not one of the same prefix", function()
    local label = require("docker.formatters.containers").label
    t.eq(
      "shop",
      label("com.docker.compose.project.config_files=/a,com.docker.compose.project=shop", "com.docker.compose.project")
    )
    t.eq(nil, label("com.docker.compose.project.config_files=/a", "com.docker.compose.project"))
    t.eq(nil, label(nil, "com.docker.compose.project"))
  end)
end)

describe("images", function()
  local rows = format("images", "images.ndjson")

  it("removes tagged images by tag, untagged ones by ID", function()
    t.eq("nginx:1.27", rows[1].item.ref)
    t.eq("nginx:latest", rows[2].item.ref)
    t.eq("9f8e7d6c5b4a", rows[3].item.ref)
    t.eq("1e5f3c5b981a", rows[1].item.name)
  end)
end)

describe("compose", function()
  it("highlights partly running projects as pending", function()
    local rows = format("compose", "compose.json")
    t.eq({ "shop", "running(2)", "/shop/compose.yaml" }, rows[1].row)
    t.eq("DockerRunning", rows[1].highlights.STATUS)
    t.eq("DockerPending", rows[2].highlights.STATUS)
  end)
end)

describe("types", function()
  it("lists the kinds", function()
    t.eq(
      { "compose", "containers", "images", "networks", "volumes" },
      vim.tbl_map(function(row)
        return row.item.name
      end, formatters.types.format({}))
    )
  end)
end)
