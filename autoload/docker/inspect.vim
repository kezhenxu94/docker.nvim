" The docker inspect JSON of the buffer's resource, read-only.
function! docker#inspect#load(dbuf) abort
  if !docker#cli#inspectable(a:dbuf.kind)
    call docker#buffer#on_error(a:dbuf, 'Cannot inspect ' . a:dbuf.kind)
    return {}
  endif
  call setbufvar(a:dbuf.buf, '&filetype', 'json')
  return docker#buffer#add_job(a:dbuf, docker#cli#inspect(a:dbuf.context, a:dbuf.kind, a:dbuf.name,
        \ {json, ... -> json isnot v:null && bufloaded(a:dbuf.buf)
        \   ? docker#buffer#set_lines(a:dbuf, split(trim(json), "\n"), 0) : 0},
        \ {err -> docker#buffer#on_error(a:dbuf, err)}))
endfunction
