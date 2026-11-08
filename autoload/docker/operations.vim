" Operations on the items of buffer rows, offered by gra: [{title, run: Fn()}].

function! s:describe_targets(items) abort
  let names = map(copy(a:items), {_, item -> item.kind . ' ' . get(item, 'ref', item.name)})
  if len(names) > 3
    return printf('%s and %d more', join(names[:2], ', '), len(names) - 3)
  endif
  return join(names, ', ')
endfunction

" Run a docker command on every item (Call(item, Callback, OnError)), then reload the buffer.
function! s:run(dbuf, items, Call) abort
  let state = {'remaining': len(a:items)}
  for item in a:items
    call a:Call(item, {result, ... -> s:finished(a:dbuf, state, result)},
          \ {err -> docker#util#notify(err, 'error')})
  endfor
endfunction

function! s:finished(dbuf, state, result) abort
  if a:result isnot v:null && trim(a:result) !=# ''
    call docker#util#notify(trim(a:result))
  endif
  let a:state.remaining -= 1
  if a:state.remaining == 0
    call docker#buffer#load(a:dbuf)
  endif
endfunction

function! s:confirmed(dbuf, items, verb, Call) abort
  if docker#util#confirm(printf('%s %s (context: %s)?', a:verb, s:describe_targets(a:items), a:dbuf.context))
    call s:run(a:dbuf, a:items, a:Call)
  endif
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

function! s:call_verb(Call, context, verb, item, Callback, OnError) abort
  return a:Call(a:context, a:verb, a:item.name, a:Callback, a:OnError)
endfunction

function! s:pull(dbuf, items) abort
  call docker#util#notify('Pulling ' . s:describe_targets(a:items))
  call s:run(a:dbuf, a:items, {item, Callback, OnError -> docker#cli#pull(a:dbuf.context, item.ref, Callback, OnError)})
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
          \ {item, Callback, OnError -> docker#cli#remove(a:dbuf.context, item, Callback, OnError)}])})
  endif

  if len(a:items) > 1
    " Name the targets of bulk operations
    for operation in operations
      let operation.title = printf('%s %d %s', operation.title, len(a:items), get(s:plurals, kind, kind))
    endfor
  endif
  return operations
endfunction

" Pick an operation for the items of the rows in [first, last] and run it.
function! docker#operations#select(dbuf, first, last) abort
  let operations = docker#operations#for_items(a:dbuf, docker#resources#items_in_rows(a:dbuf, a:first, a:last))
  if empty(operations)
    call docker#util#notify('No operations', 'warn')
    return
  endif
  let choice = docker#util#select(map(copy(operations), 'v:val.title'), 'Operation')
  if choice >= 0
    call operations[choice].run()
  endif
endfunction
