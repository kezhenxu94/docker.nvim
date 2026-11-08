" The differences between Vim and Neovim: jobs, marks and virtual text (text properties /
" extmarks), the table header (WinBar menu / 'winbar'), floating windows and terminals.

let s:nvim = has('nvim')

" ------------------------------------------------------------------ jobs

let s:next_job = 0

" Run cmd (a list, no shell). opts.on_out(chunk) receives stdout as it arrives (then it is not
" kept), opts.on_exit(code, stdout, stderr) is called once the job is done, unless it was killed.
" Returns the job, {} when it cannot be started.
function! docker#compat#job_start(cmd, opts) abort
  let s:next_job += 1
  let job = {'id': s:next_job, 'done': 0, 'killed': 0, 'out': '', 'err': '', 'opts': a:opts,
        \ 'exited': 0, 'closed': 0, 'code': -1}
  if s:nvim
    try
      let job.job = jobstart(a:cmd, {
            \ 'stdin': 'null',
            \ 'on_stdout': {_, data, __ -> s:on_out(job, join(data, "\n"))},
            \ 'on_stderr': {_, data, __ -> s:on_err(job, join(data, "\n"))},
            \ 'on_exit': {_, code, __ -> s:on_exit(job, {'code': code, 'exited': 1, 'closed': 1})}})
    catch
      return {}
    endtry
    return job.job > 0 ? job : {}
  endif
  " exit_cb and close_cb arrive in either order
  let job.job = job_start(a:cmd, {
        \ 'in_io': 'null', 'mode': 'raw',
        \ 'out_cb': {_, data -> s:on_out(job, data)},
        \ 'err_cb': {_, data -> s:on_err(job, data)},
        \ 'exit_cb': {_, code -> s:on_exit(job, {'code': code, 'exited': 1})},
        \ 'close_cb': {_ -> s:on_exit(job, {'closed': 1})}})
  return job_status(job.job) ==# 'fail' ? {} : job
endfunction

function! s:on_out(job, data) abort
  if has_key(a:job.opts, 'on_out')
    if !a:job.killed && a:data !=# ''
      call a:job.opts.on_out(a:data)
    endif
  else
    let a:job.out .= a:data
  endif
endfunction

function! s:on_err(job, data) abort
  let a:job.err .= a:data
endfunction

function! s:on_exit(job, update) abort
  call extend(a:job, a:update)
  if a:job.done || !a:job.exited || !a:job.closed
    return
  endif
  let a:job.done = 1
  if !a:job.killed && has_key(a:job.opts, 'on_exit')
    call a:job.opts.on_exit(a:job.code, a:job.out, a:job.err)
  endif
endfunction

function! docker#compat#job_running(job) abort
  return !empty(a:job) && !a:job.done
endfunction

" Kill a job if it is still running, its callbacks are not called anymore.
function! docker#compat#job_kill(job) abort
  if !docker#compat#job_running(a:job)
    return
  endif
  let a:job.killed = 1
  if s:nvim
    silent! call jobstop(a:job.job)
  else
    call job_stop(a:job.job, 'term')
  endif
endfunction

" ------------------------------------------------------------------ marks and virtual text

" Kinds of marks: 'row' (the rows of a table, they are gone once their line is deleted), 'cell'
" (the cells, text typed at either end stays in the cell), 'changed' (rows a reload changed),
" 'pending' (deleted rows), 'status' and 'logstatus' (virtual text after a line).
let s:kinds = ['row', 'cell', 'changed', 'pending', 'status', 'logstatus']

if s:nvim
  let s:ns = {}
  for s:kind in s:kinds
    let s:ns[s:kind] = nvim_create_namespace('docker_' . s:kind)
  endfor
  unlet s:kind
