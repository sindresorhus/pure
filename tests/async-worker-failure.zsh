#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"
set +e
zmodload -F zsh/files b:zf_rm b:zf_mkdir

main() {
	test_no_infinite_recursion_on_worker_failure || return
	test_worker_startup_failure_clears_git_state || return
	test_git_jobs_queued_same_precmd_as_dir_change || return
	test_git_environment_change_clears_stale_git_state || return
	test_worker_sync_preserves_explicit_empty_git_variables || return
	test_worker_sync_quotes_working_directory || return
	test_worker_env_change_clears_cache_after_eval_failure || return
	test_worker_sync_enqueue_failure_clears_git_state || return
	test_sync_recovery_preserves_replacement_worker_cache || return
	test_stale_git_callback_ignored_during_worker_sync || return
	test_worker_directory_eval_failure_does_not_repopulate_cache || return
	test_root_vcs_pwd_does_not_false_positive_working_tree_change || return
	test_directory_switch_clears_stale_git_state || return
	test_directory_prefix_switch_clears_stale_git_state || return
	test_nested_worktree_clears_stale_git_state || return
	test_async_eval_setup_failure_reports_callback || return
	test_callback_no_recursion_on_worker_failure || return
	test_callback_failed_recovery_clears_git_state || return
	test_callback_recovery_calls_tasks_on_success || return
	test_dead_worker_no_stderr_leakage || return

	print -- "async-worker-failure tests passed"
}

assert_git_state_empty() {
	local message=$1

	assert_empty "${prompt_pure_vcs_info[branch]-}" "branch should be cleared $message" || return
	assert_empty "${prompt_pure_vcs_info[top]-}" "top-level should be cleared $message" || return
	assert_empty "${prompt_pure_vcs_info[action]-}" "action should be cleared $message" || return
	assert_empty "${prompt_pure_vcs_info[pwd]-}" "pwd should be cleared $message" || return
	assert_empty "${prompt_pure_git_dirty-}" "dirty marker should be cleared $message" || return
	assert_empty "${prompt_pure_git_last_dirty_check_timestamp-}" "cached dirty timestamp should be cleared $message" || return
	assert_empty "${prompt_pure_git_arrows-}" "arrows should be cleared $message" || return
	assert_empty "${prompt_pure_git_stash-}" "stash should be cleared $message" || return
	assert_empty "${prompt_pure_git_fetch_pattern-}" "fetch pattern should be cleared $message" || return
}

test_no_infinite_recursion_on_worker_failure() {
	# Simulate async_start_worker always failing (e.g. zpty permission denied).
	async_start_worker() { return 1 }

	typeset -g prompt_pure_async_inited=0

	# This should return 1 (failure), not infinitely recurse.
	local ret=0
	prompt_pure_async_init || ret=$?

	assert_equal 1 $ret "prompt_pure_async_init should return 1 when worker fails to start" || return
	assert_equal 0 $prompt_pure_async_inited "prompt_pure_async_inited should be reset to 0 on failure" || return

	unfunction async_start_worker
}

test_worker_startup_failure_clears_git_state() {
	# Simulate async_start_worker failing after Git state was previously populated.
	async_start_worker() {
		return 1
	}

	typeset -gA prompt_pure_vcs_info=(branch main top /tmp/repo action rebase pwd /tmp/repo)
	typeset -g prompt_pure_git_dirty="*"
	typeset -g prompt_pure_git_last_dirty_check_timestamp=1
	typeset -g prompt_pure_git_arrows="⇡"
	typeset -g prompt_pure_git_stash=1
	typeset -g prompt_pure_git_fetch_pattern="pull|fetch"
	typeset -g prompt_pure_async_inited=0

	prompt_pure_async_tasks || :

	assert_git_state_empty "when worker fails to start" || return

	unfunction async_start_worker
}

