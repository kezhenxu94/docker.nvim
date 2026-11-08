" Minimal test runner, see the Makefile:
"   vim -Nu NONE -i NONE -es -S tests/runner.vim tests/test_{name}.vim
"   nvim --headless -u NONE -i NONE -S tests/runner.vim tests/test_{name}.vim
" Runs the Test_* functions of the file, with SetUp() and TearDown() around each, and appends
" the results to $TEST_RESULT.
let s:root = expand('<sfile>:p:h:h')
let s:spec = argv(0)
" resource.vim, see the Makefile
execute 'set runtimepath^=' . fnameescape(s:root) . ',' . fnameescape(fnamemodify($RESOURCE_VIM, ':p'))
set nomore
runtime plugin/resource.vim
runtime plugin/docker.vim
" Against the fake docker of tests/bin, never a real daemon
let $PATH = s:root . '/tests/bin:' . $PATH
let $DOCKER_TEST_DIR = tempname()
call mkdir($DOCKER_TEST_DIR, 'p')
execute 'source' fnameescape(s:root . '/tests/helpers.vim')
execute 'source' fnameescape(s:spec)

let s:failed = 0
let s:out = []
let s:tests = sort(filter(map(split(execute('function /^Test_'), "\n"),
      \ {_, line -> matchstr(line, 'Test_\w\+')}), '!empty(v:val)'))
for s:name in s:tests
  let v:errors = []
  try
    if exists('*SetUp')
      call SetUp()
    endif
    call call(s:name, [])
  catch
    call add(v:errors, v:exception . ' @ ' . v:throwpoint)
  endtry
  try
    if exists('*TearDown')
      call TearDown()
    endif
  catch
    call add(v:errors, 'TearDown: ' . v:exception . ' @ ' . v:throwpoint)
  endtry
  if empty(v:errors)
    call add(s:out, '  ok   ' . s:name)
  else
    let s:failed += 1
    call add(s:out, '  FAIL ' . s:name)
    call extend(s:out, map(copy(v:errors), {_, error -> '       ' . error}))
  endif
endfor
call add(s:out, printf('%s: %d passed, %d failed', s:spec, len(s:tests) - s:failed, s:failed))
call writefile(s:out, $TEST_RESULT, 'a')
call delete($DOCKER_TEST_DIR, 'rf')
execute s:failed ? 'cquit!' : 'qall!'
