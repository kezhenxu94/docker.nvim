" Helpers of the tests: the fake docker (tests/bin/docker), waiting, prompts and messages.

let s:dir = $DOCKER_TEST_DIR
let s:fixtures = expand('<sfile>:p:h') . '/fixtures'
let s:rules = []

" The functions stubbed by the tests are reset by RestoreStubs(), loaded first so that autoloading
" does not replace the stubs
runtime autoload/resource.vim

function! Fixture(name) abort
  return join(readfile(s:fixtures . '/' . a:name), "\n")
endfunction

" Make the fake docker reply to calls whose arguments match the shell glob pattern.
" opts: {stdout, stderr, code, fixture, script}. Later rules take precedence.
function! Respond(pattern, opts) abort
  let base = printf('%s/rule%d', s:dir, len(s:rules) + 1)
  let script = get(a:opts, 'script', '')
  if script ==# ''
    let stdout = has_key(a:opts, 'fixture') ? Fixture(a:opts.fixture) : get(a:opts, 'stdout', '')
    call writefile(split(stdout, "\n", 1), base . '.out', 'b')
    call writefile(split(get(a:opts, 'stderr', ''), "\n", 1), base . '.err', 'b')
    let script = printf("cat '%s.out'; cat '%s.err' >&2; exit %d", base, base, get(a:opts, 'code', 0))
  endif
  call writefile([script], base . '.sh')
  call insert(s:rules, a:pattern . "\t" . base . '.sh')
  call writefile(s:rules, s:dir . '/rules')
endfunction

" The arguments of each docker call since the last reset.
function! Calls() abort
  let file = s:dir . '/calls'
  return filereadable(file) ? readfile(file) : []
endfunction

function! CallsMatching(pattern) abort
  return filter(Calls(), {_, call -> call =~# a:pattern})
endfunction

function! ResetDocker() abort
  let s:rules = []
  call writefile([], s:dir . '/rules')
  call delete(s:dir . '/calls')
  call docker#cli#use_context('')
endfunction

" Wait until Cond() is true, fail after timeout milliseconds (5000 by default).
function! WaitFor(Cond, what, ...) abort
  let timeout = get(a:, 1, 5000)
  let start = reltime()
  while !a:Cond()
    if reltimefloat(reltime(start)) * 1000 > timeout
      throw 'timed out waiting for ' . a:what
    endif
    sleep 10m
  endwhile
endfunction

function! WaitCall(pattern, ...) abort
  let min = get(a:, 1, 1)
  call WaitFor({-> len(CallsMatching(a:pattern)) >= min}, 'docker call matching ' . a:pattern)
endfunction

function! WaitBufName(name) abort
  call WaitFor({-> bufname() ==# a:name}, 'buffer ' . a:name . ', current: ' . bufname())
endfunction

" Wait for the current docker buffer to finish loading.
function! WaitLoaded(...) abort
  let buf = bufnr()
  " The kinds are rendered without a job
  call WaitFor({-> !empty(resource#get(buf)) && !resource#loading(buf)}, 'buffer to load', get(a:, 1, 5000))
  " Let the callbacks run
  sleep 20m
endfunction

function! Open(name) abort
  execute 'edit' fnameescape(a:name)
  call WaitLoaded()
endfunction

" Answer the prompts of resource#select() with Answer(items, prompt), the index of the choice, -1
" to cancel. Returns the prompts: [{prompt, items}].
function! AnswerPrompts(Answer) abort
  let g:test_prompts = []
  let g:TestAnswer = a:Answer
  function! resource#select(items, opts, Callback) abort
    let items = has_key(a:opts, 'format_item') ? map(copy(a:items), 'a:opts.format_item(v:val)') : a:items
    call add(g:test_prompts, {'prompt': get(a:opts, 'prompt', ''), 'items': items})
    let i = g:TestAnswer(items, get(a:opts, 'prompt', ''))
    call a:Callback(i < 0 ? v:null : a:items[i], i < 0 ? v:null : i + 1)
  endfunction
  return g:test_prompts
endfunction

" Capture the messages of resource#notify(): [{msg, level}].
function! CaptureNotify() abort
  let g:test_messages = []
  function! resource#notify(msg, ...) abort
    call add(g:test_messages, {'msg': a:msg, 'level': get(a:, 1, 'info')})
  endfunction
  return g:test_messages
endfunction

function! RestoreStubs() abort
  runtime autoload/resource.vim
endfunction

" Kill docker jobs and wipe every buffer, leaving an empty one.
function! CleanBuffers() abort
  silent! %bwipeout!
  call WaitFor({-> empty(resource#buffers())}, 'docker buffers to be cleaned up')
endfunction

function! Lines() abort
  return getline(1, '$')
endfunction

" The status shown after a line, '' if none.
function! Status() abort
  return get(resource#compat#status(bufnr()), 1, '')
endfunction

" Move the cursor to the first occurrence of text and press keys.
function! PressOn(text, keys) abort
  call cursor(1, 1)
  if search('\V' . escape(a:text, '\'), 'cW') == 0
    throw 'line not found: ' . a:text
  endif
  execute 'normal' a:keys
endfunction