else
  " Text properties are typed, a type has one highlight: types are created per highlight
  function! s:type(kind, hl) abort
    let name = 'docker_' . a:kind . (empty(a:hl) ? '' : '_' . a:hl)
    if empty(prop_type_get(name))
      let props = {'priority': get({'row': 10, 'cell': 20, 'changed': 30}, a:kind, 0)}
      if !empty(a:hl)
        let props.highlight = a:hl
      endif
      if a:kind ==# 'cell'
        let props.start_incl = 1
        let props.end_incl = 1
      endif
      call prop_type_add(name, props)
    endif
    return name
  endfunction

  function! s:types(kind) abort
    return filter(prop_type_list(), {_, name -> name =~# '^docker_' . a:kind . '\(_\|$\)'})
  endfunction
endif

" Mark the row at lnum, highlighted with DockerBody.
function! docker#compat#mark_row(buf, lnum, id) abort
  if s:nvim
    call nvim_buf_set_extmark(a:buf, s:ns.row, a:lnum - 1, 0,
          \ {'id': a:id, 'invalidate': v:true, 'line_hl_group': 'DockerBody'})
  else
    call prop_add(a:lnum, 1, {'bufnr': a:buf, 'id': a:id, 'type': s:type('row', 'DockerBody'),
          \ 'length': len(getbufline(a:buf, a:lnum)[0])})
  endif
endfunction

" Mark the cell [col, end_col) (0-indexed bytes) of the row at lnum.
function! docker#compat#mark_cell(buf, lnum, col, end_col, id, hl) abort
  if s:nvim
    let opts = {'id': a:id, 'end_col': a:end_col, 'invalidate': v:true,
          \ 'right_gravity': v:false, 'end_right_gravity': v:true}
    if !empty(a:hl)
      let opts.hl_group = a:hl
    endif
    call nvim_buf_set_extmark(a:buf, s:ns.cell, a:lnum - 1, a:col, opts)
  else
    call prop_add(a:lnum, a:col + 1, {'bufnr': a:buf, 'id': a:id, 'type': s:type('cell', a:hl),
          \ 'length': a:end_col - a:col})
  endif
endfunction

" The marks of a kind still in the buffer: [{id, lnum, col, end_col}], col 0-indexed.
function! docker#compat#marks(buf, kind) abort
  let marks = []
  if s:nvim
    for [id, row, col, details] in nvim_buf_get_extmarks(a:buf, s:ns[a:kind], 0, -1, {'details': v:true})
      if !get(details, 'invalid', v:false)
        call add(marks, {'id': id, 'lnum': row + 1, 'col': col, 'end_col': get(details, 'end_col', col)})
      endif
    endfor
    return marks
  endif
  let types = s:types(a:kind)
  if empty(types)
    return []
  endif
  for prop in prop_list(1, {'bufnr': a:buf, 'end_lnum': -1, 'types': types})
    call add(marks, {'id': get(prop, 'id', 0), 'lnum': prop.lnum, 'col': prop.col - 1,
          \ 'end_col': prop.col - 1 + get(prop, 'length', 0)})
  endfor
  return marks
endfunction

function! docker#compat#clear(buf, kind) abort
  if !bufloaded(a:buf)
    return
  endif
  if s:nvim
    call nvim_buf_clear_namespace(a:buf, s:ns[a:kind], 0, -1)
    return
  endif
  let types = s:types(a:kind)
  if !empty(types)
    call prop_remove({'bufnr': a:buf, 'types': types, 'all': 1})
  endif
endfunction

" Highlight the row at lnum with DockerChanged.
function! docker#compat#mark_changed(buf, lnum) abort
  if s:nvim
    call nvim_buf_set_extmark(a:buf, s:ns.changed, a:lnum - 1, 0,
          \ {'line_hl_group': 'DockerChanged', 'priority': 200})
  else
    call prop_add(a:lnum, 1, {'bufnr': a:buf, 'type': s:type('changed', 'DockerChanged'),
          \ 'length': len(getbufline(a:buf, a:lnum)[0])})
  endif
endfunction

" Show text after the line lnum, replacing the text of the same kind, '' to clear it.
function! docker#compat#virt_text(buf, kind, lnum, text, hl) abort
  call docker#compat#clear(a:buf, a:kind)
  if a:text ==# '' || !bufloaded(a:buf)
    return
  endif
  if s:nvim
    call nvim_buf_set_extmark(a:buf, s:ns[a:kind], a:lnum - 1, 0,
          \ {'virt_text': [[a:text, a:hl]], 'virt_text_pos': 'eol'})
  else
    call prop_add(a:lnum, 0, {'bufnr': a:buf, 'type': s:type(a:kind, a:hl), 'text': a:text,
          \ 'text_padding_left': 1})
  endif
endfunction

" The text shown by virt_text(), '' if none.
function! docker#compat#get_virt_text(buf, kind) abort
  if s:nvim
    let marks = nvim_buf_get_extmarks(a:buf, s:ns[a:kind], 0, -1, {'details': v:true})
    return empty(marks) ? '' : marks[0][3].virt_text[0][0]
  endif
  let types = s:types(a:kind)
  let props = empty(types) ? [] : prop_list(1, {'bufnr': a:buf, 'end_lnum': -1, 'types': types})
  return empty(props) ? '' : props[0].text
endfunction

" Show lines highlighted with DockerDeleted above (or below) the line lnum.
function! docker#compat#virt_lines(buf, lnum, lines, above) abort
  if s:nvim
    call nvim_buf_set_extmark(a:buf, s:ns.pending, a:lnum - 1, 0, {
          \ 'virt_lines': map(copy(a:lines), {_, line -> [[line, 'DockerDeleted']]}),
          \ 'virt_lines_above': a:above ? v:true : v:false})
    " Lines above the first line are only shown as filler of the top line
    if a:above && a:lnum == 1
      for win in win_findbuf(a:buf)
        call win_execute(win, 'if line("w0") == 1 | call winrestview({"topfill": ' . len(a:lines) . '}) | endif')
      endfor
    endif
    return
  endif
  for line in a:lines
    call prop_add(a:lnum, 0, {'bufnr': a:buf, 'type': s:type('pending', 'DockerDeleted'), 'text': line,
          \ 'text_align': a:above ? 'above' : 'below'})
  endfor
endfunction

" ------------------------------------------------------------------ table header

" Show the table header (see docker#util#header()) at the top of the window.
function! docker#compat#set_header(win) abort
  let header = docker#util#header(a:win)
  if empty(header)
    call docker#compat#clear_header(a:win)
    return
  endif
  call setwinvar(a:win, 'docker_header', 1)
  if s:nvim
    " Evaluated when drawn, as the width of the sign column is only known then
    call setwinvar(a:win, '&winbar', '%!docker#compat#winbar()')
    redrawstatus!
    return
  endif
  if !has('menu')
    return
  endif
  " The WinBar menu, its item is padded by a space, after a space
  let item = repeat(' ', max([header.textoff - 2, 0])) . header.header . header.indicator
  call win_execute(a:win, ['silent! aunmenu WinBar', 'nnoremenu <silent> 1.10 WinBar.'
        \ . escape(substitute(item, '&', '&&', 'g'), ' .\|"<') . ' <Nop>'])
endfunction

" The 'winbar' of a window showing a table, Neovim only.
function! docker#compat#winbar(...) abort
  let header = docker#util#header(a:0 ? a:1 : g:statusline_winid)
  if empty(header)
    return ''
  endif
  let Escape = {text -> substitute(text, '%', '%%', 'g')}
  return printf('%s%%#DockerHeader#%s%%=%%#Comment#%s',
        \ repeat(' ', header.textoff), Escape(header.header), Escape(header.indicator))
endfunction

" Remove the header of a window, which now shows another buffer.
function! docker#compat#clear_header(win) abort
  if !getwinvar(a:win, 'docker_header', 0)
    return
  endif
  call win_execute(a:win, 'unlet w:docker_header')
  if s:nvim
    call win_execute(a:win, 'setlocal winbar<')
  elseif has('menu')
    call win_execute(a:win, 'silent! aunmenu WinBar')
  endif
endfunction

" The text of the header of a window.
function! docker#compat#get_header(win) abort
  if s:nvim
    return getwinvar(a:win, '&winbar') ==# '' ? '' : docker#compat#winbar(a:win)
  endif
  let s:menu = {}
  call win_execute(a:win, 'let s:menu = menu_info("WinBar")')
  return join(get(s:menu, 'submenus', []), ' ')
endfunction

" ------------------------------------------------------------------ windows

" Show lines in a window over the editor, closed by q, <Esc> or g?.
function! docker#compat#float(lines, title) abort
  let width = max(map(copy(a:lines), {_, line -> strdisplaywidth(line)}))
  if s:nvim
    let buf = nvim_create_buf(v:false, v:true)
    call setbufline(buf, 1, a:lines)
    call setbufvar(buf, '&modifiable', 0)
    call setbufvar(buf, '&bufhidden', 'wipe')
    let win = nvim_open_win(buf, v:true, {
          \ 'relative': 'editor',
          \ 'width': min([width + 2, &columns - 4]),
          \ 'height': min([len(a:lines), &lines - 4]),
          \ 'row': (&lines - len(a:lines)) / 2,
          \ 'col': (&columns - width) / 2,
          \ 'style': 'minimal', 'border': 'rounded', 'title': a:title, 'title_pos': 'center'})
    for lhs in ['q', '<Esc>', 'g?']
      execute 'nnoremap <buffer> <nowait> <silent>' lhs '<Cmd>close<CR>'
    endfor
    execute 'autocmd WinLeave <buffer> ++once silent! call nvim_win_close(' . win . ', v:true)'
    return win
  endif
  return popup_create(a:lines, {
        \ 'title': a:title, 'border': [], 'padding': [0, 1, 0, 1], 'pos': 'center',
        \ 'maxheight': &lines - 4, 'maxwidth': &columns - 4, 'mapping': 0,
        \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
        \ 'filter': function('s:float_filter')})
endfunction

" Keys go to the popup: q, <Esc> and the ? of g? close it
function! s:float_filter(id, key) abort
  if index(['q', "\<Esc>", '?'], a:key) >= 0
    call popup_close(a:id)
  endif
  return 1
endfunction

" ------------------------------------------------------------------ terminals

" Run cmd in a terminal in the current window, in place of the current buffer, which is named
" name: the terminal buffer takes the name, so that editing it again finds the terminal.
function! docker#compat#term(cmd, name) abort
  if s:nvim
    call jobstart(a:cmd, {'term': v:true})
    setlocal nonumber norelativenumber
    call s:rename(bufnr(), a:name)
    return
  endif
  let buf = bufnr()
  let term = term_start(a:cmd, {'curwin': 1})
  setlocal nonumber norelativenumber
  " The buffer being read cannot be wiped until it is read
  call timer_start(0, {-> s:replace(buf, term, a:name)})
endfunction

function! s:replace(buf, term, name) abort
  execute 'silent! bwipeout!' a:buf
  let win = bufwinid(a:term)
  if win != -1
    call win_execute(win, 'call s:rename(' . a:term . ', ' . string(a:name) . ')')
  endif
endfunction

" :file leaves a buffer with the old name
function! s:rename(buf, name) abort
  let old = bufname(a:buf)
  if old ==# a:name
    return
  endif
  execute 'keepalt file' fnameescape(a:name)
  for info in getbufinfo()
    if info.name ==# fnamemodify(old, ':p') || info.name ==# old
      execute 'silent! bwipeout!' info.bufnr
    endif
  endfor
endfunction

" Start typing in the terminal, Vim starts terminals in Terminal-Job mode.
function! docker#compat#startinsert() abort
  if s:nvim
    startinsert
  endif
endfunction

" ------------------------------------------------------------------ paths

function! docker#compat#state_dir() abort
  if s:nvim
    return stdpath('state')
  endif
  return (empty($XDG_STATE_HOME) ? expand('~/.local/state') : $XDG_STATE_HOME) . '/vim'
endfunction
