#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

typeset -g flush_count=0

async_flush_jobs() {
	(( ++flush_count ))
}

prompt_pure_set_title() {
	:
}

# Asserts whether running the command line in $1 cancels Pure's background jobs, as needed for a user-issued pull or fetch.
assert_flushes() {
	local command_line=$1 expected=$2
	flush_count=0
	prompt_pure_preexec "$command_line" "$command_line" "$command_line"
	assert_equal "$expected" "$flush_count" "'$command_line' should flush async jobs $expected time(s)"
}

main() {
	# Pure reads optional globals that may be unset.
	set +u
	zmodload -F zsh/files b:zf_rm b:zf_mkdir
	zmodload zsh/datetime

	local repository=$PWD/.ai-temporary/pure-preexec-$$
	trap "zf_rm -rf -- ${(q)repository}" EXIT
	zf_mkdir -p -- "$repository"
	builtin cd -q "$repository"

	# Only the aliases of this repository are used, as the test helper ignores the user's Git config.
	command git init -q --template=
	command git config alias.up 'pull --rebase'
	command git config alias.pullAll 'pull --all'
	command git config alias.sync '!git fetch origin && git rebase'
	command git config alias.pr pull-request
	command git config alias.get-latest 'fetch --prune'
	# Alias values can span multiple lines.
	command git config alias.multi $'!f() {\n\tgit pull\n}; f'

	local aliases=$(prompt_pure_async_git_aliases)
	assert_equal "up|pullall|sync|get-latest|multi" "$aliases" "only aliases that pull or fetch should be detected"
	typeset -g prompt_pure_git_fetch_pattern="pull|fetch|$aliases"

	assert_flushes 'git pull' 1
	assert_flushes 'git up' 1
	# Git alias names are case-insensitive.
	assert_flushes 'git pullAll' 1
	assert_flushes 'git PULLALL --rebase' 1
	assert_flushes 'git sync' 1
	assert_flushes 'git multi' 1
	assert_flushes 'git get-latest' 1
	assert_flushes 'git fetch --all' 1
	assert_flushes 'git -C ~/project pull --rebase' 1
	assert_flushes 'hub pull' 1
	assert_flushes 'cd project && git pull' 1

	# A pull or fetch must also be detected when it is followed by a shell delimiter instead of a space, so the background fetch is still cancelled.
	assert_flushes 'git pull; echo done' 1
	assert_flushes 'git fetch; git status' 1
	assert_flushes 'git pull | tee log' 1
	assert_flushes 'git up; echo hi' 1
	assert_flushes 'hub pull; echo done' 1
	assert_flushes $'git pull\necho done' 1
	assert_flushes 'git pull --rebase; git push' 1
	assert_flushes 'git pull)' 1
	assert_flushes '(git pull)' 1
	assert_flushes '$(git pull)' 1

	# Other commands, including ones that only contain the words, should not flush.
	assert_flushes 'git push' 0
	assert_flushes 'git log --oneline' 0
	assert_flushes 'git pullrequest' 0
	assert_flushes 'git pull-request' 0
	assert_flushes 'git upgrade' 0
	assert_flushes 'git pr' 0
	assert_flushes 'git log --grep git' 0
	assert_flushes 'pull' 0
	assert_flushes 'echo fetch' 0
	assert_flushes 'git fetchall' 0

	# Without a fetch pattern (outside a Git repository, or with Git integration disabled), nothing is flushed.
	unset prompt_pure_git_fetch_pattern
	assert_flushes 'git pull' 0

	# The command start time is recorded for the execution time.
	unset prompt_pure_cmd_timestamp
	prompt_pure_preexec 'ls' 'ls' 'ls'
	assert_equal "$EPOCHSECONDS" "${prompt_pure_cmd_timestamp-}" "preexec should record the command start time"

	print -- "preexec tests passed"
}

main "$@"
