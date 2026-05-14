#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"
set +e
zmodload -F zsh/files b:zf_rm b:zf_mkdir

main() {
	test_no_infinite_recursion_on_worker_failure || return
	test_worker_startup_failure_clears_git_state || return
	test_worker_sync_clears_stale_git_state_before_returning || return
	test_worker_sync_cd_failure_is_not_cached || return
	test_worker_sync_success_queues_git_job || return
	test_worker_sync_eval_failure_clears_pending_state || return
	test_worker_sync_records_pending_before_eval || return
	test_worker_sync_enqueue_failure_preserves_new_pending_state || return
	test_async_eval_setup_failure_reports_callback || return
	test_real_worker_sync_reports_encoded_status || return
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

test_worker_sync_clears_stale_git_state_before_returning() {
	local saved_pwd=$PWD
	local tmpdir=$PWD/.ai-temporary/worker-sync-clear-$$
	zf_mkdir -p "$tmpdir"

	async_worker_eval() {
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 1
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=(pwd /tmp/repo git_dir __unset__ git_work_tree __unset__)
	typeset -gA prompt_pure_worker_env_pending=()
	typeset -gA prompt_pure_vcs_info=(branch main top /tmp/repo action rebase pwd /tmp/repo)
	typeset -g prompt_pure_git_dirty="*"
	typeset -g prompt_pure_git_last_dirty_check_timestamp=1
	typeset -g prompt_pure_git_arrows="⇡"
	typeset -g prompt_pure_git_stash=1
	typeset -g prompt_pure_git_fetch_pattern="pull|fetch"

	builtin cd -q "$tmpdir"

	prompt_pure_async_tasks || :

	builtin cd -q "$saved_pwd"
	zf_rm -rf -- "$saved_pwd/.ai-temporary"

	assert_git_state_empty "before returning for worker sync" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_sync_cd_failure_is_not_cached() {
	local saved_pwd=$PWD
	local tmpdir=$PWD/.ai-temporary/worker-sync-$$
	zf_mkdir -p "$tmpdir"
	local -a worker_eval_command

	async_worker_eval() {
		local worker=$1; shift
		worker_eval_command=("$@")
		return 0
	}
	local async_flush_jobs_called=0
	async_flush_jobs() {
		async_flush_jobs_called=1
		return 0
	}
	local git_job_called=0
	local render_called=0
	async_job() {
		git_job_called=1
		return 1
	}
	prompt_pure_preprompt_render() {
		render_called=1
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=()
	typeset -gA prompt_pure_worker_env_pending=()

	builtin cd -q "$tmpdir"
	zf_rm -rf -- "$tmpdir"

	prompt_pure_async_tasks || :

	builtin cd -q "$saved_pwd"
	zf_rm -rf -- "$saved_pwd/.ai-temporary"

	assert_empty "${prompt_pure_worker_env[pwd]-}" "worker sync should not be cached before eval callback" || return
	assert_equal 1 $async_flush_jobs_called "old git jobs should be flushed before worker sync" || return
	assert_equal 0 $git_job_called "git jobs should wait for worker sync callback" || return

	local sync_output
	sync_output=$("${(@)worker_eval_command}" 2>&1)
	builtin cd -q "$saved_pwd"
	prompt_pure_async_callback '[async/eval]' 0 "$sync_output" 0 "" 1

	assert_empty "${prompt_pure_worker_env[pwd]-}" "failed worker cd should not be cached as synced" || return
	assert_equal 0 $git_job_called "git jobs should not run when worker cd fails" || return
	assert_equal 1 $render_called "failed worker sync should render even when stale results are pending" || return

	prompt_pure_async_callback prompt_pure_async_vcs_info 0 "pwd ${(q)PWD} branch stale top /tmp/repo action rebase" 0 "" 0

	assert_empty "${prompt_pure_vcs_info[branch]-}" "stale vcs info should not repopulate branch after failed worker sync" || return
	assert_empty "${prompt_pure_vcs_info[top]-}" "stale vcs info should not repopulate top-level after failed worker sync" || return

	prompt_pure_preprompt_render() {
		:
	}
	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_sync_success_queues_git_job() {
	local -a worker_eval_command

	async_worker_eval() {
		local worker=$1; shift
		worker_eval_command=("$@")
		return 0
	}
	local async_flush_jobs_called=0
	async_flush_jobs() {
		async_flush_jobs_called=1
		return 0
	}
	local git_job_called=0
	async_job() {
		git_job_called=1
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=()
	typeset -gA prompt_pure_worker_env_pending=()
	typeset -gA prompt_pure_vcs_info=(branch "" top "" action "" pwd "")

	prompt_pure_async_tasks || :

	assert_empty "${prompt_pure_worker_env[pwd]-}" "worker sync should not be cached before eval callback" || return
	assert_equal 1 $async_flush_jobs_called "old git jobs should be flushed before worker sync" || return
	assert_equal 0 $git_job_called "git jobs should wait for worker sync callback" || return

	prompt_pure_async_callback '[async/eval]' 0 "renice output" 0 "" 0

	assert_empty "${prompt_pure_worker_env[pwd]-}" "unrelated eval callback should not cache worker sync" || return
	assert_equal 0 $git_job_called "unrelated eval callback should not queue git jobs" || return

	local sync_output
	sync_output=$("${(@)worker_eval_command}" 2>&1)
	prompt_pure_async_callback '[async/eval]' 0 "$sync_output" 0 "" 0

	assert_equal "$PWD" "${prompt_pure_worker_env[pwd]-}" "successful worker sync should be cached" || return
	assert_equal 1 $git_job_called "git jobs should run after worker sync succeeds" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_sync_eval_failure_clears_pending_state() {
	local async_worker_eval_called=0
	async_worker_eval() {
		(( async_worker_eval_called++ ))
		(( async_worker_eval_called == 1 ))
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=()
	typeset -gA prompt_pure_worker_env_pending=()

	prompt_pure_async_tasks || :

	assert_equal "$PWD" "${prompt_pure_worker_env_pending[pwd]-}" "worker sync should be pending before eval failure" || return

	prompt_pure_async_callback '[async/eval]' 1 "" 0 "" 0

	assert_equal 1 $async_worker_eval_called "non-marker eval failure should not immediately retry worker sync" || return
	assert_empty "${prompt_pure_worker_env_pending[pwd]-}" "non-marker eval failure should clear pending sync state" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_sync_records_pending_before_eval() {
	async_worker_eval() {
		prompt_pure_async_callback '[async/eval]' 0 "prompt_pure_worker_sync:${prompt_pure_worker_env_pending[token]}:0" 0 "" 0
		return 0
	}
	async_flush_jobs() {
		return 0
	}
	local git_job_called=0
	async_job() {
		git_job_called=1
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=()
	typeset -gA prompt_pure_worker_env_pending=()
	typeset -gA prompt_pure_vcs_info=(branch "" top "" action "" pwd "")

	prompt_pure_async_tasks || :

	assert_empty "${prompt_pure_worker_env_pending[pwd]-}" "sync callback should not leave pending state behind" || return
	assert_equal "$PWD" "${prompt_pure_worker_env[pwd]-}" "sync callback should cache worker sync even if it arrives during async_worker_eval" || return
	assert_equal 1 $git_job_called "git jobs should run after immediate worker sync callback" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_sync_enqueue_failure_preserves_new_pending_state() {
	async_worker_eval() {
		typeset -gA prompt_pure_worker_env_pending=(pwd "$PWD" git_dir __unset__ git_work_tree __unset__ token 999)
		return 1
	}
	async_flush_jobs() {
		return 0
	}
	async_job() {
		return 0
	}

	typeset -g prompt_pure_async_inited=1
	typeset -gA prompt_pure_worker_env=()
	typeset -gA prompt_pure_worker_env_pending=()

	prompt_pure_async_tasks || :

	assert_equal 999 "${prompt_pure_worker_env_pending[token]-}" "enqueue failure should not clear newer pending sync state" || return

	unfunction async_worker_eval async_flush_jobs async_job
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

test_real_worker_sync_reports_encoded_status() {
	typeset -g ASYNC_INIT_DONE=0
	source ./async.zsh
	typeset -gA ASYNC_PTYS=()
	typeset -gA ASYNC_CALLBACKS=()
	typeset -gA ASYNC_PROCESS_BUFFER=()

	local worker=prompt_pure_worker_sync_test
	async_stop_worker $worker >/dev/null 2>&1 || :
	async_start_worker $worker -u || return

	local saved_pwd=$PWD
	local tmpdir=$PWD/.ai-temporary/worker-sync-real-$$
	zf_mkdir -p "$tmpdir"
	zf_rm -rf -- "$tmpdir"

	local callback_job callback_code callback_output
	real_worker_callback() {
		callback_job=$1
		callback_code=$2
		callback_output=$3
	}

	async_worker_eval $worker prompt_pure_async_worker_sync 1 "$tmpdir" 0 "" 0 "" || return

	local index
	for index in {1..50}; do
		async_process_results $worker real_worker_callback direct >/dev/null 2>&1
		[[ $callback_job == '[async/eval]' ]] && break
		sleep 0.01
	done

	async_stop_worker $worker >/dev/null 2>&1 || :
	builtin cd -q "$saved_pwd"

	assert_equal "[async/eval]" "$callback_job" "real worker sync should report through async/eval" || return
	assert_equal 1 "$callback_code" "real async/eval wrapper should preserve eval status" || return

	if [[ $callback_output != *"prompt_pure_worker_sync:1:1"* ]]; then
		print -u2 -- "Assertion failed: real worker sync should encode failed cd status in output"
		print -u2 -- "Actual: $callback_output"
		return 1
	fi

	unfunction real_worker_callback
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
