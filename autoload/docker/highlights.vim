" Linked with default, so colorschemes and :highlight take precedence.
function! docker#highlights#setup() abort
  let warn = hlexists('DiagnosticWarn') ? 'DiagnosticWarn' : 'WarningMsg'
  let error = hlexists('DiagnosticError') ? 'DiagnosticError' : 'ErrorMsg'
  execute 'highlight default link DockerPending' warn
  execute 'highlight default link DockerFailed' error
  highlight default link DockerBody Normal
  highlight default link DockerRunning Normal
  highlight default link DockerSucceeded Comment
  highlight default link DockerHeader Title
  " Rows deleted from a list, until :w deletes the resources
  highlight default link DockerDeleted DiffDelete
  " Rows a watched reload changed
  highlight default link DockerChanged DiffChange
  for [group, attributes] in items(docker#util#config('highlights'))
    execute 'highlight' group attributes
  endfor

  " The diagnostics of containers
  call sign_define('DockerError', {'text': 'E', 'texthl': 'DockerFailed'})
  call sign_define('DockerWarn', {'text': 'W', 'texthl': 'DockerPending'})
endfunction
