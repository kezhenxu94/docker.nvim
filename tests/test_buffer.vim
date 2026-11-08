function! s:error(Fn) abort
  try
    call a:Fn()
  catch
    return v:exception
  endtry
  return ''
endfunction

function! TearDown() abort
  call RestoreStubs()
endfunction

function! Test_parse_name() abort
  call assert_equal({
        \ 'context': 'ctx/a:b',
        \ 'kind': 'containers',
        \ 'name': 'web',
        \ 'subresource': 'logs',
        \ 'params': {'follow': v:true, 'tail': '10'},
        \ }, docker#provider#parse('docker://context/ctx%2Fa%3Ab/containers/web/logs?follow&tail=10'))
endfunction

function! Test_parse_name_requires_a_context() abort
  call assert_match('^Invalid buffer name format', s:error({-> docker#provider#parse('docker://containers')}))
endfunction

function! Test_buf_name_round_trips_with_parse_name() abort
  let name = docker#util#buf_name({'context': 'ctx/a', 'kind': 'containers',
        \ 'params': {'project': 'shop', 'status': 'running'}})
  call assert_equal('docker://context/ctx%2fa/containers?project=shop&status=running', name)
  call assert_equal({'context': 'ctx/a', 'kind': 'containers', 'name': '', 'subresource': '',
        \ 'params': {'project': 'shop', 'status': 'running'}}, docker#provider#parse(name))
endfunction

function! s:canonical(name) abort
  call ResetDocker()
  call Respond('context show', {'stdout': "ctx-a\n"})
  return docker#provider#canonical(a:name)
endfunction

function! Test_canonical_name_pins_names_without_a_context_to_the_current_one() abort
  call assert_equal('docker://context/ctx-a/containers?status=running', s:canonical('docker://containers?status=running'))
endfunction

function! Test_canonical_name_uses_the_context_switched_to() abort
  call ResetDocker()
  call docker#cli#use_context('remote')
  call assert_equal('docker://context/remote/images', docker#provider#canonical('docker://images'))
endfunction

function! Test_canonical_name_lists_the_kinds_without_a_kind() abort
  call assert_equal('docker://context/ctx-a/types', s:canonical('docker://'))
  call assert_equal('docker://context/ctx-a/types', s:canonical('docker://context/ctx-a'))
endfunction

function! Test_canonical_name_keeps_canonical_names() abort
  call assert_equal('docker://context/ctx-a/volumes', s:canonical('docker://context/ctx-a/volumes'))
endfunction

function! Test_canonical_name_fails_without_a_context() abort
  call ResetDocker()
  call assert_equal('No current docker context', s:error({-> docker#provider#canonical('docker://images')}))
endfunction
