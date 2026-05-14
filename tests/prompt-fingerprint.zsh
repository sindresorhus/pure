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

	print -- "prompt-fingerprint tests passed"
}

main "$@"
