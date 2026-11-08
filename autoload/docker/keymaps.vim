" The keymaps of docker buffers.

" Descriptions of the keymaps by name, for the help
let s:descriptions = {
      \ 'drill_down': 'drill down into the item under the cursor',
      \ 'show_logs': 'show the logs of the item under the cursor',
      \ 'follow_logs': 'follow the logs of the item under the cursor',
      \ 'exec': 'open a shell in the container under the cursor',
      \ 'inspect': 'go to what the cell under the cursor refers to, mostly docker inspect',
      \ 'operations': 'operations on the item under the cursor, or the selected ones',
      \ 'parent': 'go to the parent buffer',
      \ 'help': 'show this help',
      \ 'watch': 'toggle reloading the list periodically',
      \ 'refresh': 'reload the buffer',
      \ }

let s:commands = {
      \ 'drill_down': 'call docker#keymaps#action("drill_down")',
      \ 'show_logs': 'call docker#keymaps#action("show_logs", 0)',
      \ 'follow_logs': 'call docker#keymaps#action("show_logs", 1)',
      \ 'exec': 'call docker#keymaps#action("exec")',
      \ 'inspect': 'call docker#keymaps#inspect()',
      \ 'operations': 'call docker#keymaps#operations()',
      \ 'parent': 'call docker#keymaps#parent()',
      \ 'help': 'call docker#help#show(bufnr())',
      \ 'watch': 'call docker#refresh#toggle(docker#buffer#get(bufnr()))',
      \ 'refresh': 'call docker#buffer#load(docker#buffer#get(bufnr()))',
      \ }

" Set the keymaps of the current buffer.
function! docker#keymaps#setup(dbuf) abort
  for [name, lhs] in items(docker#util#config('keymaps'))
    if has_key(s:commands, name) && lhs !=# ''
      execute 'nnoremap <buffer> <silent>' lhs '<Cmd>' . s:commands[name] . '<CR>'
    endif
  endfor
  let operations = docker#util#config('keymaps').operations
  if operations !=# ''
    execute 'xnoremap <buffer> <silent>' operations '<Cmd>' . s:commands.operations . '<CR>'
  endif
  " The diagnostics of containers
  nnoremap <buffer> <silent> ]d <Cmd>call docker#navigation#diagnostic(1)<CR>
  nnoremap <buffer> <silent> [d <Cmd>call docker#navigation#diagnostic(0)<CR>
  nnoremap <buffer> <silent> <C-w>d <Cmd>call docker#navigation#show_diagnostics(docker#buffer#get(bufnr()))<CR>
  " Like tags
  nnoremap <buffer> <silent> <C-]> <Cmd>call docker#navigation#tag_jump(0)<CR>
  nnoremap <buffer> <silent> <C-w>] <Cmd>call docker#navigation#tag_jump(1)<CR>
  nnoremap <buffer> <silent> <C-w><C-]> <Cmd>call docker#navigation#tag_jump(1)<CR>
endfunction

" [[lhs, description]] of the keymaps, sorted by lhs.
function! docker#keymaps#list() abort
  let keymaps = []
  for [name, lhs] in items(docker#util#config('keymaps'))
    if has_key(s:descriptions, name) && lhs !=# ''
      call add(keymaps, [lhs, s:descriptions[name]])
    endif
  endfor
  return sort(keymaps)
endfunction

" Run the action for the item under the cursor.
function! docker#keymaps#action(name, ...) abort
  let dbuf = docker#buffer#get(bufnr())
  let item = docker#resources#item_at(dbuf, line('.'))
  if empty(item)
    return
  endif
  let actions = docker#actions#get(item.kind)
  if !has_key(actions, a:name)
    call docker#util#notify(printf('%s is not supported for %s', a:name, item.kind), 'warn')
    return
  endif
  call call(actions[a:name], [dbuf, item] + a:000)
endfunction

function! docker#keymaps#inspect() abort
  let target = docker#navigation#cursor_target(docker#buffer#get(bufnr()))
  if target !=# ''
    execute 'edit' fnameescape(target)
  endif
endfunction

function! docker#keymaps#parent() abort
  let parent = docker#navigation#parent_name(docker#buffer#get(bufnr()))
  if parent !=# ''
    execute 'edit' fnameescape(parent)
  endif
endfunction

" The operations on the item under the cursor, or the selected ones in Visual mode.
function! docker#keymaps#operations() abort
  let dbuf = docker#buffer#get(bufnr())
  if mode() ==# 'n'
    call docker#operations#select(dbuf, line('.'), line('.'))
    return
  endif
  let [first, last] = [line('v'), line('.')]
  execute "normal! \<Esc>"
  call docker#operations#select(dbuf, min([first, last]), max([first, last]))
endfunction
