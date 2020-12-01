function! vim_partial_modes#init()
	return ''
endfunction

let s:conditions = {}
let s:modes = {}
let s:mode_stack = []
let s:root_mode = 'normal'
let s:actions = {}
let s:priorities = {
	\ 'default': -100,
	\ 'standard': 0,
	\ 'mode': 50,
	\ 'synonym': 100,
	\ }

function! s:priority_get(name)
	let l:names = split(a:name, '\ze+')
	let l:res = 0
	for l:name in l:names
		let l:res += get(s:priorities, a:name, 0)
	endfor
	return l:res
endfunction

function! s:priority_compare(lhs, rhs)
	return s:priority_get(a:rhs) - get(a:lhs)
endfunction

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

function! vim_partial_modes#escape_ltgt(str)
	" TODO add more from |key-notation|
	let l:str = a:str
	for [l:pat, l:code] in [['<', 'lt'], ['\\', 'Bslash'], ['|', 'Bar'], ['\r', 'CR'], [' ', 'Space'], ["\<plug>", 'Plug']]
		let l:str = substitute(l:str, l:pat, '<' . l:code . '>', 'g')
	endfor
	return l:str
endfunction

function! s:construct_plug_token(words)
	return "\<Plug>(" . join(s:map_array(a:words, {w -> escape(w, ' )\')}), ' ') . ")"
endfunction

function! s:map_all_modes(lhs, rhs, ...)
	let l:infix = ''
	let l:modes = [['', ''], ['', '!'], ['t', '']]
	let l:arguments = []
	if a:0
		let l:infix = get(a:1, 'infix', '')
		let l:modes = get(a:1, 'modes', l:modes)
		let l:arguments = get(a:1, 'arguments', l:arguments)
	endif
	let l:arg = ' ' . join(s:map_array(l:arguments, { x -> '<' . x . '> ' }), '') . vim_partial_modes#escape_ltgt(a:lhs) . (l:infix == 'un' ? '' : ' ' . vim_partial_modes#escape_ltgt(a:rhs))
	for [l:pre, l:post] in l:modes
		execute l:pre . l:infix . 'map' . l:post . l:arg
	endfor
endfunction

function! s:qarg(arg)
	return '"' . tr(escape(a:arg, '"\' . "\r\n"), "\r\n", 'rn') . '"'
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

let s:inside_au = v:false
function! vim_partial_modes#condition_get(name)
	if !s:inside_au
		let s:inside_au = v:true
		doau User partial_modes_BeforeConditionGet
		let s:inside_au = v:false
	endif
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

function! vim_partial_modes#condition_has_all(names)
	return index(s:map_array(a:names, {n -> vim_partial_modes#condition_get(n)}), v:false) == -1
endfunction

function! vim_partial_modes#condition_has_any(names)
	return index(s:map_array(a:names, {n -> !vim_partial_modes#condition_get(n)}), v:false) != -1
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
	call s:map_all_modes(l:token, 'vim_partial_modes#mode_push({"name": ' . s:qarg(l:name) . '})', { 'arguments': ['expr'] })
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

function! vim_partial_modes#define_action(opts)
	let l:name = a:opts['name']
	let l:action = { 'name': l:name, 'maps': {} }
	if has_key(s:actions, l:name)
		if !get(a:opts, 'override', v:false)
			echoerr 'Action ' . l:name . ' already exists'
		endif
	endif
	let l:action['on_expand'] = [] + s:dict_get_list(a:opts, 'on_expand')
	let l:map_infix  = get(a:opts, 'map_infix', '')
	let s:actions[l:name] = l:action
	let l:token = s:construct_plug_token(['partial-modes', 'expand-action', l:name])
	call s:map_all_modes(l:token, 'vim_partial_modes#action_expand({"name": ' . s:qarg(l:name) . '})', { 'infix': l:map_infix, 'arguments': ['expr'] })
	return l:token
endfunction

function! vim_partial_modes#manage_key(opts)
	let l:key = a:opts['key']
	let l:action_name = 'key=' . l:key
	if !has_key(s:actions, l:action_name)
		let l:token_key = vim_partial_modes#define_action({
					\ 'name': l:action_name,
					\ })
		let l:token_norekey = vim_partial_modes#define_action({
					\ 'name': 'nore' . l:action_name,
					\ 'map_infix': 'nore',
					\ })
		call vim_partial_modes#action_map({
					\ 'name': l:action_name,
					\ 'rhs': l:token_norekey,
					\ 'priority': 'default',
					\ })
		call vim_partial_modes#action_map({
					\ 'name': 'nore' . l:action_name,
					\ 'rhs': l:key,
					\ 'priority': 'synonym',
					\ })
	endif
	let l:token_key = s:construct_plug_token(['partial-modes', 'expand-action', l:action_name])
	let l:controller = { 'key': l:key, 'action_name': l:action_name }
	function controller.enable_for_buffer() closure
		call s:map_all_modes(l:key, l:token_key, { 'arguments': ['buffer'] })
	endfunction
	function controller.disable_for_buffer() closure
		call s:map_all_modes(l:key, '', { 'infix': 'un', 'arguments': ['buffer'] })
	endfunction
	function controller.enable_global() closure
		call s:map_all_modes(l:key, l:token_key)
	endfunction
	function controller.disable_global() closure
		call s:map_all_modes(l:key, '', { 'infix': 'un' })
	endfunction
	return l:controller
endfunction

function! vim_partial_modes#action_map(opts)
	let l:name = a:opts['name']
	let l:rhs = a:opts['rhs']
	let l:action = s:actions[l:name]
	let l:priority = get(a:opts, 'priority', 'standard')
	let l:conditions = s:dict_get_list(a:opts, 'conditions')
	let l:queue = get(l:action['maps'], l:priority, [])
	call insert(l:queue, { 'conditions': l:conditions, 'rhs': l:rhs })
	let l:action['maps'][l:priority] = l:queue
	return ''
endfunction

function! vim_partial_modes#action_expand(opts)
	let l:name = a:opts['name']
	let l:action = s:actions[l:name]
	let l:maps = l:action['maps']
	let l:priorities = sort(keys(l:maps), funcref('s:priority_compare'))
	for l:p in l:priorities
		for l:m in l:maps[l:p]
			if vim_partial_modes#condition_has_all(l:m['conditions'])
				return l:m['rhs']
			endif
		endfor
	endfor
	return ''
endfunction

call vim_partial_modes#define_condition({
			\ 'name': 'track-native-mode',
			\ 'auto': v:true,
			\ 'value': v:true
			\ }) 
call vim_partial_modes#define_condition({
			\ 'name': 'inside-native-mode',
			\ 'auto': v:true,
			\ 'value': v:true
			\ }) 
