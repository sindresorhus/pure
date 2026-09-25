#!/usr/bin/env zsh

set -euo pipefail

cd -- "${0:A:h}/.."

set +e
set +u
zstyle ':prompt:pure:title' show no
source ./pure.zsh >/dev/null 2>&1

assert_equal() {
	local expected=$1
	local actual=$2
	local message=$3

	if [[ $expected != $actual ]]; then
		print -u2 -- "Assertion failed: $message"
		print -u2 -- "Expected: $expected"
		print -u2 -- "Actual:   $actual"
		return 1
	fi
}

main() {
	typeset -gA prompt_pure_state=(
		prompt '❯'
	)
	typeset -gA prompt_pure_vcs_info=(
		branch ''
		action ''
	)
	typeset -g prompt_pure_git_branch_color=242
	typeset -g prompt_pure_precustom_step=0
	typeset -g prompt_pure_reset_prompt_count=0

	prompt_pure_precustom() {
		if (( prompt_pure_precustom_step == 0 )); then
			psvar[22]='a|b'
			psvar[23]=c
		else
			psvar[22]=a
			psvar[23]='b|c'
		fi
	}

	prompt_pure_reset_prompt() {
		(( ++prompt_pure_reset_prompt_count ))
	}

	prompt_pure_preprompt_render precmd
	(( prompt_pure_precustom_step++ ))
	prompt_pure_preprompt_render

	assert_equal 1 $prompt_pure_reset_prompt_count "prompt fingerprint should distinguish separators inside custom prompt parts" || return

	# A `%` in the prompt symbol must render literally, not as a prompt escape.
	# `print -P "$PROMPT"` uses the same expansion as the real ZLE prompt, so a symbol like `a%b` must not be read as a bold escape.
	# Render in a fresh shell because PURE_PROMPT_SYMBOL is read when Pure sets up the prompt.
	local symbol rendered
	# A trailing `%` must not consume the `%f` that resets the color after the symbol.
	for symbol in 'a%b' '100%' '%F{red}x'; do
		rendered=$(PURE_PROMPT_SYMBOL=$symbol zsh -fc '
			zstyle ":prompt:pure:title" show no
			source ./pure.zsh >/dev/null 2>&1
			typeset -gA prompt_pure_vcs_info=(branch "" action "")
			print -P -r -- "$PROMPT"
		' 2>/dev/null)
		# Strip color escapes so only the visible symbol text remains.
		rendered=${rendered//$'\e'\[[0-9;]#m/}
		if [[ $rendered != *"$symbol"* ]]; then
			print -u2 -- "Assertion failed: prompt symbol '$symbol' should render literally"
			print -u2 -- "Rendered: $rendered"
			return 1
		fi
	done

	print -- "prompt-fingerprint tests passed"
}

main "$@"
