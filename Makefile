NVIM ?= nvim
SPECS ?= $(wildcard tests/*_spec.lua)

.PHONY: test lint format demo

# Each spec runs in its own Neovim with isolated state, against tests/bin/docker (never a real daemon)
test:
	@failed=0; for spec in $(SPECS); do \
		tmp=$$(mktemp -d); \
		XDG_STATE_HOME=$$tmp/state XDG_DATA_HOME=$$tmp/data XDG_CONFIG_HOME=$$tmp/config \
			$(NVIM) --headless --clean -l tests/runner.lua $$spec || failed=1; \
		rm -rf $$tmp; \
	done; exit $$failed

lint:
	stylua --check lua tests plugin

format:
	stylua lua tests plugin

# The README demo, recorded with asciinema in tmux against throwaway containers
demo:
	demo/setup.sh
	demo/record.sh
	agg demo/docker-nvim.cast demo/docker-nvim.gif
