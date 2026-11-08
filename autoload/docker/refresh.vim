" Opt-in periodic reload of resource lists ("watch"), toggled per buffer.

let s:timer = -1

function! s:should_refresh(dbuf) abort
  let buf = a:dbuf.buf
  if !a:dbuf.watch || !bufloaded(buf) || getbufvar(buf, '&modified')
    return 0
  endif
  if docker#compat#job_running(a:dbuf.loading_job) || empty(win_findbuf(buf))
    return 0
  endif
  " Do not move lines under a visual selection or a pending operator
  return bufnr() != buf || mode() ==# 'n'
endfunction

function! s:tick(...) abort
  let watching = 0
  for dbuf in docker#buffer#all()
    let watching = watching || dbuf.watch
    if s:should_refresh(dbuf)
      call docker#buffer#load(dbuf, {'silent': 1})
    endif
  endfor
  if !watching
    call docker#refresh#stop()
  endif
endfunction

" The interval in milliseconds, 0 when disabled.
function! docker#refresh#interval() abort
  let interval = docker#util#config('refresh_interval')
  return interval is v:false ? 0 : interval
endfunction

function! s:start() abort
  let interval = docker#refresh#interval()
  if s:timer != -1 || interval <= 0
    return
  endif
  let s:timer = timer_start(interval, function('s:tick'), {'repeat': -1})
endfunction

function! docker#refresh#stop() abort
  if s:timer != -1
    call timer_stop(s:timer)
    let s:timer = -1
  endif
endfunction

" Toggle watching the buffer.
function! docker#refresh#toggle(dbuf) abort
  if !docker#buffer#is_table(a:dbuf)
    call docker#util#notify('Only resource lists can be watched', 'warn')
    return
  endif
  if docker#refresh#interval() <= 0
    call docker#util#notify('Watching is disabled, set g:docker_refresh_interval to enable it', 'warn')
    return
  endif
  let a:dbuf.watch = !a:dbuf.watch
  if a:dbuf.watch
    call s:start()
  endif
  call docker#util#update_header(a:dbuf)
endfunction
