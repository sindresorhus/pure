#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"
set +e
typeset -g ASYNC_INIT_DONE=0
source ./async.zsh
set -e

main() {
	assert_empty_read_status trap 0
	assert_empty_read_status watcher 0
	assert_empty_read_status direct 1

	print -- "async-empty-read tests passed"
}

assert_empty_read_status() {
	local caller=$1
	local expected_status=$2
	local callback_status=
	local callback_stderr=
	local callback_has_next=

	zpty() {
		data=''
		return 0
	}

	callback() {
		callback_status=$2
		callback_stderr=$5
		callback_has_next=$6
	}

	local process_status=0
	async_process_results worker callback $caller || process_status=$?

	assert_equal $expected_status $process_status "$caller caller should keep the documented status after an empty read"
	assert_equal 2 $callback_status "$caller caller should report empty read through the callback"
	assert_equal 0 $callback_has_next "$caller caller should report no next item after an empty read"

	if [[ $callback_stderr != *"empty read from worker worker"* ]]; then
		print -u2 -- "Assertion failed: $caller caller should report empty read details"
		print -u2 -- "Actual: $callback_stderr"
		return 1
	fi

	unfunction zpty callback
}

main "$@"
