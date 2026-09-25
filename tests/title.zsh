#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

# test-helper chdirs to the project root, so this is where pure.zsh lives.
typeset -g pure_zsh_path=$PWD/pure.zsh

# prompt_pure_set_title only writes when standard output is a terminal, so its output cannot be captured with a command substitution.
# Run a direct title call in a pseudo-terminal (where stdout is a real terminal) instead, bracketed by markers, and return whatever the call wrote between them.
# Returns non-zero if zpty could not be used.
title_in_pty() {
	local call=$1
	export PURE_TITLE_TEST_ZSH=$pure_zsh_path
	zmodload zsh/zpty 2>/dev/null || return 1
	zpty __pure_title "source \"\$PURE_TITLE_TEST_ZSH\" >/dev/null 2>&1
print -n __M__
$call
print -n __E__" 2>/dev/null || return 1
	local output="" chunk
	integer attempts=0
	while (( attempts < 1000 )); do
		zpty -r -t __pure_title chunk 2>/dev/null && output+=$chunk
		[[ $output == *'__E__'* ]] && break
		(( ++attempts ))
		sleep 0.003
	done
	zpty -d __pure_title 2>/dev/null
	[[ $output == *'__M__'*'__E__'* ]] || return 1
	local inner=${output#*__M__}
	inner=${inner%%__E__*}
	# The terminal adds carriage returns; drop them.
	print -rn -- ${inner//$'\r'/}
}

# Asserts that the title call in $2 writes nothing. The status of the pseudo-terminal call is checked too, so a failure to run it is not mistaken for an unset title.
assert_no_title() {
	local description=$1 call=$2 title_output
	title_output=$(title_in_pty "$call") || {
		print -u2 -- "Assertion failed: the title call did not run in a pseudo-terminal ($description)"
		return 1
	}
	assert_empty "$title_output" "$description"
}

main() {
	set +u
	zmodload -F zsh/files b:zf_rm

	# Content assertions. If zpty is unavailable these are skipped with a warning, as they need a real terminal on standard output; the critical output-corruption check below always runs.
	if title_in_pty "builtin cd -q /usr; prompt_pure_set_title expand-prompt '%~'" >/dev/null 2>&1; then
		local hostname=${(%):-%m}
		# While a command runs, the title shows the current directory name and the command.
		assert_equal $'\e]0;usr: ls -la\a' "$(title_in_pty "builtin cd -q /usr; prompt_pure_preexec 'ls -la' 'ls -la' 'ls -la'")" "title should show the directory name and command" || return
		# The root directory has no name, so show `/`.
		assert_equal $'\e]0;/: ls\a' "$(title_in_pty "builtin cd -q /; prompt_pure_preexec ls ls ls")" "title should show / for the root directory" || return
		# At the prompt, the title shows the full path.
		assert_equal $'\e]0;/usr\a' "$(title_in_pty "builtin cd -q /usr; prompt_pure_set_title expand-prompt '%~'")" "title should show the path at the prompt" || return
		# Remote sessions prefix the hostname, unless host display is disabled.
		assert_equal $'\e]0;('"$hostname"$'\) /usr\a' "$(title_in_pty "builtin cd -q /usr; psvar[13]=1; prompt_pure_set_title expand-prompt '%~'")" "title should show the hostname when the username is shown" || return
		assert_equal $'\e]0;/usr\a' "$(title_in_pty "builtin cd -q /usr; psvar[13]=1; typeset -gA prompt_pure_state=(show_host 0); prompt_pure_set_title expand-prompt '%~'")" "title should not show the hostname when host display is disabled" || return
		# The command is not expanded as a prompt.
		assert_equal $'\e]0;usr: print %~\a' "$(title_in_pty "builtin cd -q /usr; prompt_pure_preexec 'print %~' 'print %~' 'print %~'")" "title should show the command literally" || return
		# Cases where the title is not set.
		assert_no_title "title should not be set inside Emacs" "builtin cd -q /usr; INSIDE_EMACS=vterm prompt_pure_set_title expand-prompt '%~'" || return
		assert_no_title "title should not be set over a serial console" "builtin cd -q /usr; TTY=/dev/ttyS0 prompt_pure_set_title expand-prompt '%~'" || return
		assert_no_title "title should not be set when disabled" "builtin cd -q /usr; zstyle ':prompt:pure:title' show no; prompt_pure_set_title expand-prompt '%~'" || return
	else
		print -u2 -- "Warning: zpty unavailable, skipping the pty title content assertions"
	fi

	# The bug: a non-interactive script that sources Pure must not have its output polluted with title escape sequences, even when run with standard output redirected to a file.
	local sandbox=$(mktemp -d "${TMPDIR:-/tmp}/pure-title.XXXXXX")
	trap "zf_rm -rf -- ${(q)sandbox}" EXIT
	print -r -- 'source "$1"
print -r -- "id,name"' > "$sandbox/script.zsh"
	local script_output=$(zsh "$sandbox/script.zsh" "$pure_zsh_path" </dev/null 2>/dev/null)
	assert_equal $'id,name' "$script_output" "a non-interactive script's output should not contain title escape sequences"

	print -- "title tests passed"
}

main "$@"
