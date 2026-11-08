" The logs of a container or a compose project.
function! docker#logs#load(dbuf) abort
  if a:dbuf.kind !=# 'containers' && a:dbuf.kind !=# 'compose'
    call docker#buffer#on_error(a:dbuf, 'Logs are only available for containers and compose projects')
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

  let job = docker#cli#logs(a:dbuf.context, a:dbuf.kind, a:dbuf.name, opts,
        \ {result -> s:on_result(a:dbuf, opts.follow, result)},
        \ {err -> docker#buffer#on_error(a:dbuf, err)})
  if empty(job)
    return {}
  endif
  call docker#buffer#add_job(a:dbuf, job)
  if opts.follow
    let a:dbuf.follow_job = job
    execute 'nnoremap <buffer> <silent> <C-c> <Cmd>call docker#logs#stop(' . a:dbuf.buf . ')<CR>'
  endif
  return job
endfunction

function! s:on_result(dbuf, follow, result) abort
  let buf = a:dbuf.buf
  if !bufloaded(buf)
    return
  endif
  call docker#buffer#setup(a:dbuf)

  let lines = split(a:result, "\n", 1)
  if !a:follow
    call docker#buffer#set_lines(a:dbuf, lines, 1)
    return
  endif

  call docker#buffer#set_status(a:dbuf, '')
  call setbufvar(buf, '&modifiable', 1)
  " Replace the trailing placeholder line, then add a new one for the status
  let start = len(getbufline(buf, 1, '$'))
  " Windows at the end keep showing the new lines, like tail -f
  let at_end = filter(win_findbuf(buf), {_, win -> getcurpos(win)[1] >= start - 1})
  call setbufline(buf, start, lines)
  call appendbufline(buf, '$', '')
  let max_lines = docker#util#config('logs_max_lines')
  let excess = len(getbufline(buf, 1, '$')) - 1 - max_lines
  if max_lines >= 0 && excess > 0
    silent call deletebufline(buf, 1, excess)
  endif
  call s:set_status(a:dbuf, 'Waiting for new logs... (Ctrl+C to stop)')
  for win in at_end
    call win_execute(win, 'call cursor(line("$"), 1)')
  endfor
endfunction

function! s:set_status(dbuf, text) abort
  call docker#compat#virt_text(a:dbuf.buf, 'logstatus', len(getbufline(a:dbuf.buf, 1, '$')), a:text, 'Comment')
endfunction

" Stop following the logs.
function! docker#logs#stop(buf) abort
  let dbuf = docker#buffer#get(a:buf)
  let job = get(dbuf, 'follow_job', {})
  if empty(job) || !has_key(dbuf.jobs, job.id)
    return
  endif
  call docker#compat#job_kill(job)
  call remove(dbuf.jobs, job.id)
  call s:set_status(dbuf, 'Stopped following logs, to restart, re-edit this buffer with `:e`')
endfunction
