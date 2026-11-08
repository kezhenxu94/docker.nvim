" kind: the kind to list, filters: {key: value} for docker … --filter key=value
function! docker#get(kind, ...) abort
  if a:kind ==# ''
    call resource#notify('Usage: :Docker get {kind} [{filter}={value}]...', 'error')
    return
  endif
  call docker#util#open({'kind': a:kind, 'params': get(a:, 1, {})})
endfunction

" Switch to a context, select one if it is ''.
function! docker#ctx(context) abort
  if a:context !=# ''
    call docker#cli#use_context(a:context)
    call resource#notify('Switched to context: ' . a:context)
    return
  endif
  call docker#cli#contexts({result, ... -> s:select_context(result)})
endfunction

function! s:select_context(result) abort
  if a:result is v:null
    call resource#notify('No contexts found', 'error')
    return
  endif
  let current = docker#cli#current_context()
  let names = map(docker#cli#decode(a:result), 'v:val.Name')
  call resource#select(names, {'prompt': printf('Select context (current: %s)', current),
        \ 'format_item': {name -> (name ==# current ? '* ' : '  ') . name}},
        \ {name, ... -> name is v:null ? 0 : docker#ctx(name)})
endfunction
