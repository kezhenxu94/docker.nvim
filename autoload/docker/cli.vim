" The docker commands. A context of '' is docker's current context.

function! s:state_file() abort
  return docker#compat#state_dir() . '/docker_state.json'
endfunction

" The context switched to with :Docker context, '' for docker's current context
let s:context = ''
if filereadable(s:state_file())
  try
    let s:state = json_decode(join(readfile(s:state_file()), "\n"))
    if type(s:state) == v:t_dict && type(get(s:state, 'context')) == v:t_string
      let s:context = s:state.context
    endif
  catch
  endtry
  unlet! s:state
endif

function! docker#cli#cmd(context, args) abort
  return (a:context ==# '' ? ['docker'] : ['docker', '--context', a:context]) + a:args
endfunction

" Run docker. Callback(stdout, code, stderr) is called when it is done, stdout is v:null on failure,
" OnError(stderr) on failure. Returns the job, {} if docker cannot be run.
function! s:docker(context, args, Callback, OnError) abort
  let cmd = docker#cli#cmd(a:context, a:args)
  let job = docker#compat#job_start(cmd, {
        \ 'on_exit': {code, out, err -> s:done(a:Callback, a:OnError, code, out, err)}})
  if empty(job)
    call docker#util#notify('Failed to run docker: ' . join(cmd), 'error')
  endif
  return job
endfunction

function! s:done(Callback, OnError, code, out, err) abort
  if a:code != 0 && a:OnError isnot v:null
    call a:OnError(trim(a:err))
  endif
  if a:Callback isnot v:null
    call a:Callback(a:code == 0 ? a:out : v:null, a:code, a:err)
  endif
endfunction

