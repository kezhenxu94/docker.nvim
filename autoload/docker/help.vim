" The help of docker buffers, g?.

function! docker#help#lines() abort
  let lines = ['Keymaps']
  for [lhs, description] in docker#keymaps#list()
    call add(lines, printf('  %-8s %s', lhs, description))
  endfor
  return lines + [
        \ '',
        \ 'Built-in keys that also work',
        \ '  <C-]>    jump to what the cell under the cursor refers to: a container''s',
        \ '           IMAGE the image, its PROJECT the containers of the project, a',
        \ '           compose project its containers, else docker inspect',
        \ '  <C-t>    jump back, <C-w>] opens the jump in a split',
        \ '  ]d [d    next / previous unhealthy container, <C-w>d shows why',
        \ '',
        \ 'Editing, :w applies after confirming, :w! without confirming',
        \ '  lists    delete lines to remove the containers, images, volumes,',
        \ '           networks, or to take compose projects down',
        \ '',
        \ 'Commands',
        \ '  :Docker get {kind} [{filter}={value}]...',
        \ '  :Docker context [{context}]',
        \ '',
        \ 'Buffer names',
        \ '  docker://[context/{context}/]{kind}[/{name}[/{subresource}]][?{filters}]',
        \ '  Without context/{context}/ the current context is used and the buffer',
        \ '  stays bound to it, e.g. :e docker://containers?status=running',
        \ '  :e docker:// lists the kinds',
        \ '',
        \ 'More in :help docker.nvim',
        \ ]
endfunction

" Show the help in a floating window.
function! docker#help#show(...) abort
  return docker#compat#float(docker#help#lines(), ' docker.nvim ')
endfunction
