" kind: the kind to list, filters: {key: value} for docker … --filter key=value
function! docker#get(kind, ...) abort
  if a:kind ==# ''
    call docker#util#notify('Usage: :Docker get {kind} [{filter}={value}]...', 'error')
    return
  endif
  call docker#util#open({'kind': a:kind, 'params': get(a:, 1, {})})
endfunction

" Switch to a context, select one if it is ''.
function! docker#ctx(context) abort
  if a:context !=# ''
    call docker#cli#use_context(a:context)
    call docker#util#notify('Switched to context: ' . a:context)
    return
  endif
  call docker#cli#contexts({result, ... -> s:select_context(result)})
endfunction

function! s:select_context(result) abort
  if a:result is v:null
    call docker#util#notify('No contexts found', 'error')
    return
  endif
  let current = docker#cli#current_context()
  let names = map(docker#cli#decode(a:result), 'v:val.Name')
  let choice = docker#util#select(map(copy(names), {_, name -> (name ==# current ? '* ' : '  ') . name}),
        \ printf('Select context (current: %s)', current))
  if choice >= 0
    call docker#ctx(names[choice])
  endif
endfunction
