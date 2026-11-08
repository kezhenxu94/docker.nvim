if exists('g:loaded_docker')
  finish
endif
let g:loaded_docker = 1

command! -nargs=* -complete=customlist,docker#commands#complete Docker call docker#commands#run(<q-args>)

augroup docker_autocmds
  autocmd!
  " Nested so that the BufReadCmd of the buffer an alias redirects to runs
  autocmd BufReadCmd docker://* ++nested call docker#buffer#on_read(str2nr(expand('<abuf>')))
  autocmd BufUnload docker://* call docker#buffer#on_unload(str2nr(expand('<abuf>')))
  autocmd BufDelete,BufWipeout docker://* call docker#buffer#on_delete(str2nr(expand('<abuf>')))
  autocmd BufWriteCmd docker://* call docker#buffer#on_write(str2nr(expand('<abuf>')), v:cmdbang)
  autocmd TextChanged,TextChangedI docker://* call docker#buffer#on_text_changed(str2nr(expand('<abuf>')))
  " Also for other buffers, to remove the table header of a window that showed one
  autocmd BufWinEnter * if expand('<afile>') =~# '^docker://' || exists('w:docker_header')
        \ | call docker#buffer#on_win_enter(str2nr(expand('<abuf>'))) | endif
  autocmd WinScrolled * if exists('w:docker_header') | call docker#buffer#on_scroll() | endif
  if exists('##WinResized')
    autocmd WinResized * if exists('w:docker_header') | call docker#buffer#on_scroll() | endif
  endif
  autocmd ColorScheme * if exists('*docker#highlights#setup') | call docker#highlights#setup() | endif
  autocmd VimLeavePre * if exists('*docker#buffer#stop_all') | call docker#buffer#stop_all() | endif
augroup END
