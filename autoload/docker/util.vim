" Configuration, messages, prompts and buffer names.

let s:defaults = {
      \ 'keymaps': {
      \   'drill_down': '<CR>',
      \   'inspect': 'gd',
      \   'parent': '-',
      \   'refresh': 'R',
      \   'watch': 'gw',
      \   'show_logs': 'gl',
      \   'follow_logs': 'gL',
      \   'exec': 'gs',
      \   'operations': 'gra',
      \   'help': 'g?',
      \ },
      \ 'refresh_interval': 10000,
      \ 'exec_command': 'sh',
      \ 'logs_tail': 1000,
      \ 'logs_max_lines': 10000,
      \ 'highlights': {},
      \ }

" The value of g:docker_{name}, the keymaps are merged with the defaults.
function! docker#util#config(name) abort
  let value = get(g:, 'docker_' . a:name, s:defaults[a:name])
  if a:name ==# 'keymaps'
    return extend(copy(s:defaults.keymaps), value)
  endif
  return value
endfunction

" level: 'error', 'warn' or 'info'
function! docker#util#notify(msg, ...) abort
  let level = get(a:, 1, 'info')
  execute 'echohl' get({'error': 'ErrorMsg', 'warn': 'WarningMsg'}, level, 'None')
  for line in split(a:msg, "\n")
    echomsg line
  endfor
  echohl None
endfunction

" Pick one of items (strings), returns its index, -1 if none.
function! docker#util#select(items, prompt) abort
  let choices = split(a:prompt, "\n")
  call extend(choices, map(copy(a:items), {i, item -> printf('%d: %s', i + 1, item)}))
  let choice = inputlist(choices)
  return choice >= 1 && choice <= len(a:items) ? choice - 1 : -1
endfunction

function! docker#util#confirm(prompt) abort
  return docker#util#select(['Yes', 'No'], a:prompt) == 0
endfunction

" rfc2396: everything but alphanumerics and -_.!~*'() is encoded, byte by byte
function! docker#util#uri_encode(text) abort
  return substitute(a:text, "[^A-Za-z0-9_.!~*'()-]",
        \ '\=join(map(range(len(submatch(0))), {_, i -> printf("%%%02x", char2nr(submatch(0)[i]))}), "")', 'g')
endfunction

function! docker#util#uri_decode(text) abort
  return substitute(a:text, '%\(\x\x\)', '\=eval(''"\x'' . submatch(1) . ''"'')', 'g')
endfunction

" docker://[context/<context>/]<kind>[/<name>[/<subresource>]][?<params>]
" Without a context the buffer is pinned to the current context when it is opened.
" opts: {context, kind, name, subresource, params}, all optional but kind
function! docker#util#buf_name(opts) abort
  let parts = ['docker:/']
  if get(a:opts, 'context', '') !=# ''
    " Encoded as context names may contain / and :
    call extend(parts, ['context', docker#util#uri_encode(a:opts.context)])
  endif
  call add(parts, a:opts.kind)
  if get(a:opts, 'name', '') !=# ''
    call add(parts, a:opts.name)
    if get(a:opts, 'subresource', '') !=# ''
      call add(parts, a:opts.subresource)
    endif
  endif
  let name = join(parts, '/')
  let params = get(a:opts, 'params', {})
  let query = sort(map(items(params), {_, kv -> kv[0] . '=' . docker#util#param_string(kv[1])}))
  return empty(query) ? name : name . '?' . join(query, '&')
endfunction

function! docker#util#param_string(value) abort
  if a:value is v:true || a:value is v:false
    return a:value ? 'true' : 'false'
  endif
  return a:value
endfunction

" Open (or switch to) the buffer for the given name parts.
function! docker#util#open(opts) abort
  " Escaped as % (from the encoded context) and # are expanded by :edit
  execute 'edit' fnameescape(docker#util#buf_name(a:opts))
endfunction

" The table header of the buffer of a window, aligned with its number column and horizontal
" scroll: {textoff, header, indicator}, {} if none.
function! docker#util#header(win) abort
  let dbuf = docker#buffer#get(winbufnr(a:win))
  if empty(dbuf) || empty(dbuf.header_row)
    return {}
  endif
  let info = getwininfo(a:win)[0]
  let indicator = ''
  if dbuf.watch
    let indicator = printf(' ⟳ %ss ', substitute(printf('%g', docker#refresh#interval() / 1000.0), '\.0$', '', ''))
  endif
  let width = info.width - info.textoff - strdisplaywidth(indicator)
  return {'textoff': info.textoff, 'indicator': indicator,
        \ 'header': strpart(dbuf.header_row.formatted, s:leftcol(a:win, info), max([width, 0]))}
endfunction

" getwininfo() has leftcol since Vim 9.1.0888
function! s:leftcol(win, info) abort
  if has_key(a:info, 'leftcol')
    return a:info.leftcol
  endif
  let s:view = {}
  call win_execute(a:win, 'let s:view = winsaveview()')
  return s:view.leftcol
endfunction

" Show the table header in the windows showing the buffer.
function! docker#util#update_header(dbuf) abort
  for win in win_findbuf(a:dbuf.buf)
    call docker#compat#set_header(win)
  endfor
endfunction
