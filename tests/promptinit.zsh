#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

main() {
	# Pure reads optional globals that may be unset.
	set +eu
	zmodload -F zsh/files b:zf_rm b:zf_mkdir

	# The documented install path: put Pure in `fpath`, let `promptinit` autoload `prompt_pure_setup`, then run `prompt pure`.
	local themes_directory=$PWD/.ai-temporary/pure-promptinit-$$
	trap "zf_rm -rf -- ${(q)themes_directory}" EXIT
	zf_mkdir -p -- "$themes_directory"
	command ln -s "$PWD/pure.zsh" "$themes_directory/prompt_pure_setup"

	# stderr is silenced because `async` is not installed next to Pure here, which `prompt_pure_setup` autoloads.
	# An empty or unexpected output still fails the assertions below.
	local output
	output=$(PURE_THEMES_DIRECTORY=$themes_directory command zsh -fc '
		zstyle ":prompt:pure:title" show no
		fpath=($PURE_THEMES_DIRECTORY $PWD $fpath)
		autoload -U promptinit; promptinit
		prompt pure
		print -r -- "promptpercent=${options[promptpercent]:-no} promptsubst=${options[promptsubst]:-no}"
		typeset -gA prompt_pure_vcs_info=(branch "" action "")
		print -P -r -- "$PROMPT"
	' 2>/dev/null)

	# `prompt` applies the options Pure asks for through `prompt_opts`, in the scope of the prompt setup function.
	assert_equal "promptpercent=on promptsubst=on" "${output%%$'\n'*}" "Pure should request the prompt options it needs through promptinit" || return

	# Without those options the prompt is printed as text, with its `%` escapes visible.
	local prompt=${output#*$'\n'}
	if [[ $prompt == *'%'* ]]; then
		print -u2 -- "Assertion failed: the prompt should be expanded, not printed with its escapes"
		print -u2 -- "Prompt: $prompt"
		return 1
	fi
	if [[ $prompt != *$'\e['*'❯'* ]]; then
		print -u2 -- "Assertion failed: the expanded prompt should be colored and end in the prompt symbol"
		print -u2 -- "Prompt: $prompt"
		return 1
	fi

	print -- "promptinit tests passed"
}

main "$@"