" Run docker synchronously, returns the lines of stdout, [] on failure.
function! s:docker_sync(context, args) abort
  let output = system(join(map(docker#cli#cmd(a:context, a:args), {_, arg -> s:shellescape(arg)})))
  return v:shell_error ? [] : split(output, "\n")
endfunction

" For sh, whatever 'shell' is
function! s:shellescape(arg) abort
  return "'" . substitute(a:arg, "'", "'\\\\''", 'g') . "'"
endfunction

let s:json = '--format={{json .}}'

" The list commands by kind
let s:list = {
      \ 'containers': ['ps', '--all', s:json],
      \ 'images': ['images', s:json],
      \ 'volumes': ['volume', 'ls', s:json],
      \ 'networks': ['network', 'ls', s:json],
      \ 'compose': ['compose', 'ls', '--all', '--format=json'],
      \ }

" The inspect commands by kind
let s:inspect = {
      \ 'containers': ['container', 'inspect'],
      \ 'images': ['image', 'inspect'],
      \ 'volumes': ['volume', 'inspect'],
      \ 'networks': ['network', 'inspect'],
      \ }

" The kinds that can be listed
function! docker#cli#kinds() abort
  return sort(keys(s:list))
endfunction

function! docker#cli#inspectable(kind) abort
  return has_key(s:inspect, a:kind)
endfunction

" Decode the output of a list command: JSON lines, or a JSON array for compose ls.
function! docker#cli#decode(output) abort
  let output = trim(a:output)
  if output =~# '^\['
    return json_decode(output)
  endif
  return map(split(output, "\n"), {_, line -> json_decode(line)})
endfunction

" filters: {key: value} as --filter key=value, project is the compose project label
function! docker#cli#list(context, kind, filters, Callback, OnError) abort
  let args = copy(s:list[a:kind])
  for key in sort(keys(a:filters))
    let value = docker#util#param_string(a:filters[key])
    let filter = key ==# 'project' ? 'label=com.docker.compose.project=' . value : key . '=' . value
    call extend(args, ['--filter', filter])
  endfor
  return s:docker(a:context, args, a:Callback, a:OnError)
endfunction

function! docker#cli#inspect(context, kind, name, Callback, OnError) abort
  return s:docker(a:context, s:inspect[a:kind] + [a:name], a:Callback, a:OnError)
endfunction

function! docker#cli#history(context, image, Callback, OnError) abort
  return s:docker(a:context, ['history', s:json, a:image], a:Callback, a:OnError)
endfunction

" The logs of a container or a compose project, stdout and stderr in order.
" opts: {follow, since, tail}, tail defaults to g:docker_logs_tail, -1 for all.
" Callback(text) is called with complete lines (newline separated): once when done, as they
" arrive when following.
function! docker#cli#logs(context, kind, name, opts, Callback, OnError) abort
  let args = a:kind ==# 'compose' ? ['compose', '--project-name', a:name, 'logs', '--no-color'] : ['logs']
  call add(args, '--tail=' . get(a:opts, 'tail', docker#util#config('logs_tail')))
  if get(a:opts, 'since', '') !=# ''
    call add(args, '--since=' . a:opts.since)
  endif
  if get(a:opts, 'follow', 0)
    call add(args, '--follow')
  endif
  if a:kind !=# 'compose'
    call add(args, a:name)
  endif
  " The output of the container goes to both, merged to keep the order
  let cmd = ['sh', '-c', join(map(docker#cli#cmd(a:context, args), {_, arg -> s:shellescape(arg)})) . ' 2>&1']

  if get(a:opts, 'follow', 0)
    " Output arrives in arbitrary chunks, only complete lines are emitted
    let state = {'pending': ''}
    let opts = {
          \ 'on_out': {data -> s:emit_lines(state, data, a:Callback)},
          \ 'on_exit': {code, out, err -> state.pending ==# '' ? 0 : a:Callback(state.pending)},
          \ }
  else
    let opts = {'on_exit': {code, out, err -> s:logs_done(code, out, a:Callback, a:OnError)}}
  endif
  let job = docker#compat#job_start(cmd, opts)
  if empty(job)
    call docker#util#notify('Failed to run docker: ' . join(cmd), 'error')
  endif
  return job
endfunction

function! s:emit_lines(state, data, Callback) abort
  let a:state.pending .= a:data
  let last_newline = strridx(a:state.pending, "\n")
  if last_newline >= 0
    let lines = strpart(a:state.pending, 0, last_newline)
    let a:state.pending = strpart(a:state.pending, last_newline + 1)
    call a:Callback(lines)
  endif
endfunction

function! s:logs_done(code, out, Callback, OnError) abort
  let text = substitute(a:out, '\n$', '', '')
  if a:code != 0
    if a:OnError isnot v:null
      call a:OnError(text)
    endif
  else
    call a:Callback(text)
  endif
endfunction

" Remove a resource, see the formatters for the items.
function! docker#cli#remove(context, item, Callback, OnError) abort
  let args = {
        \ 'container': ['rm', '--force', a:item.name],
        \ 'image': ['rmi', get(a:item, 'ref', a:item.name)],
        \ 'volume': ['volume', 'rm', a:item.name],
        \ 'network': ['network', 'rm', a:item.name],
        \ 'compose': ['compose', '--project-name', a:item.name, 'down'],
        \ }[a:item.kind]
  return s:docker(a:context, args, a:Callback, a:OnError)
endfunction

" verb: start, stop, restart, pause, unpause or kill
function! docker#cli#container(context, verb, name, Callback, OnError) abort
  return s:docker(a:context, [a:verb, a:name], a:Callback, a:OnError)
endfunction

" verb: start, stop or restart
function! docker#cli#compose(context, verb, project, Callback, OnError) abort
  return s:docker(a:context, ['compose', '--project-name', a:project, a:verb], a:Callback, a:OnError)
endfunction

function! docker#cli#pull(context, ref, Callback, OnError) abort
  return s:docker(a:context, ['pull', '--quiet', a:ref], a:Callback, a:OnError)
endfunction

" The command of a shell in a container.
function! docker#cli#exec_cmd(context, name, command) abort
  return docker#cli#cmd(a:context, ['exec', '--interactive', '--tty', a:name, a:command])
endfunction

" The context switched to with :Docker context, or docker's current context, '' if none.
function! docker#cli#current_context() abort
  return s:context !=# '' ? s:context : get(s:docker_sync('', ['context', 'show']), 0, '')
endfunction

function! docker#cli#contexts(Callback) abort
  return s:docker('', ['context', 'ls', s:json], a:Callback, v:null)
endfunction

function! docker#cli#context_names() abort
  return s:docker_sync('', ['context', 'ls', '--format={{.Name}}'])
endfunction

" Use a context for docker.nvim only, docker's current context is left as is; '' to use it again.
function! docker#cli#use_context(name) abort
  let s:context = a:name
  call mkdir(docker#compat#state_dir(), 'p')
  call writefile([json_encode({'context': a:name ==# '' ? v:null : a:name})], s:state_file())
endfunction
