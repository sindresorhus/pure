#!/usr/bin/env zsh

#
# zsh-async
#
# version: 0.2.3
# author: Mathias Fredriksson
# url: https://github.com/mafredri/zsh-async
#

# Wrapper for jobs executed by the async worker, gives output in parseable format with execution time
_async_job() {
	# store start time
	local start=$EPOCHREALTIME

	# run the command
	local out
	out=$(eval "$@" 2>&1)
	local ret=$?

	# Grab mutex lock
	read -ep >/dev/null

	# return output (<job_name> <return_code> <output> <duration>)
	print -r -N -n -- "$1" "$ret" "$out" $(( $EPOCHREALTIME - $start ))$'\0'

	# Unlock mutex
	print -p "t"
}

# The background worker manages all tasks and runs them without interfering with other processes
_async_worker() {
	local -A storage
	local unique=0

	# Process option parameters passed to worker
	while getopts "np:u" opt; do
		case "$opt" in
		# Use SIGWINCH since many others seem to cause zsh to freeze, e.g. ALRM, INFO, etc.
		n) trap 'kill -WINCH $ASYNC_WORKER_PARENT_PID' CHLD;;
		p) ASYNC_WORKER_PARENT_PID=$OPTARG;;
		u) unique=1;;
		esac
	done

	# Create a mutex for writing to the terminal through coproc
	coproc cat
	# Insert token into coproc
	print -p "t"

	while read -r cmd; do
		# Separate on spaces into an array
		cmd=(${=cmd})
		local job=$cmd[1]

		# Check for non-job commands sent to worker
		case "$job" in
		_killjobs)
			kill -KILL ${${(v)jobstates##*:*:}%\=*} &>/dev/null
			continue
			;;
		esac

		# If worker should perform unique jobs
		if ((unique)); then
			# Check if a previous job is still running, if yes, let it finnish
			for pid in ${${(v)jobstates##*:*:}%\=*}; do
				if [[ "${storage[$job]}" == "$pid" ]]; then
					continue 2
				fi
			done
		fi

		# run task in background
		_async_job $cmd &
		# store pid because zsh job manager is extremely unflexible (show jobname as non-unique '$job')...
		storage[$job]=$!
	done
}

#
#  Get results from finnished jobs and pass it to the to callback function. This is the only way to reliably return the
#  job name, return code, output and execution time and with minimal effort.
#
# usage:
# 	async_process_results <worker_name> <callback_function>
#
# callback_function is called with the following parameters:
# 	$1 = job name, e.g. the function passed to async_job
# 	$2 = return code
# 	$3 = resulting output from execution
# 	$4 = execution time, floating point e.g. 2.05 seconds
#
async_process_results() {
	integer count=0
	local worker=$1
	local callback=$2
	local -a items
	local IFS=$'\0'

	typeset -gA ASYNC_PROCESS_BUFFER
	# Read output from zpty and parse it if available
	while zpty -rt "$worker" line 2>/dev/null; do
		# Remove unwanted \r from output
		ASYNC_PROCESS_BUFFER[$1]+=${line//$'\r'$'\n'/$'\n'}
		# Split buffer on null characters, preserve empty elements
		items=("${(@)=ASYNC_PROCESS_BUFFER[$1]}")
		# Remove last element since it's due to the return string separator structure
		items=("${(@)items[1,${#items}-1]}")

		# Continue until we receive all information
		(( ${#items} % 4 )) && continue

		# Work through all results
		while (( ${#items} > 0 )); do
			"$callback" "${(@)=items[1,4]}"
			shift 4 items
			count+=1
		done

		# Empty the buffer
		ASYNC_PROCESS_BUFFER[$1]=""
	done

	# If we processed any results, return success
	(( $count )) && return 0

	# No results were processed
	return 1
}

#
# Start a new asynchronous job on specified worker, assumes the worker is running.
#
# usage:
# 	async_job <worker_name> <my_function> [<function_params>]
#
async_job() {
	local worker=$1; shift
	zpty -w "$worker" "$@"
}

# This function traps notification signals and calls all registered callbacks
_async_notify_trap() {
	for k in ${(k)ASYNC_CALLBACKS}; do
		async_process_results "${k}" "${ASYNC_CALLBACKS[$k]}"
	done
}

#
# Register a callback for completed jobs. As soon as a job is finnished, async_process_results will be called with the
# specified callback function. This requires that a worker is initialized with the -n (notify) option.
#
# usage:
# 	async_register_callback <worker_name> <callback_function>
#
async_register_callback() {
	typeset -gA ASYNC_CALLBACKS
	local worker=$1; shift

	ASYNC_CALLBACKS[$worker]="$*"

	trap '_async_notify_trap' WINCH
}

#
# Unregister the callback for a specific worker.
#
# usage:
# 	async_unregister_callback <worker_name>
#
async_unregister_callback() {
	typeset -gA ASYNC_CALLBACKS

	unset "ASYNC_CALLBACKS[$1]"
}

#
# Flush all current jobs running on a worker. This will terminate any and all running processes under the worker, use
# with caution.
#
# usage:
# 	async_flush_jobs <worker_name>
#
async_flush_jobs() {
	local worker=$1; shift

	# Check if the worker exists
	zpty -t "$worker" &>/dev/null || return 1

	# Send kill command to worker
	zpty -w "$worker" "_killjobs"

	# Clear all output buffers
	while zpty -r "$worker" line; do true; done

	# Clear any partial buffers
	typeset -gA ASYNC_PROCESS_BUFFER
	ASYNC_PROCESS_BUFFER[$1]=""
}

#
# Start a new async worker with optional parameters, a worker can be told to only run unique tasks and to notify a
# process when tasks are complete.
#
# usage:
# 	async_start_worker <worker_name> [-u] [-n] [-p <pid>]
#
# opts:
# 	-u unique (only unique job names can run)
# 	-n notify through SIGWINCH signal
# 	-p pid to notify (defaults to current pid)
#
async_start_worker() {
	local worker=$1; shift
	zpty -t "$worker" &>/dev/null || zpty -b "$worker" _async_worker -p $$ "$@" || async_stop_worker "$worker"
}

#
# Stop one or multiple workers that are running, all unfetched and incomplete work will be lost.
#
# usage:
# 	async_stop_worker <worker_name_1> [<worker_name_2>]
#
async_stop_worker() {
	local ret=0
	for worker in "$@"; do
		async_unregister_callback "$worker"
		zpty -d "$worker" 2>/dev/null || ret=$?
	done

	return $ret
}

#
# Initialize the required modules for zsh-async. To be called before using the zsh-async library.
#
# usage:
# 	async_init
#
async_init() {
	zmodload zsh/zpty
	zmodload zsh/datetime
}

async() {
	async_init
}

async "$@"
