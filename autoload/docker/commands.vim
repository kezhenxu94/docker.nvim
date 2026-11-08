" :Docker {command} [{args}]

" :Docker get {kind} [{key}={value}]...: [kind, filters]
function! docker#commands#parse_get(args) abort
  let filters = {}
  for arg in a:args[1:]
    let match = matchlist(arg, '^\([^=]\+\)=\(.\+\)$')
    if !empty(match)
      let filters[match[1]] = match[2]
    endif
  endfor
  return [get(a:args, 0, ''), filters]
endfunction

function! s:filter(candidates, arglead) abort
  return filter(copy(a:candidates), {_, candidate -> stridx(candidate, a:arglead) == 0})
endfunction

" Completion of :Docker get, args are the arguments after get.
function! docker#commands#complete_get(arglead, args) abort
  if len(a:args) <= 1
    return s:filter(docker#cli#kinds(), a:arglead)
  endif
  " The common docker ps --filter keys, project is the compose project
  return s:filter(['project=', 'status=', 'name=', 'label=', 'ancestor=', 'network=', 'volume='], a:arglead)
endfunction

function! docker#commands#complete(arglead, cmdline, cursorpos) abort
  " Without the command name
  let args = split(a:cmdline, ' ', 1)[1:]
  if len(args) <= 1
    return s:filter(['context', 'get'], a:arglead)
  endif
  let command = remove(args, 0)
  if command ==# 'get'
    return docker#commands#complete_get(a:arglead, args)
  elseif command ==# 'context'
    return s:filter(docker#cli#context_names(), a:arglead)
  endif
  return []
endfunction

function! docker#commands#run(args) abort
  let args = split(a:args)
  let command = get(args, 0, '')
  if command ==# 'get'
    call call('docker#get', docker#commands#parse_get(args[1:]))
  elseif command ==# 'context'
    call docker#ctx(get(args, 1, ''))
  else
    call resource#notify('No such command: ' . command, 'error')
  endif
endfunction
