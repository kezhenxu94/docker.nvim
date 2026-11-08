let g:docker_refresh_interval = 200
let s:containers = 'docker://context/ctx-a/containers'

function! SetUp() abort
  call ResetDocker()
  call Respond('context show', {'stdout': "ctx-a\n"})
  call Respond('*ps --all*', {'fixture': 'containers.ndjson'})
  call Respond('*images --format*', {'fixture': 'images.ndjson'})
  call Respond('*history*', {'fixture': 'history.ndjson'})
  call Respond('*volume ls*', {'fixture': 'volumes.ndjson'})
  call Respond('*network ls*', {'fixture': 'networks.ndjson'})
  call Respond('*compose ls*', {'fixture': 'compose.json'})
  call Respond('*container inspect shop-web-1', {'fixture': 'inspect-web.json'})
  let s:messages = CaptureNotify()
endfunction

function! TearDown() abort
  call RestoreStubs()
  call CleanBuffers()
endfunction

" Answer every prompt with its first item, returning the prompts.
function! s:prompts() abort
  return AnswerPrompts({items, prompt -> 0})
endfunction

" ------------------------------------------------------------------ lists

function! Test_lists_render_the_containers_of_the_context_with_the_header() abort
  call Open(s:containers)
  call assert_equal(4, len(Lines()))
  call assert_match('^shop-web-1 \+nginx:1\.27 \+Up 2 hours', Lines()[0])
  call assert_match('NAME \+IMAGE \+STATUS', resource#compat#header(win_getid()))
  call assert_equal(['--context ctx-a ps --all --format={{json .}}'], Calls())
  call assert_equal('acwrite', &buftype)
  call assert_equal(0, &wrap)
endfunction

function! Test_lists_show_unhealthy_and_failed_containers_as_diagnostics() abort
  call Open(s:containers)
  let signs = sign_getplaced(bufnr(), {'group': 'resource'})[0].signs
  call assert_equal([[2, 'DockerSignError'], [3, 'DockerSignError']], map(copy(signs), '[v:val.lnum, v:val.name]'))
  normal ]d
  call assert_equal(2, line('.'))
  normal ]d
  call assert_equal(3, line('.'))
  normal ]d
  call assert_equal(2, line('.'))
  execute "normal \<C-w>d"
  let floats = resource#compat#floats()
  call assert_equal([['The container is unhealthy']], map(copy(floats), 'v:val[1]'))
  call resource#compat#close_float(floats[0][0])
endfunction

function! Test_lists_are_pinned_to_the_current_context_when_opened_without_one() abort
  call Open('docker://containers')
  call assert_equal(s:containers, bufname())
  " The alias is wiped
  call WaitFor({-> bufnr('docker://containers') == -1}, 'the alias to be wiped')
endfunction

function! Test_lists_filter_by_the_params_project_by_the_compose_label() abort
  call Open(s:containers . '?project=shop')
  call WaitCall('label=com.docker.compose.project=shop')
endfunction

function! Test_lists_show_the_kinds_and_enter_lists_one() abort
  call Open('docker://')
  call assert_equal('docker://context/ctx-a/types', bufname())
  call PressOn('volumes', "\<CR>")
  call WaitBufName('docker://context/ctx-a/volumes')
  call WaitLoaded()
  call assert_match('^shop_data', Lines()[0])
endfunction

function! Test_lists_show_the_error_of_docker() abort
  call Respond('*network ls*', {'stderr': 'Cannot connect to the Docker daemon', 'code': 1})
  call Open('docker://context/ctx-a/networks')
  call assert_equal('✗ Cannot connect to the Docker daemon', Status())
  call assert_equal([{'msg': 'Cannot connect to the Docker daemon', 'level': 'error'}], s:messages)
endfunction

function! Test_lists_show_a_status_when_empty() abort
  call Respond('*volume ls*', {'stdout': ''})
  call Open('docker://context/ctx-a/volumes')
  call assert_equal('No volumes found', Status())
endfunction

function! Test_lists_keep_the_cursor_on_the_same_item_when_reloaded() abort
  call Open(s:containers)
  call cursor(3, 1)
  call Respond('*ps --all*', {'stdout': join(split(Fixture('containers.ndjson'), "\n")[1:], "\n")})
  normal R
  call WaitLoaded()
  call assert_equal(3, len(Lines()))
  call assert_match('^migrate', getline('.'))
endfunction

