#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"
set +e
typeset -g ASYNC_INIT_DONE=0
source ./async.zsh
set -e

# Regression test for https://github.com/sindresorhus/pure/issues/726:
# locating the NUL delimiter with the [(i)$null] subscript is O(N²) in CPU
# and heap, so a few hundred KB of job output pins the shell for minutes
# and balloons memory. Parsing must stay linear in the buffer size.
main() {
	local null=$'\0'
	local jobname=big_job
	local stdout=''
	stdout=${(l:800000::x:)stdout}  # 800 KB payload without a NUL.
	local message=$null${(q)jobname}" 0 "${(q)stdout}" 1.5 ''"$null

	# Feed the framed message in 1 KB chunks, simulating normal zpty reads.
	local -a chunks
	local chunk_size=1024
	local offset
	for (( offset = 1; offset <= ${#message}; offset += chunk_size )); do
		chunks+=("${message[$offset,$offset+$chunk_size-1]}")
	done

	local callback_jobname=
	local callback_status=
	local callback_stdout=
	local next_chunk=

	zpty() {
		[[ -n $next_chunk ]] || return 1
		data=$next_chunk
		next_chunk=
		return 0
	}

	callback() {
		callback_jobname=$1
		callback_status=$2
		callback_stdout=$3
	}

	local process_status=0
	typeset -F SECONDS=0
	for next_chunk in $chunks; do
		if async_process_results worker callback direct; then
			process_status=0
		else
			process_status=$?
		fi
	done
	local -F elapsed=$SECONDS

	assert_equal 0 $process_status "processing a complete result should succeed"
	assert_equal $jobname $callback_jobname "callback should receive the job name"
	assert_equal 0 $callback_status "callback should receive the exit status"
	assert_equal $stdout $callback_stdout "callback should receive the full stdout payload"

	if (( elapsed > 1 )); then
		print -u2 -- "Assertion failed: parsing a large job result should be fast (quadratic buffer scan regression)"
		print -u2 -- "Elapsed: ${elapsed}s"
		return 1
	fi

	unfunction zpty callback

	print -- "async-quadratic-buffer tests passed"
}

main "$@"
