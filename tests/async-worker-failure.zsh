#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"
set +e

main() {
	test_no_infinite_recursion_on_worker_failure || return
	test_worker_startup_failure_clears_git_state || return
	test_callback_no_recursion_on_worker_failure || return
	test_callback_failed_recovery_clears_git_state || return
	test_callback_recovery_calls_tasks_on_success || return

	print -- "async-worker-failure tests passed"
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

	assert_empty "${prompt_pure_vcs_info[branch]-}" "branch should be cleared when worker fails to start" || return
	assert_empty "${prompt_pure_vcs_info[top]-}" "top-level should be cleared when worker fails to start" || return
	assert_empty "${prompt_pure_vcs_info[action]-}" "action should be cleared when worker fails to start" || return
	assert_empty "${prompt_pure_vcs_info[pwd]-}" "pwd should be cleared when worker fails to start" || return
	assert_empty "${prompt_pure_git_dirty-}" "dirty marker should be cleared when worker fails to start" || return
	assert_empty "${prompt_pure_git_last_dirty_check_timestamp-}" "cached dirty timestamp should be cleared when worker fails to start" || return
	assert_empty "${prompt_pure_git_arrows-}" "arrows should be cleared when worker fails to start" || return
	assert_empty "${prompt_pure_git_stash-}" "stash should be cleared when worker fails to start" || return
	assert_empty "${prompt_pure_git_fetch_pattern-}" "fetch pattern should be cleared when worker fails to start" || return

	unfunction async_start_worker
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

	assert_empty "${prompt_pure_vcs_info[branch]-}" "branch should be cleared when worker recovery fails" || return
	assert_empty "${prompt_pure_vcs_info[top]-}" "top-level should be cleared when worker recovery fails" || return
	assert_empty "${prompt_pure_vcs_info[action]-}" "action should be cleared when worker recovery fails" || return
	assert_empty "${prompt_pure_vcs_info[pwd]-}" "pwd should be cleared when worker recovery fails" || return
	assert_empty "${prompt_pure_git_dirty-}" "dirty marker should be cleared when worker recovery fails" || return
	assert_empty "${prompt_pure_git_last_dirty_check_timestamp-}" "cached dirty timestamp should be cleared when worker recovery fails" || return
	assert_empty "${prompt_pure_git_arrows-}" "arrows should be cleared when worker recovery fails" || return
	assert_empty "${prompt_pure_git_stash-}" "stash should be cleared when worker recovery fails" || return
	assert_empty "${prompt_pure_git_fetch_pattern-}" "fetch pattern should be cleared when worker recovery fails" || return
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

main "$@"
