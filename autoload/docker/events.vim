" :w on tables: remove the items of the deleted rows.

" The errors of the edited cells, none can be edited.
function! s:cell_edit_errors(dbuf) abort
  let rows = {}
  for mark in docker#compat#marks(a:dbuf.buf, 'row')
    let rows[mark.id] = 1
  endfor
  let cells = {}
  for mark in docker#compat#marks(a:dbuf.buf, 'cell')
    let cells[mark.id] = mark
  endfor

  let errors = []
  " Marks are created in the order of the cells
  for id in sort(map(keys(a:dbuf.cells), 'str2nr(v:val)'), 'n')
    let cell = a:dbuf.cells[id]
    if !has_key(rows, cell.row)
      continue
    endif
    " A cell whose text was deleted may be gone
    let mark = get(cells, id, {})
    let text = empty(mark) ? '' : trim(strpart(getbufline(a:dbuf.buf, mark.lnum)[0], mark.col, mark.end_col - mark.col))
    if text !=# cell.text
      call add(errors, printf('%s of %s %s is not editable', cell.column, cell.item.kind, cell.item.name))
    endif
  endfor
  return errors
endfunction

function! s:title(item) abort
  return printf('%s %s %s', a:item.kind ==# 'compose' ? 'Down' : 'Remove', a:item.kind, get(a:item, 'ref', a:item.name))
endfunction

" Remove the items, then reload the buffer once all are done, failed or not, to show what docker
" has now.
function! s:remove(dbuf, items) abort
  let state = {'remaining': len(a:items)}
  for item in a:items
    call docker#cli#remove(a:dbuf.context, item,
          \ {result, ... -> s:finished(a:dbuf, state, result)},
          \ {err -> s:failed(a:dbuf, state, item, err)})
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

function! s:failed(dbuf, state, item, err) abort
  call docker#util#notify(printf("Failed: %s\n%s", s:title(a:item), a:err), 'error')
endfunction

" Remove the items of the deleted rows, after confirming unless force (:w!).
" Returns whether the buffer was saved and is to be reloaded.
function! docker#events#on_buf_saved(dbuf, force) abort
  let errors = s:cell_edit_errors(a:dbuf)
  if !empty(errors)
    call docker#util#notify(join(errors, "\n"), 'error')
    return 0
  endif

  let rows = {}
  for mark in docker#compat#marks(a:dbuf.buf, 'row')
    let rows[mark.id] = 1
  endfor
  let items = []
  " In the order of the rows
  for id in sort(map(keys(a:dbuf.rows), 'str2nr(v:val)'), 'n')
    let item = a:dbuf.rows[id].item
    " Kinds and image layers cannot be removed
    if !has_key(rows, id) && item.kind !=# 'type' && item.kind !=# 'layer'
      call add(items, item)
    endif
  endfor
  if empty(items)
    return 1
  endif

  if !a:force
    let prompt = printf('Apply the changes (context: %s)?', a:dbuf.context)
    if !docker#util#confirm(join([prompt] + map(copy(items), {_, item -> '  ' . s:title(item)}), "\n"))
      return 0
    endif
  endif
  " Reloaded once removed
  call s:remove(a:dbuf, items)
  return 0
endfunction