call vim_partial_modes#define_condition({
			\ 'name': 'cursor-movement',
			\ 'auto': v:true,
			\ 'value': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'cursorsnap-letters',
			\ 'auto': v:true,
			\ 'value': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'selection',
			\ 'auto': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'text-input',
			\ 'auto': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'input-inserts',
			\ 'auto': v:true,
			\ 'value': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'raw-input',
			\ 'auto': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'text-input-custom',
			\ 'auto': v:true
			\ }) 
call vim_partial_modes#define_condition({
			\ 'name': 'cursor-movement-custom',
			\ 'auto': v:true,
			\ 'value': v:true,
			\ })

call vim_partial_modes#define_condition({
			\ 'name': 'operator-force=char',
			\ 'auto': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'operator-force=line',
			\ 'auto': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'operator-force=block',
			\ 'auto': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'visual-type=char',
			\ 'auto': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'visual-type=line',
			\ 'auto': v:true,
			\ })
call vim_partial_modes#define_condition({
			\ 'name': 'visual-type=block',
			\ 'auto': v:true,
			\ })

call vim_partial_modes#define_mode({
			\ 'name': 'normal',
			\ 'display_name': '',
			\ 'on_enter': vim_partial_modes#condition_setter(['inside-native-mode', 'cursor-movement', 'cursorsnap-letters', 'no=text-input'], v:true),
			\ })
call vim_partial_modes#define_mode({
			\ 'name': 'insert',
			\ 'on_enter': vim_partial_modes#condition_setter(['inside-native-mode', 'cursor-movement', 'cursorsnap-letters', 'text-input', 'input-inserts'], v:true),
			\ })
call vim_partial_modes#define_mode({
			\ 'name': 'replace',
			\ 'on_enter': vim_partial_modes#condition_setter(['inside-native-mode', 'cursor-movement', 'cursorsnap-letters', 'text-input', 'no=input-inserts'], v:true),
			\ })
call vim_partial_modes#define_mode({
			\ 'name': 'terminal',
			\ 'on_enter': vim_partial_modes#condition_setter(['inside-native-mode', 'text-input', 'input-inserts', 'raw-input'], v:true),
			\ })
