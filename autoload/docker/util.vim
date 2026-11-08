" Buffer names.

" docker://[context/<context>/]<kind>[/<name>[/<subresource>]][?<params>]
" Without a context the buffer is pinned to the current context when it is opened.
" opts: {context, kind, name, subresource, params}, all optional but kind
function! docker#util#buf_name(opts) abort
  let segments = []
  if get(a:opts, 'context', '') !=# ''
    " Encoded as context names may contain / and :
    call extend(segments, ['context', resource#uri_encode(a:opts.context)])
  endif
  call add(segments, a:opts.kind)
  if get(a:opts, 'name', '') !=# ''
    call add(segments, a:opts.name)
    if get(a:opts, 'subresource', '') !=# ''
      call add(segments, a:opts.subresource)
    endif
  endif
  return resource#name('docker', segments, get(a:opts, 'params', {}))
endfunction

" Open (or switch to) the buffer for the given name parts.
function! docker#util#open(opts) abort
  call resource#open(docker#util#buf_name(a:opts))
endfunction
