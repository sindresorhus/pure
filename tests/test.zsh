#!/usr/bin/env zsh

set -euo pipefail

cd -- "${0:A:h}"

local test_file
for test_file in *.zsh; do
	if [[ $test_file == test.zsh || $test_file == test-helper.zsh || $test_file == benchmark.zsh ]]; then
		continue
	fi

	print -- "Running $test_file"
	zsh "$test_file"
done
