#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"
set +e
typeset -g ASYNC_INIT_DONE=0
source ./async.zsh
set -e

# Worker results are framed with a NUL both before and after the payload, so
# two consecutive results are separated by a double NUL.
null=$'\0'

typeset -ga callback_jobnames callback_has_next

callback() {
	callback_jobnames+=($1)
	callback_has_next+=($6)
}

reset_process_buffer() {
	ASYNC_PROCESS_BUFFER=()
	ASYNC_PROCESS_BUFFER_FRAGMENTS=()
	ASYNC_PROCESS_BUFFER_GENERATIONS=()
}

process_chunks() {
	local callback_function=$1
	shift
	local -a chunks
	chunks=("$@")

	zpty() {
		(( ${#chunks} )) || return 1
		data=$chunks[1]
		shift chunks
		return 0
	}

	callback_jobnames=()
	callback_has_next=()
	async_process_results worker $callback_function direct || true

	unfunction zpty
}

# Two complete results in a single read must both reach the callback, with
# has_next flagged on all but the last. This also exercises the empty message
# produced by the double NUL between results.
multiple_messages_in_one_read() {
	local first=$null"jobA 0 outA 1.0 ''"$null
	local second=$null"jobB 0 outB 1.0 ''"$null

	reset_process_buffer
	process_chunks callback "$first$second"

	assert_equal "jobA jobB" "$callback_jobnames" "both results should reach the callback"
	assert_equal "1 0" "$callback_has_next" "has_next should be set on all but the last result"
}

# Regression test for the data-loss bug fixed alongside
# https://github.com/sindresorhus/pure/issues/726: when a read ended exactly
# one character past a delimiter, the old parser silently dropped that
# character from the next message, corrupting it into a 'bad format' error.
read_ending_one_character_past_delimiter() {
	local first=$null"jobA 0 outA 1.0 ''"$null
	local second=$null"jobB 0 outB 1.0 ''"$null
	local stream=$first$second

	# End the first read on the 'j' of jobB, one character past its delimiter.
	reset_process_buffer
	process_chunks callback "${stream[1,${#first}+2]}" "${stream[${#first}+3,-1]}"

	assert_equal "jobA jobB" "$callback_jobnames" "the character after a delimiter must not be dropped"
}

incomplete_message_across_calls() {
	local message=$null"jobA 0 outA 1.0 ''"$null

	reset_process_buffer
	process_chunks callback "${message[1,5]}"
	assert_empty "$callback_jobnames" "an incomplete result should not reach the callback"

	process_chunks callback "${message[6,-1]}"
	assert_equal "jobA" "$callback_jobnames" "an incomplete result should resume on the next call"
}

worker_teardown_during_callback() {
	local first=$null"jobA 0 outA 1.0 ''"$null
	local second=$null"jobB 0 outB 1.0 ''"$null

	reset_process_buffer

	teardown_callback() {
		callback_jobnames+=($1)
		_async_clear_process_buffer worker
	}

	process_chunks teardown_callback "$first$second${null}partial"

	assert_equal "jobA" "$callback_jobnames" "worker teardown should discard remaining results"
	assert_empty "${ASYNC_PROCESS_BUFFER[worker]-}" "worker teardown should not retain stale fragment metadata"
	assert_empty "${ASYNC_PROCESS_BUFFER_FRAGMENTS[6:worker:1]-}" "worker teardown should not retain stale fragments"

	unfunction teardown_callback
}

main() {
	multiple_messages_in_one_read
	read_ending_one_character_past_delimiter
	incomplete_message_across_calls
	worker_teardown_during_callback

	print -- "async-process-results tests passed"
}

main "$@"
