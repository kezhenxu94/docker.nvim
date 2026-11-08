" The state of docker buffers, by buffer number:
"   buf, context, kind, name, subresource ('' if none), params (the query, the filters of lists),
"   jobs (the jobs running in the buffer by id), loading_job, silent (whether the current load is
"   a background refresh), watch (see docker#refresh), flash_generation, header_row,
"   rows (row mark id -> {item, line, signature}), cells (cell mark id -> {item, column, text, row}),
"   diagnostics (sign id -> message), follow_job (the job following logs).
let s:buffers = {}

call docker#highlights#setup()

function! docker#buffer#get(buf) abort
  return get(s:buffers, a:buf, {})
endfunction

function! docker#buffer#all() abort
  return values(s:buffers)
endfunction

" Parse a buffer name, see docker#util#buf_name() for the format. Throws when it is invalid.
function! docker#buffer#parse_name(name) abort
  let match = matchlist(a:name, '^docker://\([^?]*\)?\=\(.*\)$')
  let segments = split(get(match, 1, ''), '/')
  let query = get(match, 2, '')
  if get(segments, 0, '') !=# 'context' || len(segments) < 3
    throw 'Invalid buffer name format. Expected: docker://context/{context}/{kind}[/{name}[/{subresource}]]'
  endif

  let params = {}
  for param in split(query, '&')
    let [key, value] = matchlist(param, '^\([^=]\+\)=\=\(.*\)$')[1:2]
    let params[key] = value ==# '' || value ==# 'true' ? v:true : value ==# 'false' ? v:false : value
  endfor

  return {
        \ 'context': docker#util#uri_decode(segments[1]),
        \ 'kind': segments[2],
        \ 'name': get(segments, 3, ''),
        \ 'subresource': get(segments, 4, ''),
        \ 'params': params,
        \ }
endfunction

