" Turn the decoded docker output into table rows, by buffer kind or subresource:
" {headers, empty (status without rows), format(data) -> rows}.
" A row: {row: cells, item, highlights: {header: group}, diagnostics: [{message, severity}]}.
" An item is the decoded docker output of a row with kind (e.g. container, image, type), name (how
" buffers and docker commands refer to it) and, for images, ref (removed by it, the ID if untagged).

" A string field, '' if missing or null
function! s:str(dict, key) abort
  let value = get(a:dict, a:key, '')
  return value is v:null ? '' : type(value) == v:t_string ? value : string(value)
endfunction

function! s:item(data, kind, name, ...) abort
  return extend(copy(a:data), extend({'kind': a:kind, 'name': a:name}, get(a:, 1, {})))
endfunction

" ------------------------------------------------------------------ containers

" A label of the labels of docker ps (key=value comma separated), '' if none.
function! docker#formatters#label(labels, key) abort
  return matchstr(',' . a:labels, '\V,' . escape(a:key, '\') . '=\zs\[^,]\*')
endfunction

" The highlight of the STATUS and the diagnostics of a container.
function! s:container_status(container) abort
  let state = s:str(a:container, 'State')
  let text = s:str(a:container, 'Status')
  if state ==# 'running'
    if stridx(text, '(unhealthy)') >= 0
      return ['DockerFailed', [{'message': 'The container is unhealthy', 'severity': 'error'}]]
    elseif stridx(text, '(health: starting)') >= 0
      return ['DockerPending', []]
    endif
    return ['DockerRunning', []]
  elseif state ==# 'exited'
    let code = matchstr(text, '^Exited (\zs-\?\d\+\ze)')
    if code !=# '' && str2nr(code) != 0
      return ['DockerFailed', [{'message': printf('Exited with code %d', str2nr(code)), 'severity': 'error'}]]
    endif
    return ['DockerSucceeded', []]
  elseif state ==# 'restarting'
    return ['DockerPending', [{'message': 'The container is restarting', 'severity': 'warn'}]]
  elseif state ==# 'dead'
    return ['DockerFailed', [{'message': 'The container is dead', 'severity': 'error'}]]
  endif
  " created, paused, removing
  return ['DockerPending', []]
endfunction

function! s:containers(containers) abort
  let rows = []
  for container in a:containers
    let [highlight, diagnostics] = s:container_status(container)
    call add(rows, {
          \ 'row': [s:str(container, 'Names'), s:str(container, 'Image'), s:str(container, 'Status'),
          \   s:str(container, 'Ports'), docker#formatters#label(s:str(container, 'Labels'), 'com.docker.compose.project'),
          \   s:str(container, 'RunningFor'), s:str(container, 'ID')],
          \ 'highlights': {'STATUS': highlight},
          \ 'diagnostics': diagnostics,
          \ 'item': s:item(container, 'container', s:str(container, 'Names')),
          \ })
  endfor
  return rows
endfunction

" ------------------------------------------------------------------ images

function! s:images(images) abort
  let rows = []
  for image in a:images
    let tagged = s:str(image, 'Repository') !=# '<none>' && s:str(image, 'Tag') !=# '<none>'
    let id = s:str(image, 'ID')
    call add(rows, {
          \ 'row': [s:str(image, 'Repository'), s:str(image, 'Tag'), id, s:str(image, 'CreatedSince'), s:str(image, 'Size')],
          \ 'highlights': tagged ? {} : {'REPOSITORY': 'DockerSucceeded', 'TAG': 'DockerSucceeded'},
          \ 'diagnostics': [],
          \ 'item': s:item(image, 'image', id,
          \   {'ref': tagged ? s:str(image, 'Repository') . ':' . s:str(image, 'Tag') : id}),
          \ })
  endfor
  return rows
endfunction

" ------------------------------------------------------------------ history

" The layers of an image, docker history
function! s:history(layers) abort
  let rows = []
  for i in range(len(a:layers))
    let layer = a:layers[i]
    call add(rows, {
          \ 'row': [s:str(layer, 'CreatedSince'), s:str(layer, 'CreatedBy'), s:str(layer, 'Size'), s:str(layer, 'Comment')],
          \ 'highlights': {},
          \ 'diagnostics': [],
          \ 'item': s:item(layer, 'layer', printf('%d:%s', i + 1, s:str(layer, 'ID'))),
          \ })
  endfor
  return rows
endfunction

" ------------------------------------------------------------------ volumes, networks

function! s:volumes(volumes) abort
  return map(copy(a:volumes), {_, volume -> {
        \ 'row': [s:str(volume, 'Name'), s:str(volume, 'Driver'), s:str(volume, 'Scope'), s:str(volume, 'Mountpoint')],
        \ 'highlights': {},
        \ 'diagnostics': [],
        \ 'item': s:item(volume, 'volume', s:str(volume, 'Name')),
        \ }})
endfunction

function! s:networks(networks) abort
  return map(copy(a:networks), {_, network -> {
        \ 'row': [s:str(network, 'Name'), s:str(network, 'ID'), s:str(network, 'Driver'), s:str(network, 'Scope')],
        \ 'highlights': {},
        \ 'diagnostics': [],
        \ 'item': s:item(network, 'network', s:str(network, 'Name')),
        \ }})
endfunction

" ------------------------------------------------------------------ compose

" The highlight of a project status, e.g. running(2), exited(1), running(1), exited(2)
function! s:compose_highlight(status) abort
  if stridx(a:status, ',') >= 0 || stridx(a:status, 'restarting') >= 0
    return 'DockerPending'
  elseif a:status =~# '^running'
    return 'DockerRunning'
  endif
  return 'DockerSucceeded'
endfunction

" The compose projects, docker compose ls --all
function! s:compose(projects) abort
  return map(copy(a:projects), {_, project -> {
        \ 'row': [s:str(project, 'Name'), s:str(project, 'Status'), s:str(project, 'ConfigFiles')],
        \ 'highlights': {'STATUS': s:compose_highlight(s:str(project, 'Status'))},
        \ 'diagnostics': [],
        \ 'item': s:item(project, 'compose', s:str(project, 'Name')),
        \ }})
endfunction

" ------------------------------------------------------------------ types

let s:descriptions = {
      \ 'containers': 'Containers, running or not (docker ps --all)',
      \ 'images': 'Images (docker images)',
      \ 'volumes': 'Volumes (docker volume ls)',
      \ 'networks': 'Networks (docker network ls)',
      \ 'compose': 'Compose projects (docker compose ls --all)',
      \ }

" The kinds docker.nvim lists, rows open their list
function! s:types(_) abort
  return map(docker#cli#kinds(), {_, kind -> {
        \ 'row': [kind, get(s:descriptions, kind, '')],
        \ 'highlights': {},
        \ 'diagnostics': [],
        \ 'item': {'kind': 'type', 'name': kind},
        \ }})
