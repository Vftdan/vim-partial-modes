function! vim_partial_modes#init()
	return ''
endfunction

let s:conditions = {}
let s:modes = {}
let s:mode_stack = []
let s:root_mode = 'normal'

function! s:no_setter(name)
	function! s:_setter(value) closure
		echoerr 'Condition ' . a:name . ' is read-only'
	endfunction
	return funcref('s:_setter')
endfunction

function! s:dict_get_list(dict, key)
	if !has_key(a:dict, a:key)
		return []
	endif
	let l:Value = a:dict[a:key]
	if type(l:Value) != type([])
		let l:Value = [l:Value]
	endif
	return l:Value
endfunction

function! s:apply_funcref(f, args)
	let s:dict = { 'f': a:f }
	execute 'let l:res = s:dict.f(' . join(s:map_array(range(len(a:args)), {x -> 'a:args[' . x . ']'}), ', ') . ')'
	return l:res
endfunction

function! s:map_array(arr, func)
	return map(copy(a:arr), {x -> a:func(a:arr[x])})
endfunction

function! s:call_all(funcs, ...)
	let l:res = copy(a:funcs)
	for l:i in range(len(a:funcs))
		let l:res[l:i] = s:apply_funcref(a:funcs[l:i], a:000)
	endfor
	" return s:map_array(a:funcs, {f -> s:apply_funcref(f, a:000)})
endfunction

