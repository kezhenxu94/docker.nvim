function! SetUp() abort
  call ResetDocker()
  call Respond('context show', {'stdout': "default\n"})
  call Respond('*ps --all*', {'fixture': 'containers.ndjson'})
endfunction

function! TearDown() abort
  call RestoreStubs()
  call CleanBuffers()
endfunction

function! Test_parse_get_with_filters_whose_values_contain_equal_signs() abort
  call assert_equal(['containers', {'label': 'app=web', 'status': 'running'}],
        \ docker#commands#parse_get(['containers', 'label=app=web', 'status=running']))
  call assert_equal(['images', {}], docker#commands#parse_get(['images']))
endfunction

function! Test_complete() abort
  call assert_equal(['compose', 'containers'], docker#commands#complete_get('co', ['co']))
  call assert_equal(['context', 'get'], docker#commands#complete('', 'Docker ', 7))
  call assert_equal(['status='], docker#commands#complete('st', 'Docker get containers st', 24))
  call Respond('context ls*', {'stdout': "default\nremote\n"})
  call assert_equal(['remote'], docker#commands#complete('r', 'Docker context r', 16))
endfunction

function! Test_reports_unknown_subcommands() abort
  let messages = CaptureNotify()
  Docker nope
  call assert_equal([{'msg': 'No such command: nope', 'level': 'error'}], messages)
endfunction

function! Test_get_opens_the_list_with_the_filters() abort
  Docker get containers status=running
  call WaitLoaded()
  call assert_equal('docker://context/default/containers?status=running', bufname())
  call assert_equal(4, len(Lines()))
endfunction

function! Test_context_switches_the_context_used_for_new_buffers() abort
  let messages = CaptureNotify()
  Docker context remote
  call assert_equal('remote', docker#cli#current_context())
  call assert_equal('Switched to context: remote', messages[0].msg)
endfunction

function! Test_context_without_a_name_prompts_with_the_current_one_marked() abort
  call Respond('context ls*', {'fixture': 'contexts.ndjson'})
  let prompts = AnswerPrompts({items, prompt -> 1})
  call CaptureNotify()
  Docker context
  call WaitFor({-> docker#cli#current_context() ==# 'remote'}, 'context switch')
  call assert_equal(['* default', '  remote'], prompts[0].items)
  call assert_equal('Select context (current: default)', prompts[0].prompt)
endfunction
