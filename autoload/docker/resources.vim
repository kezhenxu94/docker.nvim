" Lists of resources, and the history of images, as tables.

let s:max_column_width = 99
let s:separator = '  '
" Columns that change on every reload, not worth showing as a change
let s:volatile_columns = ['CREATED']
let s:flash_duration = 1500

" Identity of a row's item that survives reloads, so the cursor can stay on the same row.
" An image with several tags has a row per tag.
function! s:identity(item) abort
  return a:item.kind . '/' . get(a:item, 'ref', a:item.name)
endfunction

" The row mark ids by line number.
function! s:rows_by_lnum(dbuf) abort
  let rows = {}
  for mark in docker#compat#marks(a:dbuf.buf, 'row')
    let rows[mark.lnum] = mark.id
  endfor
  return rows
endfunction

" The item of the row at lnum, {} if none.
function! docker#resources#item_at(dbuf, lnum) abort
  let id = get(s:rows_by_lnum(a:dbuf), a:lnum, 0)
  return has_key(a:dbuf.rows, id) ? a:dbuf.rows[id].item : {}
endfunction

" The items of the rows in [first, last].
function! docker#resources#items_in_rows(dbuf, first, last) abort
  let rows = s:rows_by_lnum(a:dbuf)
  let items = []
  for lnum in range(a:first, a:last)
    if has_key(rows, lnum) && has_key(a:dbuf.rows, rows[lnum])
      call add(items, a:dbuf.rows[rows[lnum]].item)
    endif
  endfor
  return items
endfunction

" Remember the row under the cursor of every window showing the buffer.
function! s:save_cursors(dbuf) abort
  let rows = s:rows_by_lnum(a:dbuf)
  let saved = []
  for win in win_findbuf(a:dbuf.buf)
    let cursor = getcurpos(win)[1:2]
    let id = get(rows, cursor[0], 0)
    call add(saved, {'win': win, 'cursor': cursor,
          \ 'identity': has_key(a:dbuf.rows, id) ? s:identity(a:dbuf.rows[id].item) : ''})
  endfor
  return saved
endfunction

" Move the cursors back to the rows of the same items, or keep the line when the item is gone.
function! s:restore_cursors(saved, formatted_rows) abort
  for entry in a:saved
    let lnum = min([entry.cursor[0], max([len(a:formatted_rows), 1])])
    if entry.identity !=# ''
      for i in range(len(a:formatted_rows))
        if s:identity(a:formatted_rows[i].raw) ==# entry.identity
          let lnum = i + 1
          break
        endif
      endfor
    endif
    call win_execute(entry.win, printf('call cursor(%d, %d)', lnum, entry.cursor[1]))
  endfor
endfunction

function! s:signature(headers, cells) abort
  let values = []
  for i in range(len(a:headers))
    if index(s:volatile_columns, a:headers[i]) < 0
      call add(values, get(a:cells, i, ''))
    endif
  endfor
  return join(values, "\n")
endfunction

" The signatures of the rendered rows by identity, v:null before the first render.
function! s:signatures(dbuf) abort
  if empty(a:dbuf.rows)
    return v:null
  endif
  let result = {}
  for row in values(a:dbuf.rows)
    let result[s:identity(row.item)] = row.signature
  endfor
  return result
endfunction

