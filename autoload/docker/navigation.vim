" Jumps between buffers: the parent buffer and what the cell under the cursor refers to.

" The buffer one level up: subresource / resource -> its list -> the unfiltered list -> the kinds,
" '' if none.
function! docker#navigation#parent_name(dbuf) abort
  if a:dbuf.name !=# ''
    return docker#util#buf_name({'context': a:dbuf.context, 'kind': a:dbuf.kind})
  endif
  if !empty(a:dbuf.params)
    " The containers of a compose project come from the projects
    let kind = a:dbuf.kind ==# 'containers' && has_key(a:dbuf.params, 'project') ? 'compose' : a:dbuf.kind
    return docker#util#buf_name({'context': a:dbuf.context, 'kind': kind})
  endif
  if a:dbuf.kind !=# 'types'
    return docker#util#buf_name({'context': a:dbuf.context, 'kind': 'types'})
  endif
  return ''
endfunction

" The cell at (lnum, col) (col 0-indexed): {item, column, text}, or just the row's {item} between
" cells, {} if none.
function! s:cell_at(dbuf, lnum, col) abort
  for mark in docker#compat#marks(a:dbuf.buf, 'cell')
    if mark.lnum == a:lnum && mark.col <= a:col && a:col < mark.end_col && has_key(a:dbuf.cells, mark.id)
      return a:dbuf.cells[mark.id]
    endif
  endfor
  let item = docker#resources#item_at(a:dbuf, a:lnum)
  return empty(item) ? {} : {'item': item}
endfunction

" The buffer the cell at (lnum, col) refers to, like a tag: a container's IMAGE -> the image, its
" PROJECT -> the containers of the project, a compose project -> its containers, a kind -> its
" list, anything else -> its docker inspect. '' if none.
function! docker#navigation#tag_target(dbuf, lnum, col) abort
  let cell = s:cell_at(a:dbuf, a:lnum, a:col)
  if empty(cell)
    return ''
  endif
  let item = cell.item
  let context = a:dbuf.context
  let column = get(cell, 'column', '')
  if item.kind ==# 'type'
    return docker#util#buf_name({'context': context, 'kind': item.name})
  elseif item.kind ==# 'container' && column ==# 'IMAGE'
    return docker#util#buf_name({'context': context, 'kind': 'images', 'params': {'reference': item.Image}})
  elseif item.kind ==# 'container' && column ==# 'PROJECT' && cell.text !=# ''
    return docker#util#buf_name({'context': context, 'kind': 'containers', 'params': {'project': cell.text}})
  elseif item.kind ==# 'compose'
    return docker#util#buf_name({'context': context, 'kind': 'containers', 'params': {'project': item.name}})
  endif
  let kind = get({'container': 'containers', 'image': 'images', 'volume': 'volumes', 'network': 'networks'}, item.kind, '')
  return kind ==# '' ? '' : docker#util#buf_name({'context': context, 'kind': kind, 'name': item.name})
endfunction

" The tag target under the cursor.
function! docker#navigation#cursor_target(dbuf) abort
  return docker#navigation#tag_target(a:dbuf, line('.'), col('.') - 1)
endfunction

" Jump to the tag target under the cursor, in a new window if split, pushed on the tag stack so
" that CTRL-T jumps back. A 'tagfunc' cannot do it: Vim refuses tags that are URLs.
function! docker#navigation#tag_jump(split) abort
  let target = docker#navigation#cursor_target(docker#buffer#get(bufnr()))
  if target ==# ''
    return
  endif
  let item = {'tagname': expand('<cword>'), 'from': [bufnr()] + getpos('.')[1:]}
  if a:split
    split
  endif
  call settagstack(win_getid(), {'items': [item]}, 't')
  execute 'edit' fnameescape(target)
endfunction

" Jump to the next (or previous) diagnostic, wrapping around.
function! docker#navigation#diagnostic(forward) abort
  let lnums = map(sign_getplaced(bufnr(), {'group': 'docker'})[0].signs, 'v:val.lnum')
  if empty(lnums)
    call docker#util#notify('No diagnostics', 'warn')
    return
  endif
  call sort(uniq(sort(lnums, 'n')), 'n')
  let current = line('.')
  if a:forward
    let next = filter(copy(lnums), 'v:val > current')
    let lnum = empty(next) ? lnums[0] : next[0]
  else
    let previous = filter(copy(lnums), 'v:val < current')
    let lnum = empty(previous) ? lnums[-1] : previous[-1]
  endif
  normal! m'
  call cursor(lnum, 1)
endfunction

" Show the diagnostics of the cursor line.
function! docker#navigation#show_diagnostics(dbuf) abort
  for sign in sign_getplaced(a:dbuf.buf, {'group': 'docker', 'lnum': line('.')})[0].signs
    call docker#util#notify(get(a:dbuf.diagnostics, sign.id, ''), sign.name ==# 'DockerError' ? 'error' : 'warn')
  endfor
endfunction
