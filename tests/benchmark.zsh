#!/usr/bin/env zsh
# Benchmark Pure's synchronous hot path.
# Usage: zsh tests/benchmark.zsh [--dimmed]

setopt noshwordsplit
zmodload zsh/datetime

cd -- "${0:A:h}/.."

# Stub async machinery so we only measure synchronous code.
# Note: with async_worker_eval stubbed, the worker-sync caching in
# prompt_pure_async_tasks always measures the cache-hit path after
# the first iteration.
async() { : }
async_init() { : }
async_start_worker() { : }
async_stop_worker() { : }
async_register_callback() { : }
async_worker_eval() { : }
async_flush_jobs() { : }
async_job() { : }

# Apply dimmed path separator if requested.
local dimmed=0
if [[ $1 == '--dimmed' ]]; then
	dimmed=1
	zstyle ':prompt:pure:path:separator' dim yes
fi

# Disable title setting to avoid escape sequences in output.
zstyle ':prompt:pure:title' show no

# Source Pure (suppresses output from setup).
source ./pure.zsh >/dev/null 2>&1

# Simulate a populated prompt state (as if inside a git repo with all features).
typeset -gA prompt_pure_vcs_info=(
	branch 'main'
	top "$PWD"
	action ''
	pwd "$PWD"
)
typeset -g prompt_pure_git_dirty='*'
typeset -g prompt_pure_git_arrows='⇣⇡'
typeset -g prompt_pure_git_stash='1'
typeset -g prompt_pure_cmd_exec_time='42s'
typeset -g prompt_pure_cmd_timestamp=$EPOCHSECONDS

_bench() {
	local name=$1 iters=$2
	shift 2

	local -a times
	local i t0 t1

	# Warmup (5 iterations).
	for (( i = 0; i < 5; i++ )); do
		eval "$@" >/dev/null 2>&1
	done

	for (( i = 0; i < iters; i++ )); do
		t0=$EPOCHREALTIME
		eval "$@" >/dev/null 2>&1
		t1=$EPOCHREALTIME
		integer usec=$(( (t1 - t0) * 1000000 ))
		times+=( $usec )
	done

	# Sort using zsh numeric ordering.
	local -a sorted=( "${(@no)times}" )
	local n=$#sorted
	local min=$sorted[1]
	local max=$sorted[$n]
	local med=$sorted[$(( n / 2 + 1 ))]
	integer p95_idx=$(( n * 95 / 100 + 1 ))
	local p95=$sorted[$p95_idx]
	local sum=0
	for t in $times; do (( sum += t )); done
	local avg=$(( sum / n ))

	printf "  %-40s  min=%5dµs  med=%5dµs  p95=%5dµs  max=%5dµs  avg=%5dµs\n" \
		"$name" $min $med $p95 $max $avg
}

local iters=200

print "Pure prompt benchmark (${iters} iterations)"
if (( dimmed )); then
	print "  Mode: dimmed path separator ENABLED"
else
	print "  Mode: default (no dimmed path)"
fi
print

_bench "prompt_pure_set_colors" $iters \
	'prompt_pure_set_colors'

_bench "prompt_pure_set_path_separator" $iters \
	'prompt_pure_set_path_separator'

_bench "prompt_pure_preprompt_render (precmd)" $iters \
	'prompt_pure_preprompt_render precmd'

_bench "\${(S%%)PROMPT} expansion" $iters \
	'local x="${(S%%)PROMPT}"'

_bench "prompt_pure_async_tasks (sync part)" $iters \
	'prompt_pure_async_tasks'

_bench "prompt_pure_precmd (full)" $iters \
	'prompt_pure_precmd'

print
print "Done."
