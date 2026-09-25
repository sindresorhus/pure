#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

typeset -g who_m_output who_m_status who_output

who() {
	if [[ $1 == -m ]]; then
		print -r -- "$who_m_output"
		return $who_m_status
	fi
	print -r -- "$who_output"
}

prompt_pure_is_inside_container() {
	return 1
}

# Runs the state setup outside SSH with the given `who -m` output, and prints whether the username and host are shown, and whether the detection is exported for nested shells.
detect() {
	who_m_output=$1 who_m_status=${2:-0} who_output=${3-}
	(
		unset SSH_CONNECTION PROMPT_PURE_SSH_CONNECTION
		psvar[13]=
		prompt_pure_state_setup
		print -r -- "${psvar[13]:-0} ${+PROMPT_PURE_SSH_CONNECTION}"
	)
}

# Runs the state setup outside SSH with the given `who -m` output, and prints the remote address recorded for nested shells.
detect_value() {
	who_m_output=$1 who_m_status=${2:-0} who_output=${3-}
	(
		unset SSH_CONNECTION PROMPT_PURE_SSH_CONNECTION
		prompt_pure_state_setup
		print -r -- "$PROMPT_PURE_SSH_CONNECTION"
	)
}

main() {
	# Pure reads optional globals that may be unset.
	set +eu

	if (( UID == 0 )); then
		print -- "ssh-detection tests skipped as root"
		return
	fi

	# `prompt_pure_state_setup` only runs the `who` detection when a real `who` is in `PATH`, as a shell function is not a command.
	if (( ! $+commands[who] )); then
		print -- "ssh-detection tests skipped without a who command"
		return
	fi

	assert_equal "1 0" "$(SSH_CONNECTION='10.0.0.1 1234 10.0.0.2 22' prompt_pure_state_setup; print -r -- "${psvar[13]:-0} ${+PROMPT_PURE_SSH_CONNECTION}")" "SSH_CONNECTION should show the username" || return

	assert_equal "1 1" "$(detect 'user pts/0 2026-09-25 10:00 (192.168.1.2)')" "an IPv4 remote address should be detected" || return
	assert_equal "1 1" "$(detect 'user pts/0 2026-09-25 10:00 (2001:db8::1)')" "an IPv6 remote address should be detected" || return
	assert_equal "1 1" "$(detect 'user pts/0 2026-09-25 10:00 (laptop.example.com)')" "a remote hostname should be detected" || return
	assert_equal "1 1" "$(detect 'user pts/0 00:00 Sep 25 10:00:00 192.168.1.2')" "a remote address without parentheses (busybox) should be detected" || return

	# The whole address is recorded, not a fragment of it, as it is what nested shells detect from.
	assert_equal "(192.168.1.2)" "$(detect_value 'user pts/0 2026-09-25 10:00 (192.168.1.2)')" "an IPv4 remote address should be recorded in full" || return
	assert_equal "(2001:db8::1)" "$(detect_value 'user pts/0 2026-09-25 10:00 (2001:db8::1)')" "a compressed IPv6 remote address should be recorded in full" || return
	assert_equal "(2001:0db8:0000:0000:0000:0000:0000:0001)" "$(detect_value 'user pts/0 2026-09-25 10:00 (2001:0db8:0000:0000:0000:0000:0000:0001)')" "a full IPv6 remote address should be recorded in full" || return

	assert_equal "0 0" "$(detect 'user ttys000 Sep 25 10:00')" "a local terminal should not be detected as SSH" || return
	assert_equal "0 0" "$(detect 'user ttys000 2026-09-25 10:00')" "a local terminal with a date should not be detected as SSH" || return
	# BusyBox `who` prints the login time with seconds; it must not match the simplified IPv6 pattern and be mistaken for a remote address.
	assert_equal "0 0" "$(detect 'root tty1 2026-09-25 10:00:00')" "a local BusyBox console login with seconds should not be detected as SSH" || return
	assert_equal "0 0" "$(detect 'user ttys000 2026-09-25 10:00:00')" "a local terminal with seconds should not be detected as SSH" || return
	assert_equal "0 0" "$(detect 'user pts/0 2026-09-25 10:00 (:0)')" "a local X display should not be detected as SSH" || return
	assert_equal "0 0" "$(detect 'user pts/1 2026-09-25 10:00 (tmux(1234).%0)')" "a tmux pane should not be detected as SSH" || return

	# Fall back to plain `who` for the current TTY when `who -m` is not supported.
	local TTY=/dev/pts/3
	assert_equal "1 1" "$(detect '' 1 $'other pts/1 2026-09-25 09:00 (10.9.9.9)\nuser pts/3 2026-09-25 10:00 (10.1.2.3)')" "plain who should be used for the current TTY" || return
	assert_equal "0 0" "$(detect '' 1 $'other pts/1 2026-09-25 09:00 (10.9.9.9)\nuser pts/3 2026-09-25 10:00')" "other TTYs in plain who should be ignored" || return

	# The detection is kept for nested shells, like in tmux.
	assert_equal "1 1" "$(export PROMPT_PURE_SSH_CONNECTION='(192.168.1.2)'; prompt_pure_state_setup; print -r -- "${psvar[13]:-0} ${+PROMPT_PURE_SSH_CONNECTION}")" "an inherited detection should show the username" || return

	print -- "ssh-detection tests passed"
}

main "$@"
