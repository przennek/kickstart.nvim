" A clipboard for tests: copy / paste never touch the system clipboard
let g:clipboard = {'name': 'test', 'copy': {'+': {lines, regtype -> extend(g:, {'test_clip': [lines, regtype]})}, '*': {lines, regtype -> extend(g:, {'test_clip': [lines, regtype]})}}, 'paste': {'+': {-> get(g:, 'test_clip', [])}, '*': {-> get(g:, 'test_clip', [])}}}

" tests: the agent terminal is a plain shell, no agent started (pc.prompt_file)
let g:pc_agent_cmd = v:false