" The name of the buffer a name is an alias of, itself if none: without context/<context>/ it is
" pinned to the current context, so the buffer keeps operating on the same daemon after the
" context is switched; no kind is the kinds, types. Throws without a current context.
function! docker#buffer#canonical_name(name) abort
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
    let context = printf('context/%s/', docker#util#uri_encode(current))
  endif
  return 'docker://' . context . (rest ==# '' ? 'types' : rest)
endfunction

" Tables, as opposed to inspect / logs buffers.
function! docker#buffer#is_table(dbuf) abort
  return a:dbuf.name ==# '' || a:dbuf.subresource ==# 'history'
endfunction

function! s:new(buf) abort
  if has_key(s:buffers, a:buf)
    return s:buffers[a:buf]
  endif
  let dbuf = extend(docker#buffer#parse_name(bufname(a:buf)), {
        \ 'buf': a:buf, 'jobs': {}, 'loading_job': {}, 'silent': 0, 'watch': 0, 'flash_generation': 0,
        \ 'header_row': {}, 'rows': {}, 'cells': {}, 'diagnostics': {}})
  let s:buffers[a:buf] = dbuf
  call docker#buffer#setup(dbuf)
  call docker#keymaps#setup(dbuf)
  return dbuf
endfunction

function! docker#buffer#setup(dbuf) abort
  " Only tables are written (:w deletes the deleted rows). Logs can be edited, e.g. reformatted,
  " the edits never block quitting, :w {file} saves them.
  call setbufvar(a:dbuf.buf, '&buftype', docker#buffer#is_table(a:dbuf) ? 'acwrite' : 'nofile')
  call setbufvar(a:dbuf.buf, '&swapfile', 0)
endfunction

" opts.silent for background refreshes: no loading status, no error notification
function! docker#buffer#load(dbuf, ...) abort
  let opts = get(a:, 1, {})
  " Operations reload their buffer when done, it may have been unloaded or deleted meanwhile
  if !bufloaded(a:dbuf.buf) || get(s:buffers, a:dbuf.buf, {}) isnot a:dbuf
    return
  endif
  if docker#compat#job_running(a:dbuf.loading_job)
    if !get(opts, 'silent', 0)
      call docker#util#notify('The buffer is currently being loaded', 'warn')
    endif
    return
  endif

  let a:dbuf.silent = get(opts, 'silent', 0)
  if getbufline(a:dbuf.buf, 1, '$') == ['']
    call docker#buffer#set_status(a:dbuf, 'Loading…', 'Comment')
  endif
  let a:dbuf.loading_job = s:render(a:dbuf)
endfunction

function! s:render(dbuf) abort
  if docker#buffer#is_table(a:dbuf)
    return docker#resources#load(a:dbuf)
  elseif a:dbuf.subresource ==# ''
    return docker#inspect#load(a:dbuf)
  elseif a:dbuf.subresource ==# 'logs'
    return docker#logs#load(a:dbuf)
  endif
  call docker#buffer#on_error(a:dbuf, 'Unknown subresource: ' . a:dbuf.subresource)
  return {}
endfunction

" Kill the jobs loading the buffer, their output has nowhere to go once it is unloaded.
function! docker#buffer#stop_jobs(dbuf) abort
  call docker#compat#job_kill(a:dbuf.loading_job)
  let a:dbuf.loading_job = {}
  for job in values(a:dbuf.jobs)
    call docker#compat#job_kill(job)
  endfor
  let a:dbuf.jobs = {}
endfunction

function! docker#buffer#add_job(dbuf, job) abort
  if !empty(a:job)
    let a:dbuf.jobs[a:job.id] = a:job
  endif
  return a:job
endfunction

" Show a status after the first line, '' to clear it.
function! docker#buffer#set_status(dbuf, text, ...) abort
  call docker#compat#virt_text(a:dbuf.buf, 'status', 1, a:text, get(a:, 1, 'Comment'))
endfunction

" The error of a docker call loading the buffer.
function! docker#buffer#on_error(dbuf, err) abort
  let message = get(split(a:err ==# '' ? 'docker failed' : a:err, "\n"), 0, '')
  call docker#buffer#set_status(a:dbuf, '✗ ' . message, 'ErrorMsg')
  if !a:dbuf.silent
    call docker#util#notify(a:err, 'error')
  endif
endfunction

" Replace the buffer content with lines, keeping it unmodified.
function! docker#buffer#set_lines(dbuf, lines, modifiable) abort
  let buf = a:dbuf.buf
  call docker#buffer#set_status(a:dbuf, '')
  call setbufvar(buf, '&modifiable', 1)
  let line_count = len(getbufline(buf, 1, "$"))
  if line_count > len(a:lines)
    silent call deletebufline(buf, max([len(a:lines), 1]), '$')
  endif
  call setbufline(buf, 1, empty(a:lines) ? [''] : a:lines)
  call setbufvar(buf, '&modifiable', a:modifiable)
  call setbufvar(buf, '&modified', 0)
endfunction

" ------------------------------------------------------------------ autocmds

function! docker#buffer#on_read(buf) abort
  let name = bufname(a:buf)
  try
    let canonical = docker#buffer#canonical_name(name)
  catch
    call docker#util#notify(v:exception, 'error')
    return
  endtry
  " The name is an alias: edit the canonical buffer instead, the alias is wiped, it never becomes
  " the alternate file or a jump.
  if canonical !=# name
    let buf = bufadd(canonical)
    call setbufvar(buf, '&buflisted', 1)
    execute 'keepalt keepjumps buffer' buf
    call timer_start(0, {-> execute('silent! bwipeout! ' . a:buf)})
    return
  endif

  try
    let parts = docker#buffer#parse_name(name)
  catch
    call docker#util#notify(v:exception, 'error')
    return
  endtry
  if parts.subresource ==# 'exec'
    call docker#exec#start(name, parts)
    return
  endif
  call docker#buffer#load(s:new(a:buf))
endfunction

" An unloaded buffer (:bunload, leaving it with 'nohidden', :e) keeps its state, e.g. watching, for
" when it is loaded again, a deleted one (:bdelete, :bwipeout) starts over.
function! docker#buffer#on_unload(buf) abort
  if has_key(s:buffers, a:buf)
    call docker#buffer#stop_jobs(s:buffers[a:buf])
  endif
endfunction

function! docker#buffer#on_delete(buf) abort
  if has_key(s:buffers, a:buf)
    call docker#buffer#stop_jobs(remove(s:buffers, a:buf))
  endif
endfunction

function! docker#buffer#on_write(buf, force) abort
  let dbuf = docker#buffer#get(a:buf)
  if empty(dbuf)
    return
  endif
  if docker#events#on_buf_saved(dbuf, a:force)
    call docker#buffer#load(dbuf)
  endif
endfunction

function! docker#buffer#on_text_changed(buf) abort
  let dbuf = docker#buffer#get(a:buf)
  if !empty(dbuf) && !empty(dbuf.rows)
    call docker#resources#show_pending(dbuf)
  endif
endfunction

function! docker#buffer#on_win_enter(buf) abort
  let dbuf = docker#buffer#get(a:buf)
  if empty(dbuf)
    " A window that showed a table shows another buffer
    call docker#compat#clear_header(win_getid())
    return
  endif
  " Wrapped rows break the table layout and its alignment with the header
  if docker#buffer#is_table(dbuf)
    setlocal nowrap
  endif
  call docker#util#update_header(dbuf)
endfunction

function! docker#buffer#on_scroll() abort
  let dbuf = docker#buffer#get(bufnr())
  if !empty(dbuf)
    call docker#util#update_header(dbuf)
  endif
endfunction

function! docker#buffer#stop_all() abort
  for dbuf in values(s:buffers)
    call docker#buffer#stop_jobs(dbuf)
  endfor
endfunction
