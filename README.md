# docker.nvim

Neovim Docker plugin, manage your containers, images, volumes, networks and compose projects like a buffer!

[![docker.nvim demo](demo/docker-nvim.gif)](https://asciinema.org/a/TssTCntMhyDGHlLL)

For Kubernetes, see [kube.nvim](https://github.com/kezhenxu94/kube.nvim), the same buffers for Kubernetes resources.

## Installation

Requirements: Neovim >= 0.11 and `docker` in `$PATH` (`docker compose` for compose projects). No other plugin dependencies.

With Neovim's built-in plugin manager (`:help vim.pack`, Neovim >= 0.12):

```lua
vim.pack.add({ "https://github.com/kezhenxu94/docker.nvim" })
```

`setup()` is optional, call it only to change the [configuration](#configuration). Run `:checkhealth docker` to check docker and the daemon.

## Usage

* `:Docker get containers`: All containers, running or not.
* `:Docker get containers status=running`: Running containers, any `docker ps --filter` works, `project=web` for the containers of the compose project `web`.
* `:Docker get images reference=nginx`: The images of nginx.
* `:Docker context`: Select the docker context to use, `:Docker context remote` to switch to `remote`. Only docker.nvim is affected, not docker's current context.

Every view is a buffer named `docker://[context/{context}/]{kind}[/{name}[/{subresource}]][?{filters}]`, so you can also open them directly:

* `:e docker://`: The kinds: `containers`, `images`, `volumes`, `networks` and `compose` (projects), `<CR>` on one lists it.
* `:e docker://containers?project=web`: The containers of the compose project `web`.
* `:e docker://containers/web-1/logs?follow`: Follow the logs of the container `web-1`.
* `:e docker://containers/web-1/exec?cmd=bash`: A shell in the container `web-1`.
* `:e docker://images/1e5f3c5b981a/history`: The layers of an image.
* `:e docker://context/remote/containers`: The containers of the `remote` context.

A buffer opened without `context/{context}/` is bound to the context that was current when it was opened. Reloading and removing from it keep operating on that daemon even after you switch to another context.

docker.nvim buffers behave like file buffers: every jump is an `:edit` in the current window, so `<C-o>`, `<C-^>`, `<C-t>`, `'hidden'` and `:bd` work as usual.

## Features

* **Edit docker like a buffer**: delete lines and `:w` to remove containers, images (by tag), volumes, networks or take compose projects down, after confirming (`:w!` skips the confirmation). Deleted lines stay visible until written.
* **Operations**: `gra` offers start / stop / restart / pause / unpause / kill / remove for containers, start / stop / restart / down for compose projects, pull / remove for images, on the item under the cursor or every item of a visual selection.
* **Logs**: of containers and compose projects, limited to the last 1000 lines by default. Following keeps the cursor at the end, like `tail -f`. Logs can be edited, e.g. `:%!jq -r .msg` to make them readable, `:w {file}` saves them.
* **exec**: open a shell in a container right in Neovim.
* **Inspect**: `docker inspect` of containers, images, volumes and networks as JSON.
* **Watch**: `gw` reloads a list periodically, keeping the cursor on the same item.
* **Diagnostics**: unhealthy, dead, restarting and failed (non-zero exit code) containers are diagnostics, `]d` jumps to the next one.

## Keymaps

Keymaps follow Neovim's conventions: tags' `<C-]>`, code actions' `gra`, and the built-in directory browser's `<CR>` / `-` / `R`.

* `<CR>`: Drill down into the item under the cursor: a container's logs, an image's history, the containers of a volume, network or compose project, the list of a kind.
* `gd`: Go to what the cell under the cursor refers to, like `<C-]>`.
* `-`: Go to the parent buffer: item → its list → the unfiltered list (the compose projects for the containers of a project) → the kinds.
* `R`: Reload the buffer, the cursor stays on the same item.
* `gw`: Toggle reloading the list every `refresh_interval`.
* `gl` / `gL`: Show / follow logs, `<C-c>` stops following.
* `gs`: Open a shell (`docker exec`) in the container under the cursor.
* `gra`: Operations on the item under the cursor, or on the items of a visual selection.
* `g?`: Show the help.

Built-in keys that work in docker buffers:

* `<C-]>`: Jump to what the cell under the cursor refers to: a container's IMAGE lists the image, its PROJECT the containers of the project, a compose project its containers, anything else goes to its `docker inspect`. `<C-t>` jumps back and `<C-w>]` opens the jump in a split, as with tags.
* `]d` / `[d`: Next / previous unhealthy container, `<C-w>d` shows why.

See `:help docker.nvim` for the details.

## Configuration

The defaults:

```lua
require("docker").setup({
  keymaps = {
    drill_down = "<cr>",
    inspect = "gd",
    parent = "-",
    refresh = "R",
    watch = "gw",
    show_logs = "gl",
    follow_logs = "gL",
    exec = "gs",
    operations = "gra",
    help = "g?",
  },
  -- How often watched lists (gw) reload, in milliseconds, false to disable watching
  refresh_interval = 10000,
  -- The command gs runs in containers
  exec_command = "sh",
  logs = {
    tail = 1000, -- Lines to fetch, -1 for all
    max_lines = 10000, -- Lines kept while following, -1 for all
  },
  -- Highlight overrides, by default linked to your colorscheme's groups:
  -- DockerBody (Normal), DockerPending (DiagnosticWarn), DockerRunning (Normal),
  -- DockerFailed (DiagnosticError), DockerSucceeded (Comment), DockerHeader (Title),
  -- DockerDeleted (DiffDelete): deleted lines, DockerChanged (DiffChange): lines a watched reload changed
  -- e.g. { DockerHeader = { fg = "#df8e1d", bold = true } }
  highlights = {},
})
```

## Contributing

* `make test`: Tests in headless Neovim against a fake `docker` (`tests/bin/docker`), never a real daemon.
* `make lint`: Check the formatting with [StyLua](https://github.com/JohnnyMorganz/StyLua).
* `make demo`: Record the demo with [asciinema](https://asciinema.org) in tmux, against the containers of `demo/compose.yaml` on the current docker context, `docker compose -p docker-nvim-demo down -v` removes them.
