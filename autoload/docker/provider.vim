" The docker provider of resource.vim: the buffers
" docker://[context/{context}/]{kind}[/{name}[/{subresource}]][?{params}].

function! docker#provider#get() abort
  return {
        \ 'name': 'docker',
        \ 'title': 'docker.nvim',
        \ 'parse': function('docker#provider#parse'),
        \ 'canonical': function('docker#provider#canonical'),
        \ 'load': function('docker#provider#load'),
        \ 'term': function('docker#provider#term'),
        \ 'identity': {item -> item.kind . '/' . get(item, 'ref', item.name)},
        \ 'label': {item -> item.kind . ' ' . get(item, 'ref', item.name)},
        \ 'scope': {dbuf -> 'context: ' . dbuf.context},
        \ 'parent': function('docker#navigation#parent_name'),
        \ 'tag': function('docker#navigation#tag_target'),
        \ 'delete': function('s:delete'),
        \ 'operations': function('docker#operations#for_items'),
        \ 'keymaps': {
        \   'drill_down': {'lhs': '<CR>', 'desc': 'drill down into the item under the cursor', 'run': {dbuf -> s:action(dbuf, 'drill_down')}},
        \   'inspect': {'lhs': 'gd', 'desc': 'go to what the cell under the cursor refers to, mostly docker inspect', 'run': function('s:inspect')},
        \   'show_logs': {'lhs': 'gl', 'desc': 'show the logs of the item under the cursor', 'run': {dbuf -> s:action(dbuf, 'show_logs', 0)}},
        \   'follow_logs': {'lhs': 'gL', 'desc': 'follow the logs of the item under the cursor', 'run': {dbuf -> s:action(dbuf, 'show_logs', 1)}},
        \   'exec': {'lhs': 'gs', 'desc': 'open a shell in the container under the cursor', 'run': {dbuf -> s:action(dbuf, 'exec')}},
        \ },
        \ 'help': s:HELP,
        \ 'highlights': {
        \   'DockerPending': ['DiagnosticWarn', 'WarningMsg'],
        \   'DockerFailed': ['DiagnosticError', 'ErrorMsg'],
        \   'DockerRunning': 'Normal',
        \   'DockerSucceeded': 'Comment',
        \   'DockerSignError': 'DockerFailed',
        \   'DockerSignWarn': 'DockerPending',
        \ },
        \ 'defaults': {'exec_command': 'sh', 'logs_tail': 1000},
        \ 'volatile': ['CREATED'],
        \ }
endfunction

let s:HELP = [
      \ '',
      \ 'Built-in keys that also work',
      \ '  <C-]>    jump to what the cell under the cursor refers to: a container''s',
      \ '           IMAGE the image, its PROJECT the containers of the project, a',
      \ '           compose project its containers, else docker inspect',
      \ '  <C-t>    jump back, <C-w>] opens the jump in a split',
      \ '  ]d [d    next / previous unhealthy container, <C-w>d shows why',
      \ '',
      \ 'Editing, :w applies after confirming, :w! without confirming',
      \ '  lists    delete lines to remove the containers, images, volumes,',
      \ '           networks, or to take compose projects down',
      \ '',
      \ 'Commands',
      \ '  :Docker get {kind} [{filter}={value}]...',
      \ '  :Docker context [{context}]',
      \ '',
      \ 'Buffer names',
      \ '  docker://[context/{context}/]{kind}[/{name}[/{subresource}]][?{filters}]',
      \ '  Without context/{context}/ the current context is used and the buffer',
      \ '  stays bound to it, e.g. :e docker://containers?status=running',
      \ '  :e docker:// lists the kinds',
      \ '',
      \ 'More in :help docker.nvim',
      \ ]

" ------------------------------------------------------------------ names

" Parse a buffer name, see docker#util#buf_name() for the format. Throws when it is invalid.
function! docker#provider#parse(name) abort
  let parts = resource#parse(a:name)
  let segments = parts.segments
  if get(segments, 0, '') !=# 'context' || len(segments) < 3
    throw 'Invalid buffer name format. Expected: docker://context/{context}/{kind}[/{name}[/{subresource}]]'
  endif
  return {
        \ 'context': resource#uri_decode(segments[1]),
        \ 'kind': segments[2],
        \ 'name': get(segments, 3, ''),
        \ 'subresource': get(segments, 4, ''),
        \ 'params': parts.params,
        \ }
endfunction

