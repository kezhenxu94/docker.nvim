" Run Fn(Done) and wait for it to call Done, returns the arguments of Done.
function! s:await(Fn) abort
  let result = []
  call a:Fn({... -> add(result, a:000)})
  call WaitFor({-> !empty(result)}, 'callback')
  return result[0]
endfunction

function! SetUp() abort
  call ResetDocker()
endfunction

function! Test_decode_json_lines_and_arrays() abort
  call assert_equal([{'Name': 'a'}, {'Name': 'b'}], docker#cli#decode("{\"Name\":\"a\"}\n{\"Name\":\"b\"}\n"))
  call assert_equal([{'Name': 'a'}], docker#cli#decode("[{\"Name\":\"a\"}]\n"))
  call assert_equal([], docker#cli#decode(''))
endfunction

function! Test_list_passes_the_context_and_the_filters_project_as_the_compose_label() abort
  call Respond('*', {'stdout': ''})
  call s:await({Done -> docker#cli#list('ctx-a', 'containers', {'project': 'shop', 'status': 'running'}, Done, v:null)})
  call assert_equal(['--context ctx-a ps --all --format={{json .}} --filter label=com.docker.compose.project=shop --filter status=running'],
        \ Calls())
endfunction

function! Test_list_reports_errors() abort
  call Respond('*', {'stderr': 'Cannot connect to the Docker daemon', 'code': 1})
  let [err] = s:await({Done -> docker#cli#list('ctx-a', 'images', {}, v:null, Done)})
  call assert_equal('Cannot connect to the Docker daemon', err)
endfunction

function! Test_logs_merge_stdout_and_stderr() abort
  call Respond('*logs*', {'script': 'echo out; echo err >&2'})
  let [logs] = s:await({Done -> docker#cli#logs('ctx-a', 'containers', 'web', {'since': '1h'}, Done, v:null)})
  call assert_equal("out\nerr", logs)
  call assert_equal(['--context ctx-a logs --tail=1000 --since=1h web'], Calls())
endfunction

function! Test_logs_of_compose_projects() abort
  call Respond('*', {'stdout': 'web-1  | hello'})
  call s:await({Done -> docker#cli#logs('ctx-a', 'compose', 'shop', {'tail': 5}, Done, v:null)})
  call assert_equal(['--context ctx-a compose --project-name shop logs --no-color --tail=5'], Calls())
endfunction

function! Test_logs_followed_emit_complete_lines() abort
  call Respond('*logs*', {'script': 'printf "a\nb"; sleep 0.2; printf "c\nd\n"'})
  let chunks = []
  let job = docker#cli#logs('', 'containers', 'web', {'follow': 1}, {text -> add(chunks, text)}, v:null)
  call WaitFor({-> !docker#compat#job_running(job)}, 'logs')
  call assert_equal(['a', "bc\nd"], chunks)
  call assert_equal(['logs --tail=1000 --follow web'], Calls())
endfunction

function! Test_remove_uses_the_command_of_the_kind() abort
  call Respond('*', {'stdout': ''})
  for item in [
        \ {'kind': 'container', 'name': 'web'},
        \ {'kind': 'image', 'name': '1e5f', 'ref': 'nginx:latest'},
        \ {'kind': 'volume', 'name': 'data'},
        \ {'kind': 'network', 'name': 'net'},
        \ {'kind': 'compose', 'name': 'shop'},
        \ ]
    call s:await({Done -> docker#cli#remove('ctx-a', item, Done, v:null)})
  endfor
  call assert_equal([
        \ '--context ctx-a rm --force web',
        \ '--context ctx-a rmi nginx:latest',
        \ '--context ctx-a volume rm data',
        \ '--context ctx-a network rm net',
        \ '--context ctx-a compose --project-name shop down',
        \ ], Calls())
endfunction

function! Test_killed_jobs_do_not_call_back() abort
  call Respond('*', {'script': 'sleep 5'})
  let called = []
  let job = docker#cli#list('', 'images', {}, {... -> add(called, 1)}, {... -> add(called, 1)})
  call docker#compat#job_kill(job)
  call WaitFor({-> !docker#compat#job_running(job)}, 'the job to end')
  sleep 50m
  call assert_equal([], called)
endfunction

function! Test_contexts_use_the_context_switched_to_and_save_it() abort
  call Respond('context show', {'stdout': "default\n"})
  call assert_equal('default', docker#cli#current_context())
  call docker#cli#use_context('remote')
  call assert_equal('remote', docker#cli#current_context())
  call assert_equal({'context': 'remote'},
        \ json_decode(join(readfile(docker#compat#state_dir() . '/docker_state.json'))))
endfunction