call vim_partial_modes#define_mode({
			\ 'name': 'visual',
			\ 'on_enter': vim_partial_modes#condition_setter(['inside-native-mode', 'selection', 'cursor-movement', 'cursorsnap-letters'], v:true),
			\ })
call vim_partial_modes#define_mode({
			\ 'name': 'select',
			\ 'on_enter': vim_partial_modes#condition_setter(['inside-native-mode', 'selection', 'cursor-movement', 'cursorsnap-letters', 'text-input', 'input-inserts'], v:true),
			\ })

function! s:parse_visual_mode_char(ch)
	return get({
		\     'v' : ['visual', 'char'],
		\     'V' : ['visual', 'line'],
		\ "\<c-v>": ['visual', 'block'],
		\     's' : ['select', 'char'],
		\     'S' : ['select', 'line'],
		\ "\<c-s>": ['select', 'block'],
		\ }, a:ch, ['', ''])
endfunction
let s:last_native_mode = mode(1)
function! vim_partial_modes#handle_native_mode_change()
	let l:mode = mode(1)
	let l:top_mode = get(s:mode_stack, 0, {'name': s:root_mode})['name']
	let l:modes = s:map_array(s:mode_stack, {x -> x['name']})
	if l:mode == s:last_native_mode
		return ''
	endif
	if l:mode[0] == 'n'
		if l:mode[1] == 'o'
			let l:force_type = index(['char', 'line', 'block', ''], s:parse_visual_mode_char(l:mode[2])[1])
			let l:type_states = [v:false, v:false, v:false, v:null]
			let l:type_states[l:force_type] = v:true
			call vim_partial_modes#condition_set('operator-force=char', l:type_states[0])
			call vim_partial_modes#condition_set('operator-force=line', l:type_states[1])
			call vim_partial_modes#condition_set('operator-force=block', l:type_states[2])
			if index(l:modes, 'operator') == -1
				call vim_partial_modes#mode_push({ 'name': 'operator' })
			else
				while s:mode_stack[0]['name'] != 'operator'
					call vim_partial_modes#mode_pop()
				endwhile
			endif
		else
			if l:mode[1] == 'i'
				if index(l:modes, 'normal', 1)[:-2] == -1
					call vim_partial_modes#mode_push({ 'name': 'normal' })
				else
					while s:mode_stack[0]['name'] != 'normal'
						call vim_partial_modes#mode_pop()
					endwhile
				endif
			endif
			while len(s:mode_stack) > 1 && s:mode_stack[0]['name'] != 'normal'
				call vim_partial_modes#mode_pop()
			endwhile
			if len(s:mode_stack) == 0
				call vim_partial_modes#mode_push({ 'name': 'normal' })
			elseif s:mode_stack[0]['name'] != 'normal'
				call vim_partial_modes#mode_transform({ 'name': 'normal' })
				" FIXME do not contantly accumulate transformations
			endif
		endif
	else
		let l:visual_pair = s:parse_visual_mode_char(l:mode[0])
		let l:name = l:visual_pair[0]
		if l:name != ''
			let l:visual_type = index(['char', 'line', 'block'], l:visual_pair[1])
			let l:type_states = [v:false, v:false, v:false]
			let l:type_states[l:visual_type] = v:true
			call vim_partial_modes#condition_set('visual-type=char', l:type_states[0])
			call vim_partial_modes#condition_set('visual-type=line', l:type_states[1])
			call vim_partial_modes#condition_set('visual-type=block', l:type_states[2])
		else
			let l:name = get({
				\ 'i': 'insert',
				\ 'R': 'replace',
				\ 't': 'terminal',
				\}, l:mode[0], '')
		endif
		if l:name != ''
			while len(s:mode_stack) > 1 && index(['normal', 'visual', 'select', 'insert', 'replace', 'terminal'], s:mode_stack[0]['name']) == -1
				call vim_partial_modes#mode_pop()
			endwhile
			call vim_partial_modes#mode_transform({ 'name': l:name })
		elseif l:mode[0] == 'c'
			call vim_partial_modes#mode_push({ 'name': 'command' })
		else
			return ''
		endif
	endif
	let s:last_native_mode = l:mode
endfunction

aug partial_modes
	au!
	au User partial_modes_BeforeConditionGet if vim_partial_modes#condition_get('track-native-mode') | call vim_partial_modes#handle_native_mode_change() | endif
aug END

call vim_partial_modes#handle_native_mode_change()
