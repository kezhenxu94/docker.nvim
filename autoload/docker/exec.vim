" Shells in containers: the buffer docker://context/{context}/containers/{name}/exec[?cmd={command}]
" starts it when it is read, like term:// buffers.
function! docker#exec#start(name, parts) abort
  if a:parts.kind !=# 'containers' || a:parts.name ==# ''
    call docker#util#notify('Expected: docker://context/{context}/containers/{name}/exec[?cmd={command}]', 'error')
    return
  endif
  let command = type(get(a:parts.params, 'cmd')) == v:t_string ? a:parts.params.cmd : docker#util#config('exec_command')
  call docker#compat#term(docker#cli#exec_cmd(a:parts.context, a:parts.name, command), a:name)
endfunction

" Open a shell in a container, it is started when the buffer is read unless it already exists.
function! docker#exec#open(context, name) abort
  call docker#util#open({'context': a:context, 'kind': 'containers', 'name': a:name, 'subresource': 'exec'})
  call docker#compat#startinsert()
endfunction
