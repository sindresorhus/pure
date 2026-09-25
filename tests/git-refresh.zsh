#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

typeset -ga queued_jobs queued_commands

async_job() {
	queued_jobs+=("$2")
	queued_commands+=("${(j: :)@[2,-1]}")
}

# Runs a refresh for the repository at /tmp/repository, as from precmd, and records the queued commands.
refresh() {
	queued_commands=()
	prompt_pure_vcs_info[top]=/tmp/repository
	prompt_pure_async_refresh
}

# Feeds a `prompt_pure_async_vcs_info` result for a repository at $1 to the callback, as when entering a new Git repository.
enter_repository() {
	local top=$1
	queued_jobs=()
	typeset -gA prompt_pure_vcs_info=(branch '' top '' action '' pwd '')
	unset prompt_pure_git_fetch_pattern
	typeset -gA prompt_pure_worker_env=(pwd "$PWD" generation 1)
	local -A info=(pwd "$PWD" branch main top "$top" action '')
	prompt_pure_async_callback prompt_pure_async_vcs_info 0 $'1\n'"${(j: :)${(@kvq)info}}" 0 "" 0
}

main() {
	# Pure reads optional globals that may be unset, and `zstyle -t` returns non-zero for unset styles.
	set +eu
	zmodload zsh/datetime zsh/zutil
	zmodload -F zsh/files b:zf_rm b:zf_mkdir

	typeset -g prompt_pure_async_inited=1
	local HOME=$PWD

	enter_repository /tmp/repository
	assert_equal "prompt_pure_async_git_aliases prompt_pure_async_git_arrows prompt_pure_async_git_fetch prompt_pure_async_git_dirty" "$queued_jobs" "entering a repository should queue the refresh jobs" || return
	assert_equal /tmp/repository "$prompt_pure_vcs_info[top]" "entering a repository should store its top-level" || return

	enter_repository $HOME
	assert_equal "prompt_pure_async_git_aliases prompt_pure_async_git_arrows prompt_pure_async_git_dirty" "$queued_jobs" "entering a repository at HOME should not fetch" || return

	# Later refreshes from precmd keep skipping the fetch at HOME.
	queued_jobs=()
	prompt_pure_async_refresh
	assert_equal "prompt_pure_async_git_arrows prompt_pure_async_git_dirty" "$queued_jobs" "refreshing a repository at HOME should not fetch" || return

	# Git reports the top-level with symlinks resolved, so a HOME under a symlink (like `/home` -> `/usr/home` on FreeBSD) should still match.
	# With CHASE_LINKS (for example from `.zshenv`), zsh itself resolves HOME when setting it.
	setopt localoptions nochaselinks
	# The temporary directory lives in the repository, so the test also runs where the system temp directory is not writable.
	local home_link_directory=$PWD/.ai-temporary/pure-home-link-$$
	zf_mkdir -p -- "$home_link_directory"
	command ln -s "$PWD" "$home_link_directory/home"
	HOME=$home_link_directory/home
	enter_repository ${PWD:A}
	HOME=$PWD
	zf_rm -r -- "$home_link_directory"
	assert_equal "prompt_pure_async_git_aliases prompt_pure_async_git_arrows prompt_pure_async_git_dirty" "$queued_jobs" "entering a repository at a symlinked HOME should not fetch" || return

	# Leaving a repository does not refresh.
	enter_repository ''
	assert_equal "" "$queued_jobs" "a result outside a repository should not queue refresh jobs" || return

	# The fetch pattern (from the aliases job) is only looked up once per repository.
	enter_repository /tmp/repository
	refresh
	assert_equal "prompt_pure_async_git_arrows|prompt_pure_async_git_fetch 0|prompt_pure_async_git_dirty 1 0" "${(j:|:)queued_commands}" "default refresh should fetch all remotes and check untracked files" || return

	zstyle ':prompt:pure:git:fetch' only_upstream yes
	zstyle ':prompt:pure:git:dirty' detailed yes
	PURE_GIT_UNTRACKED_DIRTY=0
	refresh
	assert_equal "prompt_pure_async_git_arrows|prompt_pure_async_git_fetch 1|prompt_pure_async_git_dirty 0 1" "${(j:|:)queued_commands}" "refresh should pass the fetch and dirty options" || return
	zstyle -d ':prompt:pure:git:fetch' only_upstream
	zstyle -d ':prompt:pure:git:dirty' detailed
	unset PURE_GIT_UNTRACKED_DIRTY

	PURE_GIT_PULL=0
	refresh
	assert_equal "prompt_pure_async_git_arrows|prompt_pure_async_git_dirty 1 0" "${(j:|:)queued_commands}" "PURE_GIT_PULL=0 should disable the fetch" || return
	unset PURE_GIT_PULL

	# A slow dirty check is cached, and redone after the delay.
	typeset -g prompt_pure_git_last_dirty_check_timestamp=$(( EPOCHSECONDS - 10 ))
	refresh
	assert_equal "prompt_pure_async_git_arrows|prompt_pure_async_git_fetch 0" "${(j:|:)queued_commands}" "a recent slow dirty check should be reused" || return
	PURE_GIT_DELAY_DIRTY_CHECK=5
	refresh
	assert_equal "prompt_pure_async_git_arrows|prompt_pure_async_git_fetch 0|prompt_pure_async_git_dirty 1 0" "${(j:|:)queued_commands}" "the dirty check should run again after the delay" || return
	assert_empty "${prompt_pure_git_last_dirty_check_timestamp-}" "the cached dirty timestamp should be cleared when checking again" || return
	unset PURE_GIT_DELAY_DIRTY_CHECK

	zstyle ':prompt:pure:git:stash' show yes
	refresh
	assert_equal "prompt_pure_async_git_stash" "$queued_commands[-1]" "stash should be counted when enabled" || return
	zstyle -d ':prompt:pure:git:stash' show
	typeset -g prompt_pure_git_stash=1
	refresh
	assert_empty "${prompt_pure_git_stash-}" "stash should be cleared when disabled" || return

	print -- "git-refresh tests passed"
}

main "$@"
