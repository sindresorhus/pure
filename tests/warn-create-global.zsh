#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

main() {
	# Load Pure without `promptinit` (like plugin managers do) and drive the main code paths with `WARN_CREATE_GLOBAL` on, which warns about globals created without `typeset -g`.
	local output
	output=$(command zsh -fc '
		setopt warncreateglobal
		source ./async.zsh
		source ./pure.zsh
		async_worker_eval() {
			:
		}
		async_job() {
			:
		}
		async_flush_jobs() {
			:
		}
		prompt_pure_async_init() {
			typeset -g prompt_pure_async_inited=1
		}
		prompt_pure_set_title() {
			:
		}
		prompt_pure_precmd
		prompt_pure_preexec "git pull" "git pull" "git pull"
		local generation=${prompt_pure_worker_env[generation]}
		prompt_pure_async_callback "[async/eval]" 0 "$generation" 0 "" 0
		prompt_pure_async_callback prompt_pure_async_vcs_info 0 "$generation"$'\''\n'\''"branch main top ${(q)PWD} pwd ${(q)PWD} action rebase" 0 "" 0
		prompt_pure_async_callback prompt_pure_async_git_aliases 0 "$generation"$'\''\nup'\'' 0 "" 0
		# A dirty check slower than 5 seconds caches the result.
		prompt_pure_async_callback prompt_pure_async_git_dirty 1 "$generation"$'\''\n*'\'' 6 "" 0
		prompt_pure_async_callback prompt_pure_async_git_arrows 0 "$generation"$'\''\n1\t2'\'' 0 "" 0
		prompt_pure_async_callback prompt_pure_async_git_fetch 97 "$generation" 0 "" 0
		prompt_pure_async_callback prompt_pure_async_git_stash 0 "$generation"$'\''\n1'\'' 0 "" 0
		KEYMAP=vicmd prompt_pure_update_vim_prompt_widget
		prompt_pure_reset_vim_prompt_widget
		prompt_pure_system_report >/dev/null
		prompt_pure_preview >/dev/null
	' 2>&1 >/dev/null)

	assert_empty "${(M)${(f)output}:#*created globally*}" "Pure should not create globals without typeset -g"

	print -- "warn-create-global tests passed"
}

main "$@"
