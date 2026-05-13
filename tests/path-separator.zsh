#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

main() {
	zmodload -F zsh/files b:zf_rm

	local base_directory=$PWD/.ai-temporary/pure-path-test-$$
	trap "zf_rm -rf -- ${(q)base_directory}" EXIT

	typeset -gA prompt_pure_colors=(
		path blue
	)

	# Disabled by default: path should render without dimmed separators.
	local prompt_layout
	prompt_layout=$(command zsh -fc 'source ./pure.zsh >/dev/null 2>&1; print -r -- $PROMPT')
	if [[ $prompt_layout != *'${prompt_pure_path_segment}'* || $prompt_layout != *'$(prompt_pure_render_dimmed_path)'* ]]; then
		print -u2 -- "Assertion failed: default PROMPT should support plain and dimmed path rendering"
		print -u2 -- "Actual: $prompt_layout"
		return 1
	fi
	local expanded_prompt
	expanded_prompt=$(command zsh -fc 'source ./pure.zsh >/dev/null 2>&1; print -r -- ${(S%%)PROMPT}')
	local dim=$'\e[2m'
	local nodim=$'\e[22m'
	local blue=$'\e[34m'
	local red=$'\e[31m'
	local expected_path=${(%):-%~}
	if [[ $expanded_prompt != *"${blue}${expected_path}"* || $expanded_prompt == *"${dim}/"* || $expanded_prompt == *"${nodim}"* || $expanded_prompt == *'}'* ]]; then
		print -u2 -- "Assertion failed: default PROMPT should not dim path separators"
		print -u2 -- "Actual: $expanded_prompt"
		return 1
	fi

	expanded_prompt=$(command zsh -fc 'source ./pure.zsh >/dev/null 2>&1; zstyle :prompt:pure:path color red; prompt_pure_set_colors; print -r -- ${(S%%)PROMPT}')
	if [[ $expanded_prompt != *"${red}${expected_path}"* ]]; then
		print -u2 -- "Assertion failed: default PROMPT should refresh path color"
		print -u2 -- "Actual: $expanded_prompt"
		return 1
	fi

	# Enabled via zstyle: separators should use ANSI dim attribute.
	zstyle ':prompt:pure:path:separator' dim yes
	local rendered_path
	rendered_path=$(prompt_pure_render_dimmed_path)
	if [[ $rendered_path != *"%{${dim}%}/%{${nodim}%}"* ]]; then
		print -u2 -- "Assertion failed: separators should use ANSI dim when enabled"
		print -u2 -- "Actual: $rendered_path"
		return 1
	fi
	if [[ $rendered_path != "%F{blue}"* ]]; then
		print -u2 -- "Assertion failed: path should start with path color"
		print -u2 -- "Actual: $rendered_path"
		return 1
	fi

	# Path without slashes (home directory itself).
	local saved_pwd=$PWD
	builtin cd -q ~
	rendered_path=$(prompt_pure_render_dimmed_path)
	assert_equal "%F{blue}~%f" "$rendered_path" "home directory with no slashes should produce no dim separators"
	builtin cd -q "$saved_pwd"

	# Absolute path outside home: leading / should not be dimmed.
	builtin cd -q /
	rendered_path=$(prompt_pure_render_dimmed_path)
	if [[ $rendered_path != "%F{blue}/"* ]]; then
		print -u2 -- "Assertion failed: leading slash on absolute path should not be dimmed"
		print -u2 -- "Actual: $rendered_path"
		builtin cd -q "$saved_pwd"
		return 1
	fi
	builtin cd -q "$saved_pwd"

	# Paths with percent characters are escaped.
	mkdir -p -- "$base_directory/a%b"
	builtin cd -q "$base_directory/a%b"
	rendered_path=$(prompt_pure_render_dimmed_path)
	if [[ $rendered_path != *"a%%b"* ]]; then
		print -u2 -- "Assertion failed: percent in path should be escaped as %%"
		print -u2 -- "Actual: $rendered_path"
		builtin cd -q "$saved_pwd"
		return 1
	fi
	builtin cd -q "$saved_pwd"

	# Prompt redraws without precmd should still show the current directory.
	mkdir -p -- "$base_directory/first/path" "$base_directory/second/path"
	local first_prompt second_prompt
	{
		read -r first_prompt
		read -r second_prompt
	} < <(
		command zsh -fc '
			typeset -g prompt_newline=" "
			zstyle ":prompt:pure:path:separator" dim yes
			source ./pure.zsh >/dev/null 2>&1
			typeset -gA prompt_pure_colors=(
				path blue
				prompt:success magenta
				prompt:error red
			)
			builtin cd -q "$1"
			local first_prompt=${(S%%)PROMPT}
			builtin cd -q "$2"
			local second_prompt=${(S%%)PROMPT}
			print -r -- "$first_prompt"
			print -r -- "$second_prompt"
		' zsh "$base_directory/first/path" "$base_directory/second/path"
	)
	if [[ $first_prompt != *"first"* || $second_prompt != *"second"* || $second_prompt == *"first"* ]]; then
		print -u2 -- "Assertion failed: dimmed path should update on prompt redraw without precmd"
		print -u2 -- "First prompt: $first_prompt"
		print -u2 -- "Second prompt: $second_prompt"
		return 1
	fi

	# PROMPT template renders the path dynamically.
	prompt_layout=$(command zsh -fc 'zstyle :prompt:pure:path:separator dim yes; source ./pure.zsh >/dev/null 2>&1; print -r -- $PROMPT')
	if [[ $prompt_layout != *'$(prompt_pure_render_dimmed_path)'* ]]; then
		print -u2 -- "Assertion failed: PROMPT should render path dynamically"
		print -u2 -- "Actual: $prompt_layout"
		return 1
	fi

	expanded_prompt=$(command zsh -fc 'zstyle :prompt:pure:path:separator dim yes; source ./pure.zsh >/dev/null 2>&1; print -r -- ${(S%%)PROMPT}')
	if [[ $expanded_prompt != *"${dim}/"* || $expanded_prompt != *"${nodim}"* || $expanded_prompt == *"$expected_path"* || $expanded_prompt == *'}'* ]]; then
		print -u2 -- "Assertion failed: expanded PROMPT should dim path separators"
		print -u2 -- "Actual: $expanded_prompt"
		return 1
	fi

	expanded_prompt=$(command zsh -fc 'source ./pure.zsh >/dev/null 2>&1; zstyle :prompt:pure:path:separator dim yes; prompt_pure_set_colors; print -r -- ${(S%%)PROMPT}')
	if [[ $expanded_prompt != *"${dim}/"* || $expanded_prompt != *"${nodim}"* || $expanded_prompt == *"$expected_path"* || $expanded_prompt == *'}'* ]]; then
		print -u2 -- "Assertion failed: path separator dimming should update after setup"
		print -u2 -- "Actual: $expanded_prompt"
		return 1
	fi

	print -- "path-separator tests passed"
}

main "$@"