endfunction

let s:formatters = {
      \ 'types': {'headers': ['NAME', 'DESCRIPTION'], 'format': function('s:types')},
      \ 'containers': {'headers': ['NAME', 'IMAGE', 'STATUS', 'PORTS', 'PROJECT', 'CREATED', 'ID'],
      \   'empty': 'No containers found', 'format': function('s:containers')},
      \ 'images': {'headers': ['REPOSITORY', 'TAG', 'ID', 'CREATED', 'SIZE'],
      \   'empty': 'No images found', 'format': function('s:images')},
      \ 'history': {'headers': ['CREATED', 'CREATED BY', 'SIZE', 'COMMENT'], 'format': function('s:history')},
      \ 'volumes': {'headers': ['NAME', 'DRIVER', 'SCOPE', 'MOUNTPOINT'],
      \   'empty': 'No volumes found', 'format': function('s:volumes')},
      \ 'networks': {'headers': ['NAME', 'ID', 'DRIVER', 'SCOPE'],
      \   'empty': 'No networks found', 'format': function('s:networks')},
      \ 'compose': {'headers': ['NAME', 'STATUS', 'CONFIG FILES'],
      \   'empty': 'No compose projects found', 'format': function('s:compose')},
      \ }

" The formatter of a kind or subresource, {} if none.
function! docker#formatters#get(kind) abort
  return get(s:formatters, a:kind, {})
endfunction
