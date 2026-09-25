#!/usr/bin/env zsh

set -euo pipefail

cd -- "${0:A:h}/.."

source ./pure.zsh >/dev/null 2>&1

# Do not depend on the user's Git config.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

prompt_pure_preprompt_render() {
	:
}

# Creates a `git` in the directory $1 that appends the arguments of each call to the file $2, and then runs the real Git.
create_logging_git() {
	print -r -- "#!/bin/sh
printf '%s\n' \"\$*\" >> '$2'
exec '${commands[git]}' \"\$@\"" >| "$1/git"
	chmod +x "$1/git"
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
