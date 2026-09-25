#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

git_commit() {
	command git -C "$1" -c user.name=Test -c user.email=test@test.com commit -q --allow-empty -m "$2"
}

# Pushes a new commit to the remote from a separate clone, so `work` is one commit behind after a fetch.
push_remote_commit() {
	git_commit "$base_directory/other" "remote change"
	command git -C "$base_directory/other" push -q origin main
}

fetch() {
	: >| "$git_log"
	local fetch_output fetch_code
	# The async worker does not run with `nounset`.
	fetch_output=$(set +u; prompt_pure_async_git_fetch "$@" 2>/dev/null) && fetch_code=0 || fetch_code=$?
	typeset -g check_output=$fetch_output check_code=$fetch_code
	typeset -g fetch_invocations="$(command grep -c ' fetch ' "$git_log")"
}

main() {
	zmodload -F zsh/files b:zf_rm b:zf_mkdir

	typeset -g base_directory=$PWD/.ai-temporary/pure-git-fetch-$$
	trap "zf_rm -rf -- ${(q)base_directory}" EXIT
	zf_mkdir -p -- "$base_directory/bin"

	# Log every Git invocation so the tests can tell whether a fetch ran.
	typeset -g git_log=$base_directory/git.log
	create_logging_git "$base_directory/bin" "$git_log"
	path=("$base_directory/bin" $path)

	builtin cd -q "$base_directory"
	command git init -q --bare --template= -b main remote.git
	command git clone -q --template= remote.git work 2>/dev/null
	git_commit work "initial"
	command git -C work push -q origin main
	command git clone -q --template= remote.git other
	builtin cd -q work

	# The upstream has the same name as the local branch.
	push_remote_commit
	fetch 1
	assert_equal 0 "$check_code" "only_upstream: fetch should succeed for a branch with a same-name upstream"
	assert_equal $'0\t1' "$check_output" "only_upstream: arrows should show the new remote commit"

	# The upstream has a different name than the local branch.
	command git checkout -q -b local-feature --track origin/main
	push_remote_commit
	fetch 1
	assert_equal 0 "$check_code" "only_upstream: fetch should succeed for a branch tracking a differently named upstream"
	assert_equal $'0\t1' "$check_output" "only_upstream: arrows should show the new remote commit for a differently named upstream"

	# The upstream is a local branch.
	command git checkout -q -b track-local --track main
	fetch 1
	assert_equal 0 "$check_code" "only_upstream: fetch should succeed for a branch tracking a local branch"
	assert_equal $'0\t0' "$check_output" "only_upstream: arrows should compare against the local upstream branch"
	assert_equal 1 "$fetch_invocations" "only_upstream: a local upstream should still be fetched"
	assert_equal ". refs/heads/main" "$(command grep ' fetch ' "$git_log" | command awk '{ print $(NF-1), $NF }')" "only_upstream: a local upstream should fetch its own ref from '.'"

	# The upstream is on another remote, and the branch names contain slashes.
	command git -C "$base_directory/other" push -q origin main:refs/heads/team/shared
	command git remote add up-stream ../remote.git
	command git fetch -q up-stream
	command git checkout -q -b feature/local --track up-stream/team/shared
	git_commit "$base_directory/other" "shared change"
	command git -C "$base_directory/other" push -q origin main:refs/heads/team/shared
	command git -C "$base_directory/other" reset -q --hard origin/main
	fetch 1
	assert_equal 0 "$check_code" "only_upstream: fetch should succeed for an upstream on another remote"
	assert_equal $'0\t1' "$check_output" "only_upstream: arrows should show the new commit on another remote"
	assert_equal 1 "$fetch_invocations" "only_upstream: should fetch once"
	assert_equal "up-stream refs/heads/team/shared" "$(command grep ' fetch ' "$git_log" | command awk '{ print $(NF-1), $NF }')" "only_upstream: should fetch only the upstream ref from its remote"

	# No upstream: skip the fetch.
	command git checkout -q -b no-upstream
	fetch 1
	assert_equal 97 "$check_code" "only_upstream: a branch without upstream should skip the fetch"
	assert_equal 0 "$fetch_invocations" "only_upstream: a branch without upstream should not run git fetch"

	# Detached HEAD has no upstream: skip the fetch.
	command git checkout -q --detach main
	fetch 1
	assert_equal 97 "$check_code" "only_upstream: a detached HEAD should skip the fetch"
	assert_equal 0 "$fetch_invocations" "only_upstream: a detached HEAD should not run git fetch"

	# Fetching all remotes is unaffected.
	command git checkout -q main
	push_remote_commit
	fetch 0
	assert_equal 0 "$check_code" "fetch should succeed"
	assert_equal $'0\t3' "$check_output" "arrows should show the new remote commits"

	# SSH command: `GIT_SSH_COMMAND`, `core.sshCommand`, and `GIT_SSH` should be respected in Git's order, with batch mode added.
	local ssh_log=$base_directory/ssh.log
	local ssh_command
	for ssh_command in ssh config-ssh env-ssh program-ssh; do
		print -r -- "#!/bin/sh
printf '%s %s %s\n' '$ssh_command' \"\$1\" \"\$2\" >> '$ssh_log'
exit 1" >| "$base_directory/bin/$ssh_command"
		chmod +x "$base_directory/bin/$ssh_command"
	done
	command git remote set-url origin ssh://example.invalid/remote.git
	unset GIT_SSH_COMMAND GIT_SSH

	: >| "$ssh_log"
	fetch 0
	assert_equal "ssh -o BatchMode=yes" "${"$(<$ssh_log)"%%$'\n'*}" "fetch should use ssh with batch mode by default"

	command git config core.sshCommand config-ssh
	: >| "$ssh_log"
	fetch 0
	assert_equal 99 "$check_code" "fetch through the failing SSH command should fail"
	assert_equal "config-ssh -o BatchMode=yes" "${"$(<$ssh_log)"%%$'\n'*}" "fetch should use core.sshCommand with batch mode"

	: >| "$ssh_log"
	GIT_SSH_COMMAND=env-ssh fetch 0
	assert_equal "env-ssh -o BatchMode=yes" "${"$(<$ssh_log)"%%$'\n'*}" "GIT_SSH_COMMAND should take precedence over core.sshCommand"

	# `core.sshCommand` also takes precedence over `GIT_SSH`.
	: >| "$ssh_log"
	GIT_SSH=$base_directory/bin/program-ssh fetch 0
	assert_equal "config-ssh -o BatchMode=yes" "${"$(<$ssh_log)"%%$'\n'*}" "core.sshCommand should take precedence over GIT_SSH"
	command git config --unset core.sshCommand

	# `GIT_SSH` is a program that Git calls with its own arguments, so it cannot get batch mode, but it should still be used.
	: >| "$ssh_log"
	GIT_SSH=$base_directory/bin/program-ssh fetch 0
	assert_equal "program-ssh" "${${"$(<$ssh_log)"%%$'\n'*}%% *}" "fetch should use GIT_SSH"

	print -- "git-fetch tests passed"
}

main "$@"
