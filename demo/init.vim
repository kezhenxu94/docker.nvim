" Neovim of the demo: only docker.nvim, with the defaults
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
set termguicolors nohlsearch shortmess+=I
if exists('+winborder')
  set winborder=rounded
endif
