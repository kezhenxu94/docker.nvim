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

" The buffer a cell refers to, like a tag: a container's IMAGE -> the image, its PROJECT -> the
" containers of the project, a compose project -> its containers, a kind -> its list, anything
" else -> its docker inspect. '' if none.
function! docker#navigation#tag_target(dbuf, cell) abort
  let item = a:cell.item
  let context = a:dbuf.context
  if item.kind ==# 'type'
    return docker#util#buf_name({'context': context, 'kind': item.name})
  elseif item.kind ==# 'container' && a:cell.column ==# 'IMAGE'
    return docker#util#buf_name({'context': context, 'kind': 'images', 'params': {'reference': item.Image}})
  elseif item.kind ==# 'container' && a:cell.column ==# 'PROJECT' && a:cell.text !=# ''
    return docker#util#buf_name({'context': context, 'kind': 'containers', 'params': {'project': a:cell.text}})
  elseif item.kind ==# 'compose'
    return docker#util#buf_name({'context': context, 'kind': 'containers', 'params': {'project': item.name}})
  endif
  let kind = get({'container': 'containers', 'image': 'images', 'volume': 'volumes', 'network': 'networks'}, item.kind, '')
  return kind ==# '' ? '' : docker#util#buf_name({'context': context, 'kind': kind, 'name': item.name})
endfunction