test_git_jobs_queued_same_precmd_as_dir_change() {
	# Regression test for the 1.28.0 sync-lag bug: entering a new directory must
	# queue the git jobs (vcs_info) in the SAME precmd as the directory change,
	# not defer them to a later worker round-trip.
	local -a queued_jobs
	async_worker_eval() {
		return 0
	}
	local flush_called=0
	async_flush_jobs() {
		flush_called=1
		return 0
	}
	async_job() {
		queued_jobs+=("$2")
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=()
	typeset -gA prompt_pure_vcs_info=(branch "" top "" action "" pwd "")

	prompt_pure_async_tasks || :

	assert_equal 1 $flush_called "stale git jobs should be flushed on directory change" || return
	assert_equal "$PWD" "${prompt_pure_worker_env[pwd]-}" "worker env should be updated synchronously on directory change" || return
	assert_equal prompt_pure_async_vcs_info "${queued_jobs[1]-}" "vcs_info must be queued in the same precmd as the directory change (no round-trip)" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_git_environment_change_clears_stale_git_state() {
	async_worker_eval() {
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}
	prompt_pure_async_refresh() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd $PWD git_dir /tmp/old-repo/.git git_work_tree /tmp/old-repo)
	typeset -gA prompt_pure_vcs_info=(branch old top /tmp/old-repo action rebase pwd $PWD)
	typeset -g prompt_pure_git_dirty="*"
	typeset -g prompt_pure_git_last_dirty_check_timestamp=1
	typeset -g prompt_pure_git_arrows="⇡"
	typeset -g prompt_pure_git_stash=1
	typeset -g prompt_pure_git_fetch_pattern="pull|fetch"
	local GIT_DIR=/tmp/new-repo/.git
	local GIT_WORK_TREE=/tmp/new-repo

	prompt_pure_async_tasks || :

	assert_empty "${prompt_pure_vcs_info[branch]-}" "branch should be cleared when Git environment changes" || return
	assert_empty "${prompt_pure_vcs_info[top]-}" "top-level should be cleared when Git environment changes" || return
	assert_empty "${prompt_pure_vcs_info[action]-}" "action should be cleared when Git environment changes" || return
	assert_empty "${prompt_pure_git_dirty-}" "dirty marker should be cleared when Git environment changes" || return
	assert_empty "${prompt_pure_git_last_dirty_check_timestamp-}" "cached dirty timestamp should be cleared when Git environment changes" || return
	assert_empty "${prompt_pure_git_arrows-}" "arrows should be cleared when Git environment changes" || return
	assert_empty "${prompt_pure_git_stash-}" "stash should be cleared when Git environment changes" || return
	assert_empty "${prompt_pure_git_fetch_pattern-}" "fetch pattern should be cleared when Git environment changes" || return

	unfunction async_worker_eval async_flush_jobs async_job prompt_pure_async_refresh
}

test_worker_sync_preserves_explicit_empty_git_variables() {
	local -a eval_commands
	async_worker_eval() {
		local worker=$1
		shift
		eval_commands+=("$*")
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd /tmp/old-repo git_dir /tmp/old-repo/.git git_work_tree /tmp/old-repo)
	typeset -gA prompt_pure_vcs_info=(branch "" top "" action "" pwd "")
	local GIT_DIR=
	local GIT_WORK_TREE=

	prompt_pure_async_tasks || :

	local environment_commands=${eval_commands[1]#* && }
	assert_equal "export GIT_DIR=''" "${environment_commands%% &&*}" "an explicitly empty GIT_DIR should be exported to the worker" || return
	environment_commands=${environment_commands#* && }
	assert_equal "export GIT_WORK_TREE=''" "${environment_commands%% &&*}" "an explicitly empty GIT_WORK_TREE should be exported to the worker" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_sync_quotes_working_directory() {
	local original_directory=$PWD
	local base_directory=$PWD/.ai-temporary/pure-worker-sync-$$
	local literal_directory="$base_directory/literal*"
	local glob_match_one="$base_directory/literal-one"
	local glob_match_two="$base_directory/literal-two"
	local captured_sync_command expected_cd_argument

	zf_mkdir -p "$literal_directory/nested" "$glob_match_one/nested" "$glob_match_two/nested"
	builtin cd -q "$literal_directory/nested"
	expected_cd_argument=$PWD

	async_worker_eval() {
		captured_sync_command=$2
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd $original_directory git_dir __unset__ git_work_tree __unset__)
	typeset -gA prompt_pure_vcs_info=(branch "" top "" action "" pwd "")

	setopt localoptions globsubst
	prompt_pure_async_tasks || :

	builtin cd -q "$original_directory"
	zf_rm -rf -- "$base_directory"

	local cd_argument=${(Q)${${captured_sync_command#*builtin cd -q }%% &&*}}
	assert_equal "$expected_cd_argument" "$cd_argument" "worker cd should preserve the literal working directory" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_env_change_clears_cache_after_eval_failure() {
	# A failed eval (e.g. the worker's `cd` failed because the directory was
	# deleted) must clear the cached worker env so the next precmd re-syncs,
	# instead of leaving an unreachable path cached and stalling git info. It
	# must not force a render (unlike 1.28.0, which redrew on eval failure).
	local render_called=0 result=0
	prompt_pure_preprompt_render() {
		render_called=1
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd /tmp/repo git_dir __unset__ git_work_tree __unset__ generation 1 sync_pending 1)

	prompt_pure_async_callback '[async/eval]' 1 "1" 0 "" 0

	assert_empty "${prompt_pure_worker_env[pwd]-}" "eval failure should clear cached worker env" || result=1

	typeset -gA prompt_pure_worker_env=(pwd /tmp/repo git_dir __unset__ git_work_tree __unset__ generation 2 sync_pending 2)
	prompt_pure_async_callback '[async/eval]' 1 "" 0 "" 0

	assert_empty "${prompt_pure_worker_env[pwd]-}" "markerless eval failure should clear pending worker env" || result=1
	assert_equal 0 $render_called "eval failure should not force a prompt render" || result=1

	# Restore the shared no-op render stub from test-helper.zsh for later tests.
	prompt_pure_preprompt_render() {
		:
	}
	return $result
}

test_worker_sync_enqueue_failure_clears_git_state() {
	async_worker_eval() {
		return 1
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd /tmp/old-repo git_dir __unset__ git_work_tree __unset__)
	typeset -gA prompt_pure_vcs_info=(branch old top /tmp/old-repo action rebase pwd /tmp/old-repo)
	typeset -g prompt_pure_git_dirty="*"
	typeset -g prompt_pure_git_last_dirty_check_timestamp=1
	typeset -g prompt_pure_git_arrows="⇡"
	typeset -g prompt_pure_git_stash=1
	typeset -g prompt_pure_git_fetch_pattern="pull|fetch"
	local GIT_DIR GIT_WORK_TREE
	unset GIT_DIR GIT_WORK_TREE

	prompt_pure_async_tasks || :

	assert_empty "${prompt_pure_vcs_info[branch]-}" "branch should be cleared when worker sync enqueue fails" || return
	assert_empty "${prompt_pure_vcs_info[top]-}" "top-level should be cleared when worker sync enqueue fails" || return
	assert_empty "${prompt_pure_vcs_info[action]-}" "action should be cleared when worker sync enqueue fails" || return
	assert_empty "${prompt_pure_git_dirty-}" "dirty marker should be cleared when worker sync enqueue fails" || return
	assert_empty "${prompt_pure_git_last_dirty_check_timestamp-}" "cached dirty timestamp should be cleared when worker sync enqueue fails" || return
	assert_empty "${prompt_pure_git_arrows-}" "arrows should be cleared when worker sync enqueue fails" || return
	assert_empty "${prompt_pure_git_stash-}" "stash should be cleared when worker sync enqueue fails" || return
	assert_empty "${prompt_pure_git_fetch_pattern-}" "fetch pattern should be cleared when worker sync enqueue fails" || return
	assert_empty "${prompt_pure_worker_env[pwd]-}" "worker directory should be cleared when worker sync enqueue fails" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_sync_recovery_preserves_replacement_worker_cache() {
	local worker_failed=0 vcs_jobs=0
	async_start_worker() {
		return 0
	}
	async_stop_worker() {
		return 0
	}
	async_register_callback() {
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	async_worker_eval() {
		if (( ! worker_failed )) && [[ $2 == *'builtin cd -q'* ]]; then
			worker_failed=1
			prompt_pure_async_callback '[async]' 3 "" 0 "worker crashed" 0
			return 1
		fi
		return 0
	}
	async_job() {
		if [[ $2 == prompt_pure_async_vcs_info ]]; then
			(( vcs_jobs++ ))
		fi
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd /tmp/old-repo git_dir __unset__ git_work_tree __unset__)
	typeset -gA prompt_pure_vcs_info=(branch "" top "" action "" pwd /tmp/old-repo)
	local GIT_DIR GIT_WORK_TREE
	unset GIT_DIR GIT_WORK_TREE

	prompt_pure_async_tasks || :

	assert_equal 1 $worker_failed "worker sync should trigger synchronous recovery" || return
	assert_equal "$PWD" "${prompt_pure_worker_env[pwd]-}" "successful recovery should preserve the replacement worker directory cache" || return
	assert_equal 1 $vcs_jobs "successful recovery should queue Git work for the replacement worker" || return

	unfunction async_start_worker async_stop_worker async_register_callback async_flush_jobs async_worker_eval async_job
}

test_stale_git_callback_ignored_during_worker_sync() {
	setopt localoptions
	unsetopt nounset
	local stale_callback_sent=0
	async_worker_eval() {
		if (( ! stale_callback_sent )); then
			stale_callback_sent=1
			prompt_pure_async_callback prompt_pure_async_git_dirty 1 $'1\n*' 0 "" 0
		fi
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}

	typeset -g prompt_pure_worker_generation=1
	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd /tmp/old-repo git_dir __unset__ git_work_tree __unset__ generation 1)
	typeset -gA prompt_pure_vcs_info=(branch "" top "" action "" pwd /tmp/old-repo)
	local GIT_DIR GIT_WORK_TREE
	unset GIT_DIR GIT_WORK_TREE
	typeset -g prompt_pure_git_dirty=

	prompt_pure_async_tasks || :

	assert_equal 1 $stale_callback_sent "worker sync should receive the stale Git callback" || return
	assert_empty "${prompt_pure_git_dirty-}" "stale Git callback should be ignored during worker sync" || return
	prompt_pure_async_callback '[async/eval]' 1 "1" 0 "" 0
	assert_equal "$PWD" "${prompt_pure_worker_env[pwd]-}" "stale eval failure should not clear the current worker cache" || return

	local current_generation=${prompt_pure_worker_env[generation]}
	prompt_pure_async_callback '[async/eval]' 0 "$current_generation" 0 "" 0
	prompt_pure_async_callback prompt_pure_async_git_dirty 1 "$current_generation"$'\n*' 0 "" 0
	assert_equal "*" "${prompt_pure_git_dirty-}" "current Git callback should be accepted after worker sync" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_directory_eval_failure_does_not_repopulate_cache() {
	async_worker_eval() {
		if [[ $2 == *'builtin cd -q'* ]]; then
			prompt_pure_async_callback '[async/eval]' 1 "${prompt_pure_worker_env[sync_pending]}" 0 "" 0
		fi
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd /tmp/old-repo git_dir __unset__ git_work_tree __unset__)
	typeset -gA prompt_pure_vcs_info=(branch "" top "" action "" pwd /tmp/old-repo)
	local GIT_DIR GIT_WORK_TREE
	unset GIT_DIR GIT_WORK_TREE

	prompt_pure_async_tasks || :

	assert_empty "${prompt_pure_worker_env[pwd]-}" "failed worker directory eval should not repopulate the cached directory" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_root_vcs_pwd_does_not_false_positive_working_tree_change() {
	# When vcs_info[pwd] is "/" (root-level Git repo), the working-tree-changed
	# check must not false-positive. Without the "/" guard, the pattern
	# "$PWD != ${vcs_info[pwd]}/*" would expand to "$PWD != //*" which is always
	# true and would incorrectly clear git state every precmd.
	async_worker_eval() {
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}
	prompt_pure_async_refresh() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd $PWD git_dir __unset__ git_work_tree __unset__)
	typeset -gA prompt_pure_vcs_info=(branch main top / action "" pwd /)
	typeset -g prompt_pure_git_dirty="*"

	prompt_pure_async_tasks || :

	assert_equal "*" "${prompt_pure_git_dirty-}" "git state should be preserved when vcs_info pwd is /" || return

	unfunction async_worker_eval async_flush_jobs async_job prompt_pure_async_refresh
}

test_directory_switch_clears_stale_git_state() {
	# Switching to a different working tree must clear the previous tree's git
	# state (branch, dirty, arrows, stash) in the same precmd, so stale info
	# from the old repo is never shown while the new repo's info loads.
	async_worker_eval() {
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	# Pretend the worker is already synced to the current directory so the
	# env-sync block is skipped and we exercise the working-tree switch path.
	typeset -gA prompt_pure_worker_env=(pwd $PWD git_dir __unset__ git_work_tree __unset__)
	# Stale git state from a previous, unrelated working tree.
	local old_repo_path=$PWD/old-repo
	typeset -gA prompt_pure_vcs_info=(branch old top $old_repo_path action rebase pwd $old_repo_path)
	typeset -g prompt_pure_git_dirty="*"
	typeset -g prompt_pure_git_arrows="⇡"
	typeset -g prompt_pure_git_stash=1

	prompt_pure_async_tasks || :

	assert_empty "${prompt_pure_vcs_info[branch]-}" "branch should be cleared when switching working tree" || return
	assert_empty "${prompt_pure_vcs_info[top]-}" "top-level should be cleared when switching working tree" || return
	assert_empty "${prompt_pure_vcs_info[action]-}" "action should be cleared when switching working tree" || return
	assert_empty "${prompt_pure_git_dirty-}" "dirty marker should be cleared when switching working tree" || return
	assert_empty "${prompt_pure_git_arrows-}" "arrows should be cleared when switching working tree" || return
	assert_empty "${prompt_pure_git_stash-}" "stash should be cleared when switching working tree" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_directory_prefix_switch_clears_stale_git_state() {
	local original_directory=$PWD
	local base_directory=$PWD/.ai-temporary/pure-directory-prefix-$$
	local old_repository=$base_directory/repo
	local new_repository=$base_directory/repository
	local result=0

	zf_mkdir -p "$old_repository" "$new_repository"
	builtin cd -q "$new_repository"

	async_worker_eval() {
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}
	prompt_pure_async_refresh() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd $PWD git_dir __unset__ git_work_tree __unset__)
	typeset -gA prompt_pure_vcs_info=(branch old top $old_repository action rebase pwd $old_repository)
	local GIT_DIR GIT_WORK_TREE
	unset GIT_DIR GIT_WORK_TREE
	typeset -g prompt_pure_git_dirty="*"
	typeset -g prompt_pure_git_arrows="⇡"
	typeset -g prompt_pure_git_stash=1

	prompt_pure_async_tasks || :

	assert_empty "${prompt_pure_vcs_info[branch]-}" "branch should be cleared when switching to a path with the old path as a prefix" || result=1
	assert_empty "${prompt_pure_vcs_info[top]-}" "top-level should be cleared when switching to a path with the old path as a prefix" || result=1
	assert_empty "${prompt_pure_vcs_info[action]-}" "action should be cleared when switching to a path with the old path as a prefix" || result=1
	assert_empty "${prompt_pure_git_dirty-}" "dirty marker should be cleared when switching to a path with the old path as a prefix" || result=1
	assert_empty "${prompt_pure_git_arrows-}" "arrows should be cleared when switching to a path with the old path as a prefix" || result=1
	assert_empty "${prompt_pure_git_stash-}" "stash should be cleared when switching to a path with the old path as a prefix" || result=1

	builtin cd -q "$original_directory"
	zf_rm -rf -- "$base_directory"
	unfunction async_worker_eval async_flush_jobs async_job prompt_pure_async_refresh
	return $result
}

test_nested_worktree_clears_stale_git_state() {
	local original_directory=$PWD
	local base_directory=$PWD/.ai-temporary/pure-nested-worktree-$$
	local parent_repository=$base_directory/parent
	local nested_worktree=$parent_repository/submodule
	local result=0

	zf_mkdir -p "$nested_worktree"
	builtin cd -q "$nested_worktree"

	async_worker_eval() {
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}
	prompt_pure_async_refresh() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd $parent_repository git_dir __unset__ git_work_tree __unset__)
	typeset -gA prompt_pure_vcs_info=(branch parent top $parent_repository action rebase pwd $parent_repository)
	local GIT_DIR GIT_WORK_TREE
	unset GIT_DIR GIT_WORK_TREE
	typeset -g prompt_pure_git_dirty="*"
	typeset -g prompt_pure_git_arrows="⇡"
	typeset -g prompt_pure_git_stash=1

	prompt_pure_async_tasks || :

	assert_empty "${prompt_pure_vcs_info[branch]-}" "branch should be cleared when entering a nested worktree" || result=1
	assert_empty "${prompt_pure_vcs_info[top]-}" "top-level should be cleared when entering a nested worktree" || result=1
	assert_empty "${prompt_pure_vcs_info[action]-}" "action should be cleared when entering a nested worktree" || result=1
	assert_empty "${prompt_pure_git_dirty-}" "dirty marker should be cleared when entering a nested worktree" || result=1
	assert_empty "${prompt_pure_git_arrows-}" "arrows should be cleared when entering a nested worktree" || result=1
	assert_empty "${prompt_pure_git_stash-}" "stash should be cleared when entering a nested worktree" || result=1

	builtin cd -q "$original_directory"
	zf_rm -rf -- "$base_directory"
	unfunction async_worker_eval async_flush_jobs async_job prompt_pure_async_refresh
	return $result
}

test_async_eval_setup_failure_reports_callback() {
	typeset -g ASYNC_INIT_DONE=0
	source ./async.zsh

	local callback_job callback_code
	local original_tmpdir=${TMPDIR-}
	local missing_tmpdir=$PWD/.ai-temporary/missing-tmpdir-$$
	zf_rm -rf -- "$missing_tmpdir"

	typeset -g TMPDIR=$missing_tmpdir

	_async_job() {
		local jobname=${ASYNC_JOB_NAME:-$1}
		callback_job=$jobname
		callback_code=1
	}

	_async_eval "print -r -- unreachable"

	if [[ -n $original_tmpdir ]]; then
		typeset -g TMPDIR=$original_tmpdir
	else
		unset TMPDIR
	fi

	assert_equal "[async/eval]" "$callback_job" "async eval setup failure should report through async/eval" || return
	assert_equal 1 "$callback_code" "async eval setup failure should report failure status" || return

	unfunction _async_job
}

test_callback_no_recursion_on_worker_failure() {
	# Simulate async_start_worker always failing.
	async_start_worker() { return 1 }
	async_stop_worker() { : }

	# Stub prompt_pure_async_tasks to detect if it gets called.
	local tasks_called=0
	prompt_pure_async_tasks() { tasks_called=1 }

	typeset -g prompt_pure_async_inited=0

	# Simulate the callback receiving an async worker crash (code 3).
	# Code 3 is representative; codes 2 and 130 share the same branch.
	prompt_pure_async_callback '[async]' 3 '' 0 'worker crashed' 0

	assert_equal 0 $prompt_pure_async_inited "prompt_pure_async_inited should remain 0 after failed recovery" || return
	assert_equal 0 $tasks_called "prompt_pure_async_tasks should not be called when recovery fails" || return

	unfunction async_start_worker async_stop_worker prompt_pure_async_tasks
}

test_callback_failed_recovery_clears_git_state() {
	# Simulate async_start_worker failing after Git state was previously populated.
	async_start_worker() {
		return 1
	}
	async_stop_worker() {
		:
	}

	typeset -gA prompt_pure_vcs_info=(branch main top /tmp/repo action rebase pwd /tmp/repo)
	typeset -g prompt_pure_git_dirty="*"
	typeset -g prompt_pure_git_last_dirty_check_timestamp=1
	typeset -g prompt_pure_git_arrows="⇡"
	typeset -g prompt_pure_git_stash=1
	typeset -g prompt_pure_git_fetch_pattern="pull|fetch"
	typeset -g prompt_pure_async_inited=1
	local render_called=0
	prompt_pure_preprompt_render() {
		render_called=1
	}

	# Use next_pending=1 because a worker crash may be reported while buffered output remains.
	prompt_pure_async_callback '[async]' 3 '' 0 'worker crashed' 1

	assert_git_state_empty "when worker recovery fails" || return
	assert_equal 1 $render_called "prompt should be rendered after worker recovery clears git state" || return

	local async_job_called=0
	async_job() {
		async_job_called=1
	}
	prompt_pure_async_callback prompt_pure_async_vcs_info 0 "pwd ${(q)PWD} branch stale top /tmp/repo action rebase" 0 '' 0

	assert_empty "${prompt_pure_vcs_info[branch]-}" "stale callback should not restore branch after worker recovery fails" || return
	assert_empty "${prompt_pure_vcs_info[top]-}" "stale callback should not restore top-level after worker recovery fails" || return
	assert_equal 0 $async_job_called "stale callback should not queue async jobs after worker recovery fails" || return

	unfunction async_start_worker async_stop_worker prompt_pure_preprompt_render async_job
}

test_callback_recovery_calls_tasks_on_success() {
	# Simulate async_start_worker succeeding on recovery.
	async_start_worker() { return 0 }
	async_stop_worker() { : }
	async_register_callback() { : }
	async_worker_eval() { : }

	# Stub prompt_pure_async_tasks to detect if it gets called.
	local tasks_called=0
	prompt_pure_async_tasks() { tasks_called=1 }

	typeset -g prompt_pure_async_inited=0

	# Simulate the callback receiving an async worker crash (code 2).
	prompt_pure_async_callback '[async]' 2 '' 0 'worker crashed' 0

	assert_equal 1 $tasks_called "prompt_pure_async_tasks should be called when recovery succeeds" || return

	unfunction async_start_worker async_stop_worker async_register_callback async_worker_eval prompt_pure_async_tasks
}

test_dead_worker_no_stderr_leakage() {
	# Restore prompt_pure_async_tasks (earlier tests unfunction it).
	source ./pure.zsh >/dev/null 2>&1
	prompt_pure_preprompt_render() { : }

	# Simulate: worker was previously started but is now dead.
	# When recovery fails, the remaining async calls in prompt_pure_async_tasks
	# must not leak error messages to stderr. (GitHub issue #639)
	typeset -g prompt_pure_async_inited=1

	# Recovery will fail because the worker cannot be restarted.
	async_start_worker() { return 1 }
	async_stop_worker() {
		typeset -gA ASYNC_CALLBACKS
		unset "ASYNC_CALLBACKS[$1]"
	}
	async_register_callback() { : }
	async_flush_jobs() { : }

	# Register the callback (as prompt_pure_async_init would have done).
	typeset -gA ASYNC_CALLBACKS
	ASYNC_CALLBACKS[prompt_pure]="prompt_pure_async_callback"

	# Simulate dead worker behavior: the first call with a registered callback
	# invokes recovery (which fails and unregisters the callback). Subsequent
	# calls find no callback and print errors to stderr.
	async_worker_eval() {
		local worker=$1; shift
		typeset -gA ASYNC_CALLBACKS
		local callback=
		(( ${+ASYNC_CALLBACKS[$worker]} )) && callback=$ASYNC_CALLBACKS[$worker]
		if [[ -n $callback ]]; then
			$callback '[async]' 3 "" 0 "error: no such worker: $worker" 0
		else
			print -u2 "async_worker_eval: no such async worker: $worker"
		fi
		return 1
	}
	async_job() {
		local worker=$1; shift
		typeset -gA ASYNC_CALLBACKS
		local callback=
		(( ${+ASYNC_CALLBACKS[$worker]} )) && callback=$ASYNC_CALLBACKS[$worker]
		if [[ -n $callback ]]; then
			$callback '[async]' 3 "" 0 "error: no such worker: $worker" 0
		else
			print -u2 "async_job: no such async worker: $worker"
		fi
		return 1
	}

	local stderr_file=$TMPDIR/pure-test-stderr-$$
	prompt_pure_async_tasks 2>$stderr_file
	local stderr_output=$(<$stderr_file 2>/dev/null)

	assert_empty "$stderr_output" "prompt_pure_async_tasks must not leak error messages to stderr when worker is dead" || return

	unfunction async_start_worker async_stop_worker async_register_callback async_flush_jobs async_worker_eval async_job
}

main "$@"
