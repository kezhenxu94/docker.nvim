" Operations on the items of buffer rows, offered by gra: [{title, run: Fn()}].

" Run Call(item) on every item, it returns the job of the docker command, then reload the buffer.
function! s:run(dbuf, items, Call) abort
  call resource#run(a:dbuf, a:items, a:Call)
endfunction

function! s:confirmed(dbuf, items, verb, Call) abort
  call resource#run(a:dbuf, a:items, a:Call, a:verb . ' ' . resource#describe(a:dbuf, a:items))
endfunction

function! s:title(verb) abort
  return toupper(a:verb[0]) . a:verb[1:]
endfunction

" The kinds of items that can be removed, to name them in bulk operations
let s:plurals = {
      \ 'container': 'containers',
      \ 'image': 'images',
      \ 'volume': 'volumes',
      \ 'network': 'networks',
      \ 'compose': 'compose projects',
      \ }

" Verbs of docker {verb} {container}, and whether they need a confirmation
let s:container_verbs = [['start', 0], ['stop', 1], ['restart', 1], ['pause', 0], ['unpause', 0], ['kill', 1]]
" Verbs of docker compose --project-name {project} {verb}
let s:compose_verbs = [['start', 0], ['stop', 1], ['restart', 1]]

" Call(context, verb, name, Callback, OnError)
function! s:verb_operations(dbuf, items, verbs, Call) abort
  let operations = []
  for [verb, needs_confirm] in a:verbs
    let Fn = function('s:call_verb', [a:Call, a:dbuf.context, verb])
    call add(operations, {'title': s:title(verb), 'run': needs_confirm
          \ ? function('s:confirmed', [a:dbuf, a:items, s:title(verb), Fn])
          \ : function('s:run', [a:dbuf, a:items, Fn])})
  endfor
  return operations
endfunction

function! s:call_verb(Call, context, verb, item) abort
  return a:Call(a:context, a:verb, a:item.name, v:null, v:null)
endfunction

function! s:pull(dbuf, items) abort
  call resource#notify('Pulling ' . resource#describe(a:dbuf, a:items))
  call s:run(a:dbuf, a:items, {item -> docker#cli#pull(a:dbuf.context, item.ref, v:null, v:null)})
endfunction

" The operations for the items of the given buffer rows, all of the same kind.
function! docker#operations#for_items(dbuf, items) abort
  if empty(a:items)
    return []
  endif
  let kind = a:items[0].kind
  let operations = []

  if len(a:items) == 1
    let item = a:items[0]
    let actions = docker#actions#get(kind)
    if has_key(actions, 'show_logs')
      call add(operations, {'title': 'Logs', 'run': function(actions.show_logs, [a:dbuf, item, 0])})
      call add(operations, {'title': 'Follow logs', 'run': function(actions.show_logs, [a:dbuf, item, 1])})
    endif
    if has_key(actions, 'exec')
      call add(operations, {'title': 'Exec', 'run': function(actions.exec, [a:dbuf, item])})
    endif
    if kind ==# 'image'
      call add(operations, {'title': 'History', 'run': function(actions.drill_down, [a:dbuf, item])})
    endif
  endif

  if kind ==# 'container'
    call extend(operations, s:verb_operations(a:dbuf, a:items, s:container_verbs, function('docker#cli#container')))
  elseif kind ==# 'compose'
    call extend(operations, s:verb_operations(a:dbuf, a:items, s:compose_verbs, function('docker#cli#compose')))
  elseif kind ==# 'image'
    if empty(filter(copy(a:items), {_, item -> item.ref ==# item.name}))
      call add(operations, {'title': 'Pull', 'run': function('s:pull', [a:dbuf, a:items])})
    endif
  endif

  if has_key(s:plurals, kind)
    let verb = kind ==# 'compose' ? 'Down' : 'Remove'
    call add(operations, {'title': verb, 'run': function('s:confirmed', [a:dbuf, a:items, verb,
          \ {item -> docker#cli#remove(a:dbuf.context, item, v:null, v:null)}])})
  endif

  if len(a:items) > 1
    " Name the targets of bulk operations
    for operation in operations
      let operation.title = printf('%s %d %s', operation.title, len(a:items), get(s:plurals, kind, kind))
    endfor
  endif
  return operations
endfunction
