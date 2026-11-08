EDITORS ?= vim nvim
SPECS ?= $(wildcard tests/test_*.vim)
# The checkout of https://github.com/kezhenxu94/resource.vim
RESOURCE_VIM ?= ../resource.vim

.PHONY: test demo

# Each spec runs in its own Vim and Neovim with isolated state, against tests/bin/docker (never a real daemon)
test:
	@failed=0; for editor in $(EDITORS); do \
		echo "== $$editor"; \
		case $$editor in \
			*nvim*) cmd="$$editor --headless -u NONE -i NONE";; \
			*) cmd="$$editor -Nu NONE -i NONE -es";; \
		esac; \
		for spec in $(SPECS); do \
			tmp=$$(mktemp -d); \
			TEST_RESULT=$$tmp/result RESOURCE_VIM=$(RESOURCE_VIM) XDG_STATE_HOME=$$tmp/state XDG_DATA_HOME=$$tmp/data XDG_CONFIG_HOME=$$tmp/config \
				$$cmd -S tests/runner.vim $$spec </dev/null || failed=1; \
			cat $$tmp/result 2>/dev/null || { echo "$$spec: did not finish"; failed=1; }; \
			rm -rf $$tmp; \
		done; \
	done; exit $$failed

# The README demo, recorded with asciinema in tmux against throwaway containers
demo:
	demo/setup.sh
	demo/record.sh
	agg demo/docker-nvim.cast demo/docker-nvim.gif