function! s:construct_plug_token(words)
	return "\<Plug>(" . join(s:map_array(a:words, {w -> escape(w, ' )\')}), ' ') . ")"
endfunction

function! s:map_all_modes(lhs, rhs)
	let l:arg = ' ' . escape(a:lhs, ' <\|') . ' ' . a:rhs
	for l:mapf in ['map', 'map!', 'tmap']
		execute l:mapf . l:arg
	endfor
endfunction

function! s:qarg(arg)
	return '"' . escape(a:arg, '"\') . '"'
endfunction

function! s:before_condition_index(name)
	if has_key(s:conditions, a:name)
		return
	endif
	if a:name =~ '^no='
		let l:inner = a:name[3:]
		call vim_partial_modes#define_condition({
			\ 'name': a:name,
			\ 'get': {-> !vim_partial_modes#condition_get(l:inner)},
			\ 'set': {value -> vim_partial_modes#condition_set(l:inner, !value)},
			\ })
	endif
endfunction

function! vim_partial_modes#define_condition(opts)
	let l:name = a:opts['name']
	let l:cond = { 'name': l:name }
	if has_key(s:conditions, l:name)
		if !get(a:opts, 'override', v:false)
			echoerr 'Condition ' . l:name ' already exists'
		endif
	endif
	if get(a:opts, 'auto', v:false)
		let l:cond['value'] = get(a:opts, 'value', v:false)
		let l:cond['last_value'] = l:cond['value']
		function! s:_getter() closure
			return l:cond['value']
		endfunction
		function! s:_setter(value) closure
			let l:cond['value'] = a:value
		endfunction
		let l:cond['get'] = funcref('s:_getter')
		let l:cond['set'] = funcref('s:_setter')
	else
		let l:cond['get'] = a:opts['get']
		let l:cond['set'] = get(a:opts, 'set', s:no_setter(l:name))
	endif
	let l:cond['on_change'] = [] + s:dict_get_list(a:opts, 'on_change')
	let s:conditions[l:name] = l:cond
	return ''
endfunction

function! vim_partial_modes#define_condition_all(name, names)
	call vim_partial_modes#define_condition({
		\ 'name': a:name,
		\ 'get': {-> index(s:map_array(a:names, {n -> vim_partial_modes#condition_get(n)}), v:false) == -1}
		\ })
	return ''
endfunction

function! vim_partial_modes#define_condition_any(name, names)
	call vim_partial_modes#define_condition({
		\ 'name': a:name,
		\ 'get': {-> index(s:map_array(a:names, {n -> !vim_partial_modes#condition_get(n)}), v:false) != -1}
		\ })
	return ''
endfunction

function! vim_partial_modes#condition_get(name)
	call s:before_condition_index(a:name)
	let l:cond = s:conditions[a:name]
	let l:value = l:cond['get']()
	let l:cond['last_value'] = l:value
	return l:value
	return ''
endfunction

function! vim_partial_modes#condition_set(name, value)
	call s:before_condition_index(a:name)
	let l:cond = s:conditions[a:name]
	call l:cond['set'](a:value)
	if a:value != get(l:cond, 'last_value', !a:value)
		call s:call_all(l:cond['on_change'], a:value)
	endif
	return ''
endfunction

function! vim_partial_modes#condition_toggle(name)
	call vim_partial_modes#condition_set(a:name, vim_partial_modes#condition_get(a:name))
	return ''
endfunction

function! vim_partial_modes#condition_setter(names, value)
	let l:dict = {}
	function dict.f() closure dict
		for l:name in a:names
			call vim_partial_modes#condition_set(l:name, a:value)
		endfor
	endfunction
	return dict['f']
endfunction

function! s:mode_enter(name)
	let l:mode = s:modes[a:name]
	for l:m in l:mode['extends']
		call s:mode_enter(l:m)
	endfor
	call s:call_all(l:mode['on_enter'])
endfunction

function! s:mode_leave(name)
	let l:mode = s:modes[a:name]
	call s:call_all(l:mode['on_leave'])
	for l:m in reverse(copy(l:mode['extends']))
		call s:mode_leave(l:m)
	endfor
endfunction

function! vim_partial_modes#define_mode(opts)
	let l:name = a:opts['name']
	let l:mode = { 'name': l:name }
	if has_key(s:modes, l:name)
		if !get(a:opts, 'override', v:false)
			echoerr 'Mode ' . l:name . ' already exists'
		endif
	endif
	let l:mode['extends'] = [] + s:dict_get_list(a:opts, 'extends')
	let l:mode['on_enter'] = [] + s:dict_get_list(a:opts, 'on_enter')
	let l:mode['on_leave'] = [] + s:dict_get_list(a:opts, 'on_leave')
	let l:mode['display_name'] = get(a:opts, 'display_name', l:name)
	call vim_partial_modes#define_condition({
				\ 'name': 'mode=' . l:name,
				\ 'override': v:true,
				\ 'auto': v:true,
				\ 'on_change': {arg -> arg ? s:mode_enter(l:name) : s:mode_leave(l:name)}
				\ })
	let s:modes[l:name] = l:mode
	let l:token = s:construct_plug_token(['partial-modes', 'push-mode', l:name])
	call s:map_all_modes(l:token, '<expr> vim_partial_modes#mode_push({"name": ' . s:qarg(l:name) . '})')
	return ''
endfunction

function! vim_partial_modes#mode_push(opts)
	let l:name = a:opts['name']
	let l:mode = s:modes[l:name]
	for l:k in keys(s:modes)
		if l:k == l:name
			continue
		endif
		call vim_partial_modes#condition_set('mode=' . l:k, v:false)
	endfor
	call insert(s:mode_stack, { 'name': l:name })
	call vim_partial_modes#condition_set('mode=' . l:name, v:true)
	return ''
endfunction

function! vim_partial_modes#mode_pop()
	if len(s:mode_stack) == 0
		" TODO think more
		call insert(s:mode_stack, { 'name': s:root_mode })
		call feedkeys("\<C-\>\<C-G>", 'n')
	endif
	let l:name = get(s:mode_stack, 1, s:mode_stack[0])['name']
	let l:mode = s:modes[l:name]
	for l:k in keys(s:modes)
		if l:k == l:name
			continue
		endif
		call vim_partial_modes#condition_set('mode=' . l:k, v:false)
	endfor
	call remove(s:mode_stack, 0)
	call vim_partial_modes#condition_set('mode=' . l:name, v:true)
	return ''
endfunction

function! vim_partial_modes#mode_transform(opts)
	if len(s:mode_stack) == 0
		" TODO think more
		call insert(s:mode_stack, { 'name': s:root_mode })
		call feedkeys("\<C-\>\<C-G>", 'n')
	endif
	let l:name = a:opts['name']
	let l:mode = s:modes[l:name]
	for l:k in keys(s:modes)
		if l:k == l:name
			continue
		endif
		call vim_partial_modes#condition_set('mode=' . l:k, v:false)
	endfor
	let s:mode_stack[0] = { 'name': l:name, 'replaces': s:mode_stack[0] }
	call vim_partial_modes#condition_set('mode=' . l:name, v:true)
	return ''
endfunction

call vim_partial_modes#define_condition({
			\ 'name': 'text-insert',
			\ 'auto': v:true
			\ }) 
call vim_partial_modes#define_condition({
			\ 'name': 'cursor-movement',
			\ 'auto': v:true,
			\ 'value': v:true,
			\ })

call vim_partial_modes#define_mode({
			\ 'name': 'normal',
			\ 'display_name': '',
			\ 'on_enter': vim_partial_modes#condition_setter(['cursor-movement', 'no=text-insert'], v:true),
			\ })
call vim_partial_modes#define_mode({
			\ 'name': 'insert',
			\ 'display_name': '',
			\ 'on_enter': vim_partial_modes#condition_setter(['cursor-movement', 'text-insert'], v:true),
			\ })
