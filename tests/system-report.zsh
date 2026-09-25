#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

main() {
	# Pure reads optional globals that may be unset, and the report is run with a restricted PATH below.
	set +eu
	zmodload -F zsh/files b:zf_rm

	local report
	report=$(SHELL=/bin/sh prompt_pure_system_report 2>&1)

	# The running Zsh is reported, even when the login shell is another shell.
	assert_equal "- Zsh: $ZSH_VERSION ($ZSH_PATCHLEVEL)" "${${(f)report}[1]}" "report should show the running Zsh version" || return 1

	# A missing optional tool must not leak a shell error or an empty field.
	# Build a PATH that has the report's helpers but no `git`.
	local sandbox_bin
	sandbox_bin=$(mktemp -d "${TMPDIR:-/tmp}/system-report.XXXXXX")
	trap "zf_rm -rf -- ${(q)sandbox_bin}" EXIT
	local tool tool_path
	for tool in uname who sw_vers; do
		tool_path=$(command -v "$tool" 2>/dev/null)
		if [[ -n $tool_path ]]; then
			ln -sf -- "$tool_path" "$sandbox_bin/$tool"
		fi
	done

	local no_git_report
	no_git_report=$(PATH="$sandbox_bin" SHELL=/bin/sh prompt_pure_system_report 2>&1)
	if [[ $no_git_report == *"command not found"* ]]; then
		print -u2 -- "Assertion failed: the report should not leak a shell error when an optional tool is missing"
		print -u2 -- "Report: $no_git_report"
		return 1
	fi
	if [[ $no_git_report != *"- Git: not installed"* ]]; then
		print -u2 -- "Assertion failed: a missing Git should be reported as not installed"
		print -u2 -- "Report: $no_git_report"
		return 1
	fi

	print -- "system-report tests passed"
}

main "$@"