function! Test_lists_are_reloaded_periodically_when_watched() abort
  call Open(s:containers)
  normal gw
  call assert_match('⟳ 0.2s', resource#compat#header(win_getid()))
  " The watched buffer is not current, in Vim's Ex mode (-es) it is never in Normal mode
  new
  call WaitCall('ps --all', 3)
  close
  normal gw
  call assert_notmatch('⟳', resource#compat#header(win_getid()))
endfunction

function! Test_lists_highlight_the_rows_a_watched_reload_changed() abort
  call Open(s:containers)
  call Respond('*ps --all*', {'stdout': substitute(Fixture('containers.ndjson'), 'Up 2 hours (unhealthy)', 'Up 3 hours', '')})
  normal gw
  let buf = bufnr()
  new
  call WaitFor({-> !empty(resource#compat#highlighted_lines(buf, 'changed'))}, 'the changed rows')
  call assert_equal([2], resource#compat#highlighted_lines(buf, 'changed'))
  close
  normal gw
endfunction

function! Test_lists_header_is_removed_from_windows_showing_other_buffers() abort
  call Open(s:containers)
  call assert_notequal('', resource#compat#header(win_getid()))
  enew
  call assert_equal('', resource#compat#header(win_getid()))
endfunction

" ------------------------------------------------------------------ navigation

function! Test_navigation_enter_on_a_container_shows_its_logs_and_minus_goes_back() abort
  call Respond('*logs*', {'stdout': "hello\nworld"})
  call Open(s:containers)
  call PressOn('shop-web-1', "\<CR>")
  call WaitBufName(s:containers . '/shop-web-1/logs')
  call WaitLoaded()
  call assert_equal(['hello', 'world'], Lines())
  call assert_equal('nofile', &buftype)
  call assert_equal(['--context ctx-a logs --tail=1000 shop-web-1'], CallsMatching('logs'))
  normal -
  call WaitBufName(s:containers)
endfunction

function! Test_navigation_gL_follows_the_logs_and_ctrl_c_stops() abort
  call Respond('*logs*', {'script': 'echo first; sleep 30'})
  call Open(s:containers)
  call PressOn('shop-web-1', 'gL')
  call WaitBufName(s:containers . '/shop-web-1/logs?follow=true')
  call WaitFor({-> getline(1) ==# 'first'}, 'the first line')
  call assert_equal('Waiting for new logs... (Ctrl+C to stop)', Status())
  let dbuf = resource#get(bufnr())
  execute "normal \<C-c>"
  call assert_equal({}, dbuf.jobs)
  call assert_match('^Stopped following logs', Status())
endfunction

function! Test_navigation_gd_inspects_the_item_read_only() abort
  call Open(s:containers)
  call PressOn('shop-web-1', 'gd')
  call WaitBufName(s:containers . '/shop-web-1')
  call WaitLoaded()
  call assert_equal('json', &filetype)
  call assert_equal(0, &modifiable)
  call assert_equal('[', Lines()[0])
endfunction

function! Test_navigation_ctrl_bracket_on_IMAGE_lists_the_image_and_ctrl_t_jumps_back() abort
  call Open(s:containers)
  call PressOn('nginx:1.27', "\<C-]>")
  call WaitBufName('docker://context/ctx-a/images?reference=nginx:1.27')
  call WaitCall('images .*--filter reference=nginx:1.27')
  execute "normal \<C-t>"
  call WaitBufName(s:containers)
endfunction

function! Test_navigation_ctrl_w_bracket_opens_the_jump_in_a_split() abort
  call Open(s:containers)
  call PressOn('shop-web-1', "\<C-w>]")
  call WaitBufName(s:containers . '/shop-web-1')
  call assert_equal(2, winnr('$'))
  execute "normal \<C-t>"
  call WaitBufName(s:containers)
endfunction

function! Test_navigation_ctrl_bracket_on_PROJECT_lists_its_containers() abort
  call Open(s:containers)
  call cursor(1, 1)
  call search('shop ')
  execute "normal \<C-]>"
  call WaitBufName(s:containers . '?project=shop')
endfunction

function! Test_navigation_enter_on_a_compose_project_lists_its_containers_and_minus_goes_back() abort
  call Open('docker://context/ctx-a/compose')
  call PressOn('shop', "\<CR>")
  call WaitBufName(s:containers . '?project=shop')
  normal -
  call WaitBufName('docker://context/ctx-a/compose')
  normal -
  call WaitBufName('docker://context/ctx-a/types')
endfunction

function! Test_navigation_enter_on_an_image_shows_its_history() abort
  call Open('docker://context/ctx-a/images')
  call PressOn('latest', "\<CR>")
  call WaitBufName('docker://context/ctx-a/images/1e5f3c5b981a/history')
  call WaitLoaded()
  call assert_equal(2, len(Lines()))
endfunction

function! Test_navigation_enter_on_a_volume_lists_the_containers_using_it() abort
  call Open('docker://context/ctx-a/volumes')
  call PressOn('shop_data', "\<CR>")
  call WaitBufName(s:containers . '?volume=shop_data')
endfunction

function! Test_navigation_help_lists_the_keymaps() abort
  call Open(s:containers)
  let lines = resource#buffer#help_lines(resource#provider('docker'))
  call assert_equal('Keymaps', lines[0])
  call assert_equal('  -        go to the parent buffer', lines[1])
  call assert_notequal(-1, index(lines, '  gra      operations on the item under the cursor, or the selected ones'))
endfunction

" ------------------------------------------------------------------ :w

function! Test_write_removes_the_items_of_deleted_lines_after_confirming() abort
  call Respond('*rm --force*', {'stdout': 'migrate'})
  let prompts = s:prompts()
  call Open(s:containers)
  call PressOn('migrate', 'dd')
  write
  call WaitCall('rm --force migrate')
  call assert_match('Remove container migrate', prompts[0].prompt)
  call assert_match('(context: ctx-a)', prompts[0].prompt)
endfunction

function! Test_write_untags_images_and_removes_untagged_ones_by_id_without_confirming_with_bang() abort
  call Respond('*rmi*', {'stdout': ''})
  let prompts = s:prompts()
  call Open('docker://context/ctx-a/images')
  call cursor(2, 1)
  normal 2dd
  write!
  call WaitCall('rmi', 2)
  " In parallel
  call assert_equal(['--context ctx-a rmi 9f8e7d6c5b4a', '--context ctx-a rmi nginx:latest'], sort(CallsMatching('rmi')))
  call assert_equal([], prompts)
  " Reloaded once done
  call WaitCall('images --format', 2)
endfunction

function! Test_write_takes_compose_projects_down() abort
  call Respond('*down*', {'stdout': ''})
  call s:prompts()
  call Open('docker://context/ctx-a/compose')
  call PressOn('tools', 'dd')
  write
  call WaitCall('compose --project-name tools down')
endfunction

function! Test_write_refuses_cell_edits() abort
  call Open(s:containers)
  call PressOn('migrate', "ciwrenamed\<Esc>")
  write
  call assert_equal('NAME of container migrate is not editable', s:messages[0].msg)
  call assert_equal(1, len(Calls()))
endfunction

function! Test_write_does_nothing_when_declined() abort
  call AnswerPrompts({items, prompt -> 1})
  call Open(s:containers)
  call PressOn('backup', 'dd')
  write
  sleep 100m
  call assert_equal([], CallsMatching('rm '))
  call assert_equal(1, &modified)
endfunction

function! Test_deleted_lines_stay_visible_until_written() abort
  call Open(s:containers)
  call PressOn('migrate', 'dd')
  doautocmd TextChanged
  " Above the row that followed it
  call assert_equal([[3, 1]], map(resource#compat#get_virt_lines(bufnr()), '[v:val[0], v:val[2]]'))
  call cursor(3, 1)
  normal dd
  doautocmd TextChanged
  " Below the last line without one
  call assert_equal([[2, 0]], map(resource#compat#get_virt_lines(bufnr()), '[v:val[0], v:val[2]]'))
endfunction

" ------------------------------------------------------------------ operations

function! Test_operations_gra_offers_the_operations_of_the_item_confirming_the_disruptive_ones() abort
  call Respond('*stop*', {'stdout': 'shop-web-1'})
  let prompts = AnswerPrompts({items, prompt -> max([index(items, 'Stop'), 0])})
  call Open(s:containers)
  call PressOn('shop-web-1', 'gra')
  call WaitCall('stop shop-web-1')
  call assert_equal(['Logs', 'Follow logs', 'Exec', 'Start', 'Stop', 'Restart', 'Pause', 'Unpause', 'Kill', 'Remove'],
        \ prompts[0].items)
  call assert_equal('Stop container shop-web-1 (context: ctx-a)?', prompts[1].prompt)
  " Reloaded once done
  call WaitCall('ps --all', 2)
endfunction

function! Test_operations_gra_on_a_visual_selection_runs_the_operation_on_every_item() abort
  call Respond('*start*', {'stdout': ''})
  let prompts = s:prompts()
  call Open(s:containers)
  call cursor(3, 1)
  normal Vjgra
  call WaitCall('start', 2)
  call assert_equal(['--context ctx-a start backup', '--context ctx-a start migrate'], sort(CallsMatching(' start ')))
  call assert_equal('Start 2 containers', prompts[0].items[0])
endfunction

function! Test_operations_of_images() abort
  call Respond('*pull*', {'stdout': ''})
  let prompts = AnswerPrompts({items, prompt -> index(items, 'Pull')})
  call Open('docker://context/ctx-a/images')
  call PressOn('latest', 'gra')
  call WaitCall('pull --quiet nginx:latest')
  call assert_equal(['History', 'Pull', 'Remove'], prompts[0].items)
  " Untagged images cannot be pulled
  call PressOn('9f8e7d6c5b4a', 'gra')
  call assert_equal(['History', 'Remove'], prompts[1].items)
endfunction
