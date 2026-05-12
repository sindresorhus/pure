#!/usr/bin/env zsh

set -euo pipefail

cd -- "${0:A:h}/.."

source ./pure.zsh >/dev/null 2>&1

prompt_pure_preprompt_render() {
	:
}

assert_equal() {
	local expected=$1
	local actual=$2
	local message=$3

	if [[ $expected != $actual ]]; then
		print -u2 -- "Assertion failed: $message"
		print -u2 -- "Expected: $expected"
		print -u2 -- "Actual:   $actual"
		return 1
	fi
}

assert_empty() {
	local actual=$1
	local message=$2

	if [[ -n $actual ]]; then
		print -u2 -- "Assertion failed: $message"
		print -u2 -- "Expected empty value"
		print -u2 -- "Actual: $actual"
		return 1
	fi
}