" The name of the buffer a name is an alias of, itself if none: without context/<context>/ it is
" pinned to the current context, so the buffer keeps operating on the same daemon after the
" context is switched; no kind is the kinds, types. Throws without a current context.
function! docker#provider#canonical(name) abort
  let rest = substitute(strpart(a:name, len('docker://')), '^/\+', '', '')
  let context = matchstr(rest, '^context/[^/?]*/\=')
  if context !=# ''
    let rest = strpart(rest, len(context))
    if context !~# '/$'
      let context .= '/'
    endif
  else
    let current = docker#cli#current_context()
    if current ==# ''
      throw 'No current docker context'
    endif
    let context = printf('context/%s/', resource#uri_encode(current))
  endif
  return 'docker://' . context . (rest ==# '' ? 'types' : rest)
endfunction

" ------------------------------------------------------------------ loading

" Tables, as opposed to inspect / logs buffers.
function! s:is_table(dbuf) abort
  return a:dbuf.name ==# '' || a:dbuf.subresource ==# 'history'
endfunction

function! docker#provider#load(dbuf) abort
  if s:is_table(a:dbuf)
    return s:load_table(a:dbuf)
  elseif a:dbuf.subresource ==# ''
    return s:inspect_load(a:dbuf)
  elseif a:dbuf.subresource ==# 'logs'
    return s:logs(a:dbuf)
  endif
  call resource#error(a:dbuf, 'Unknown subresource: ' . a:dbuf.subresource)
  return {}
endfunction

" Lists of resources, and the history of images.
function! s:load_table(dbuf) abort
  let kind = a:dbuf.subresource ==# '' ? a:dbuf.kind : a:dbuf.subresource
  let formatter = docker#formatters#get(kind)
  if empty(formatter)
    call resource#error(a:dbuf, 'Unknown kind: ' . kind)
    return {}
  endif
  if a:dbuf.kind ==# 'types'
    call s:render(a:dbuf, formatter, [])
    return {}
  endif

  let OnResult = {result, ... -> result isnot v:null ? s:render(a:dbuf, formatter, docker#cli#decode(result)) : 0}
  let OnError = {err -> resource#error(a:dbuf, err)}
  if a:dbuf.subresource ==# 'history'
    return docker#cli#history(a:dbuf.context, a:dbuf.name, OnResult, OnError)
  endif
  return docker#cli#list(a:dbuf.context, a:dbuf.kind, a:dbuf.params, OnResult, OnError)
endfunction

function! s:render(dbuf, formatter, data) abort
  call resource#render(a:dbuf, {'headers': a:formatter.headers, 'rows': a:formatter.format(a:data),
        \ 'empty': get(a:formatter, 'empty', 'Nothing found')})
endfunction

" The docker inspect JSON of the buffer's resource, read-only.
function! s:inspect_load(dbuf) abort
  if !docker#cli#inspectable(a:dbuf.kind)
    call resource#error(a:dbuf, 'Cannot inspect ' . a:dbuf.kind)
    return {}
  endif
  call setbufvar(a:dbuf.bufnr, '&filetype', 'json')
  return docker#cli#inspect(a:dbuf.context, a:dbuf.kind, a:dbuf.name,
        \ {json, ... -> json isnot v:null ? resource#set_lines(a:dbuf, split(trim(json), "\n"), {'writable': 0}) : 0},
        \ {err -> resource#error(a:dbuf, err)})
endfunction

" The logs of a container or a compose project, ?follow, ?since={duration}, ?tail={lines}.
function! s:logs(dbuf) abort
  if a:dbuf.kind !=# 'containers' && a:dbuf.kind !=# 'compose'
    call resource#error(a:dbuf, 'Logs are only available for containers and compose projects')
    return {}
  endif
  let params = a:dbuf.params
  let opts = {'follow': get(params, 'follow', v:false) is v:true}
  if type(get(params, 'since')) == v:t_string
    let opts.since = params.since
  endif
  if type(get(params, 'tail')) == v:t_string && params.tail =~# '^-\?\d\+$'
    let opts.tail = str2nr(params.tail)
  endif
  return resource#logs(a:dbuf, docker#cli#logs_cmd(a:dbuf.context, a:dbuf.kind, a:dbuf.name, opts), opts.follow)
endfunction

" Shells in containers: docker://context/{context}/containers/{name}/exec[?cmd={command}] starts
" it when it is read, like term:// buffers.
function! docker#provider#term(parts) abort
  if a:parts.subresource !=# 'exec'
    return v:null
  endif
  if a:parts.kind !=# 'containers' || a:parts.name ==# ''
    call resource#notify('Expected: docker://context/{context}/containers/{name}/exec[?cmd={command}]', 'error')
    return []
  endif
  let command = type(get(a:parts.params, 'cmd')) == v:t_string ? a:parts.params.cmd : resource#config('docker', 'exec_command')
  return docker#cli#exec_cmd(a:parts.context, a:parts.name, command)
endfunction

" ------------------------------------------------------------------ :w and keymaps

" Deleted rows remove their item, kinds and image layers cannot be removed.
function! s:delete(dbuf, item) abort
  if a:item.kind ==# 'type' || a:item.kind ==# 'layer'
    return v:null
  endif
  return {'title': printf('%s %s %s', a:item.kind ==# 'compose' ? 'Down' : 'Remove', a:item.kind, get(a:item, 'ref', a:item.name)),
        \ 'run': {-> docker#cli#remove(a:dbuf.context, a:item, v:null, v:null)}}
endfunction

" Run the action for the item under the cursor.
function! s:action(dbuf, name, ...) abort
  let item = resource#item(a:dbuf)
  if item is v:null
    return
  endif
  let actions = docker#actions#get(item.kind)
  if !has_key(actions, a:name)
    call resource#notify(printf('%s is not supported for %s', a:name, item.kind), 'warn')
    return
  endif
  call call(actions[a:name], [a:dbuf, item] + a:000)
endfunction

function! s:inspect(dbuf) abort
  let target = resource#tag(a:dbuf)
  if target !=# ''
    call resource#open(target)
  endif
endfunction
