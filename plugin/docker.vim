if exists('g:loaded_docker')
  finish
endif
let g:loaded_docker = 1

if empty(globpath(&runtimepath, 'autoload/resource.vim'))
  echohl ErrorMsg
  echomsg 'docker.nvim requires resource.vim: https://github.com/kezhenxu94/resource.vim'
  echohl None
  finish
endif

command! -nargs=* -complete=customlist,docker#commands#complete Docker call docker#commands#run(<q-args>)

call resource#register(docker#provider#get())
