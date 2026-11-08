" Actions on the item of a row, by item kind: drill_down, show_logs (follow) and exec. They receive
" the buffer the item was selected from, which provides the context.

" Open a buffer, in the context of dbuf.
function! s:open(dbuf, opts) abort
  call docker#util#open(extend({'context': a:dbuf.context}, a:opts))
endfunction

function! s:show_logs(kind, dbuf, item, follow) abort
  call s:open(a:dbuf, {'kind': a:kind, 'name': a:item.name, 'subresource': 'logs',
        \ 'params': a:follow ? {'follow': v:true} : {}})
endfunction

" The containers of the item, filtered with docker ps --filter
function! s:open_containers(filter, dbuf, item) abort
  call s:open(a:dbuf, {'kind': 'containers', 'params': {a:filter: a:item.name}})
endfunction

let s:actions = {
      \ 'type': {
      \   'drill_down': {dbuf, item -> s:open(dbuf, {'kind': item.name})},
      \ },
      \ 'container': {
      \   'drill_down': {dbuf, item -> s:show_logs('containers', dbuf, item, 0)},
      \   'show_logs': function('s:show_logs', ['containers']),
      \   'exec': {dbuf, item -> s:open(dbuf, {'kind': 'containers', 'name': item.name, 'subresource': 'exec'})},
      \ },
      \ 'image': {
      \   'drill_down': {dbuf, item -> s:open(dbuf, {'kind': 'images', 'name': item.name, 'subresource': 'history'})},
      \ },
      \ 'volume': {
      \   'drill_down': function('s:open_containers', ['volume']),
      \ },
      \ 'network': {
      \   'drill_down': function('s:open_containers', ['network']),
      \ },
      \ 'compose': {
      \   'drill_down': function('s:open_containers', ['project']),
      \   'show_logs': function('s:show_logs', ['compose']),
      \ },
      \ }

" The actions of an item kind: {name: Fn(dbuf, item, ...)}.
function! docker#actions#get(kind) abort
  return get(s:actions, a:kind, {})
endfunction
