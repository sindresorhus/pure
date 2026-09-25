#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

human_time() {
	local result
	prompt_pure_human_time_to_var $1 result
	print -r -- $result
}

git_arrows() {
	local REPLY=
	prompt_pure_check_git_arrows "$@"
	print -r -- $REPLY
}

vim_symbol() {
	local KEYMAP=$1
	prompt_pure_update_vim_prompt_widget
	print -r -- $prompt_pure_state[prompt]
}

main() {
	# Pure reads optional globals that may be unset, and some helpers return non-zero to signal "nothing to show".
	set +eu
	zmodload zsh/datetime

	assert_equal "0s" "$(human_time 0)" "zero seconds" || return
	assert_equal "59s" "$(human_time 59)" "seconds only" || return
	assert_equal "1m 0s" "$(human_time 60)" "a full minute keeps the seconds" || return
	assert_equal "1h 0s" "$(human_time 3600)" "zero minutes are skipped" || return
	assert_equal "1d 0s" "$(human_time 86400)" "zero hours are skipped" || return
	assert_equal "1d 21h 56m 32s" "$(human_time 165392)" "all units" || return

	# The execution time is only shown above the threshold.
	typeset -g prompt_pure_cmd_timestamp=$(( EPOCHSECONDS - 5 ))
	prompt_pure_check_cmd_exec_time
	assert_empty "$prompt_pure_cmd_exec_time" "an execution time at the default threshold should not be shown" || return
	typeset -g prompt_pure_cmd_timestamp=$(( EPOCHSECONDS - 10 ))
	prompt_pure_check_cmd_exec_time
	assert_equal "10s" "$prompt_pure_cmd_exec_time" "an execution time above the default threshold should be shown" || return
	PURE_CMD_MAX_EXEC_TIME=20 prompt_pure_check_cmd_exec_time
	assert_empty "$prompt_pure_cmd_exec_time" "PURE_CMD_MAX_EXEC_TIME should raise the threshold" || return
	unset prompt_pure_cmd_timestamp
	prompt_pure_check_cmd_exec_time
	assert_empty "$prompt_pure_cmd_exec_time" "no execution time should be shown without a command" || return

	# Arrows from `git rev-list --left-right --count` output: ahead, then behind.
	assert_empty "$(git_arrows 0 0)" "no arrows when in sync" || return
	assert_equal "⇡" "$(git_arrows 1 0)" "ahead" || return
	assert_equal "⇣" "$(git_arrows 0 2)" "behind" || return
	assert_equal "⇣⇡" "$(git_arrows 3 4)" "diverged shows the down arrow first" || return
	assert_equal "vʌ" "$(PURE_GIT_UP_ARROW=ʌ PURE_GIT_DOWN_ARROW=v git_arrows 1 1)" "custom arrows" || return

	typeset -gA prompt_pure_state
	assert_equal "❮" "$(vim_symbol vicmd)" "vicmd keymap" || return
	assert_equal "❮" "$(vim_symbol visual)" "visual keymap" || return
	assert_equal "❯" "$(vim_symbol viins)" "viins keymap" || return
	assert_equal "❯" "$(vim_symbol main)" "main keymap" || return
	# Other keymaps (like `zle -K emacs` or a custom one) should not be shown as text.
	assert_equal "❯" "$(vim_symbol emacs)" "emacs keymap" || return
	assert_equal "❯" "$(vim_symbol my-keymap)" "custom keymap" || return
	assert_equal "❯" "$(vim_symbol .safe)" "fallback keymap" || return
	assert_equal "N" "$(PURE_PROMPT_VICMD_SYMBOL=N vim_symbol vicmd)" "custom vicmd symbol" || return
	# The stored symbol is escaped, so a `%` in it renders literally in the prompt.
	assert_equal "%%b" "$(PURE_PROMPT_VICMD_SYMBOL='%b' vim_symbol vicmd)" "a percent in the vicmd symbol should be escaped" || return
	assert_equal "%%b" "$(PURE_PROMPT_SYMBOL='%b' vim_symbol viins)" "a percent in the prompt symbol should be escaped" || return
	# A symbol that contains a keymap name is used as is.
	assert_equal "[visual]" "$(PURE_PROMPT_VICMD_SYMBOL='[visual]' vim_symbol vicmd)" "custom vicmd symbol with a keymap name" || return
	assert_equal ">" "$(PURE_PROMPT_SYMBOL='>' vim_symbol viins)" "custom prompt symbol" || return
	prompt_pure_state[prompt]=❮
	prompt_pure_reset_vim_prompt_widget
	assert_equal "❯" "$prompt_pure_state[prompt]" "the prompt symbol should be reset when the line is finished" || return

	print -- "prompt-helpers tests passed"
}

main "$@"