" Highlight the rows for a moment.
function! s:flash(dbuf, lnums) abort
  if empty(a:lnums)
    return
  endif
  for lnum in a:lnums
    call docker#compat#mark_changed(a:dbuf.buf, lnum)
  endfor
  let a:dbuf.flash_generation += 1
  let generation = a:dbuf.flash_generation
  " A later reload flashes its own rows
  call timer_start(s:flash_duration, {-> a:dbuf.flash_generation == generation
        \ ? docker#compat#clear(a:dbuf.buf, 'changed') : 0})
endfunction

function! docker#resources#load(dbuf) abort
  let formatter = docker#formatters#get(a:dbuf.subresource ==# '' ? a:dbuf.kind : a:dbuf.subresource)
  if empty(formatter)
    call docker#buffer#on_error(a:dbuf, 'Unknown kind: ' . (a:dbuf.subresource ==# '' ? a:dbuf.kind : a:dbuf.subresource))
    return {}
  endif
  if a:dbuf.kind ==# 'types'
    call docker#resources#render(a:dbuf, formatter, [])
    return {}
  endif

  let OnResult = {result, ... -> s:on_result(a:dbuf, formatter, result)}
  let OnError = {err -> docker#buffer#on_error(a:dbuf, err)}
  if a:dbuf.subresource ==# 'history'
    let job = docker#cli#history(a:dbuf.context, a:dbuf.name, OnResult, OnError)
  else
    let job = docker#cli#list(a:dbuf.context, a:dbuf.kind, a:dbuf.params, OnResult, OnError)
  endif
  return docker#buffer#add_job(a:dbuf, job)
endfunction

function! s:on_result(dbuf, formatter, result) abort
  if a:result isnot v:null && bufloaded(a:dbuf.buf)
    call docker#resources#render(a:dbuf, a:formatter, docker#cli#decode(a:result))
  endif
endfunction

" Render the rows of data (the decoded docker output) as a table, keeping the cursors on the same rows.
function! docker#resources#render(dbuf, formatter, data) abort
  let buf = a:dbuf.buf
  " Edits made while a background reload was running win over the reload
  if a:dbuf.silent && getbufvar(buf, '&modified')
    return
  endif
  let headers = a:formatter.headers
  let cursors = s:save_cursors(a:dbuf)
  let previous = s:signatures(a:dbuf)

  for kind in ['row', 'cell', 'pending', 'changed']
    call docker#compat#clear(buf, kind)
  endfor
  call sign_unplace('docker', {'buffer': buf})
  let a:dbuf.rows = {}
  let a:dbuf.cells = {}
  let a:dbuf.diagnostics = {}

  let [header_row, formatted_rows] = docker#resources#format_table(headers, a:formatter.format(a:data))
  let a:dbuf.header_row = header_row

  call docker#buffer#set_lines(a:dbuf, map(copy(formatted_rows), 'v:val.formatted'), 1)
  call s:restore_cursors(cursors, formatted_rows)
  if empty(formatted_rows)
    call docker#buffer#set_status(a:dbuf, get(a:formatter, 'empty', 'Nothing found'), 'Comment')
  endif

  let changed = []
  let cell_id = 0
  for lnum in range(1, len(formatted_rows))
    let row = formatted_rows[lnum - 1]
    call docker#compat#mark_row(buf, lnum, lnum)
    let signature = s:signature(headers, row.cells)
    let a:dbuf.rows[lnum] = {'item': row.raw, 'line': row.formatted, 'signature': signature}
    let identity = s:identity(row.raw)
    if previous isnot v:null && (!has_key(previous, identity) || previous[identity] !=# signature)
      call add(changed, lnum)
    endif

    for i in range(len(row.ranges))
      let [start, end] = row.ranges[i]
      let cell_id += 1
      call docker#compat#mark_cell(buf, lnum, start, end, cell_id, get(row.highlights, headers[i], ''))
      let a:dbuf.cells[cell_id] = {'item': row.raw, 'column': headers[i],
            \ 'text': trim(strpart(row.formatted, start, end - start)), 'row': lnum}
    endfor

    for diagnostic in row.diagnostics
      let sign = diagnostic.severity ==# 'error' ? 'DockerError' : 'DockerWarn'
      let id = sign_place(0, 'docker', sign, buf, {'lnum': lnum})
      let a:dbuf.diagnostics[id] = diagnostic.message
    endfor
  endfor

  " After the signs, which may change the width of the sign column the header is aligned with
  call docker#util#update_header(a:dbuf)
  " Only reloads of a watched list: a reload asked for shows the changes it was asked for
  if a:dbuf.silent
    call s:flash(a:dbuf, changed)
  endif
endfunction

" Show the rows deleted from the buffer, which :w deletes, where they were: above the row that
" followed them, below the last line if none.
function! docker#resources#show_pending(dbuf) abort
  let buf = a:dbuf.buf
  call docker#compat#clear(buf, 'pending')
  let rows = {}
  for mark in docker#compat#marks(buf, 'row')
    let rows[mark.id] = mark.lnum
  endfor

  " Row ids are their line numbers when rendered
  let ids = sort(map(keys(a:dbuf.rows), 'str2nr(v:val)'), 'n')
  let groups = []
  let deleted = []
  for id in ids
    if !has_key(rows, id)
      call add(deleted, a:dbuf.rows[id].line)
    elseif !empty(deleted)
      call add(groups, [rows[id], deleted, 1])
      let deleted = []
    endif
  endfor
  if !empty(deleted)
    call add(groups, [len(getbufline(buf, 1, '$')), deleted, 0])
  endif
  for [lnum, lines, above] in groups
    call docker#compat#virt_lines(buf, lnum, lines, above)
  endfor
endfunction

" The 0-indexed byte range [start, end) of the cells of a row, the formatted line.
function! s:align_row(cells, widths) abort
  let formatted = []
  let ranges = []
  let pos = 0
  for i in range(len(a:widths))
    let width = min([s:max_column_width, a:widths[i]])
    let text = get(a:cells, i, '')
    let text_width = strdisplaywidth(text)
    if text_width > width
      let text = s:truncate(text, width)
      let text_width = strdisplaywidth(text)
    endif
    let text .= repeat(' ', width - text_width)
    call add(formatted, text)
    call add(ranges, [pos, pos + len(text)])
    let pos += len(text) + len(s:separator)
  endfor
  return [join(formatted, s:separator), ranges]
endfunction

" text cut to width display cells, ending with ...
function! s:truncate(text, width) abort
  let result = ''
  for char in split(a:text, '\zs')
    if strdisplaywidth(result . char) > a:width - 3
      break
    endif
    let result .= char
  endfor
  return result . '...'
endfunction

" Align rows ([{row, item, highlights, diagnostics}]) under headers.
" Returns the header row and the rows: {formatted, ranges, cells, highlights, diagnostics, raw}.
function! docker#resources#format_table(headers, rows) abort
  let widths = []
  for i in range(len(a:headers))
    call add(widths, max([len(a:headers[i])] + map(copy(a:rows), {_, row -> strdisplaywidth(get(row.row, i, ''))})))
  endfor

  let formatted_rows = []
  for row in a:rows
    let [formatted, ranges] = s:align_row(row.row, widths)
    call add(formatted_rows, {'formatted': formatted, 'ranges': ranges, 'cells': row.row,
          \ 'highlights': row.highlights, 'diagnostics': row.diagnostics, 'raw': row.item})
  endfor
  return [{'formatted': s:align_row(a:headers, widths)[0], 'raw': a:headers}, formatted_rows]
endfunction
