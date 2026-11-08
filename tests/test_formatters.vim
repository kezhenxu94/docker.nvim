function! s:format(kind, fixture) abort
  return docker#formatters#get(a:kind).format(docker#cli#decode(Fixture(a:fixture)))
endfunction

function! Test_containers_columns_with_the_compose_project() abort
  let rows = s:format('containers', 'containers.ndjson')
  call assert_equal(['shop-web-1', 'nginx:1.27', 'Up 2 hours', '0.0.0.0:8080->80/tcp', 'shop', '2 hours ago', 'a1b2c3d4e5f6'],
        \ rows[0].row)
  call assert_equal('', rows[2].row[4])
  call assert_equal(['container', 'shop-web-1'], [rows[0].item.kind, rows[0].item.name])
endfunction

function! Test_containers_status_highlights_and_diagnostics() abort
  let rows = s:format('containers', 'containers.ndjson')
  call assert_equal(['DockerRunning', 'DockerFailed', 'DockerFailed', 'DockerSucceeded'],
        \ map(copy(rows), 'v:val.highlights.STATUS'))
  call assert_equal([], rows[0].diagnostics)
  call assert_equal('The container is unhealthy', rows[1].diagnostics[0].message)
  call assert_equal('Exited with code 1', rows[2].diagnostics[0].message)
  call assert_equal([], rows[3].diagnostics)
endfunction

function! Test_containers_label_not_one_of_the_same_prefix() abort
  call assert_equal('shop', docker#formatters#label(
        \ 'com.docker.compose.project.config_files=/a,com.docker.compose.project=shop', 'com.docker.compose.project'))
  call assert_equal('', docker#formatters#label('com.docker.compose.project.config_files=/a', 'com.docker.compose.project'))
  call assert_equal('', docker#formatters#label('', 'com.docker.compose.project'))
endfunction

function! Test_images_removed_by_tag_untagged_by_id() abort
  let rows = s:format('images', 'images.ndjson')
  call assert_equal('nginx:1.27', rows[0].item.ref)
  call assert_equal('nginx:latest', rows[1].item.ref)
  call assert_equal('9f8e7d6c5b4a', rows[2].item.ref)
  call assert_equal('1e5f3c5b981a', rows[0].item.name)
  call assert_equal({'REPOSITORY': 'DockerSucceeded', 'TAG': 'DockerSucceeded'}, rows[2].highlights)
endfunction

function! Test_history_layers() abort
  let rows = s:format('history', 'history.ndjson')
  call assert_equal(['1:1e5f3c5b981a', '2:<missing>'], map(copy(rows), 'v:val.item.name'))
  call assert_equal('layer', rows[0].item.kind)
endfunction

function! Test_compose_partly_running_projects_are_pending() abort
  let rows = s:format('compose', 'compose.json')
  call assert_equal(['shop', 'running(2)', '/shop/compose.yaml'], rows[0].row)
  call assert_equal('DockerRunning', rows[0].highlights.STATUS)
  call assert_equal('DockerPending', rows[1].highlights.STATUS)
endfunction

function! Test_types_list_the_kinds() abort
  call assert_equal(['compose', 'containers', 'images', 'networks', 'volumes'],
        \ map(docker#formatters#get('types').format([]), 'v:val.item.name'))
endfunction

function! Test_format_table_aligns_and_truncates() abort
  let [header, rows] = docker#resources#format_table(['NAME', 'X'],
        \ [{'row': ['ä', repeat('y', 120)], 'item': {}, 'highlights': {}, 'diagnostics': []}])
  call assert_equal('NAME  X' . repeat(' ', 98), header.formatted)
  call assert_equal('ä     ' . repeat('y', 96) . '...', rows[0].formatted)
  call assert_equal([[0, 5], [7, 106]], rows[0].ranges)
endfunction
