#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

main() {
	# prompt_pure_precmd references many env vars that may be unset.
	set +u

	zmodload zsh/datetime
	zmodload zsh/zutil

	prompt_pure_set_title() {
		:
	}

	prompt_pure_set_colors() {
		:
	}

	prompt_pure_check_cmd_exec_time() {
		:
	}

	prompt_pure_async_tasks() {
		:
	}

	typeset -gA prompt_pure_vcs_info=(pwd '' top '')
	typeset -gA prompt_pure_state=(prompt '❯')

	# Conda env should be shown by default.
	CONDA_DEFAULT_ENV=myenv
	prompt_pure_precmd
	assert_equal "myenv" "$psvar[20]" "conda env should be shown by default"

	# Conda env with full path should show only the basename.
	CONDA_DEFAULT_ENV=/path/to/envs/myenv
	prompt_pure_precmd
	assert_equal "myenv" "$psvar[20]" "conda env should show basename when set to full path"

	# Conda 'base' environment should be hidden.
	CONDA_DEFAULT_ENV=base
	prompt_pure_precmd
	assert_empty "$psvar[20]" "conda base environment should be hidden"

	# Conda 'base' environment with full path should also be hidden.
	CONDA_DEFAULT_ENV=/path/to/envs/base
	prompt_pure_precmd
	assert_empty "$psvar[20]" "conda base environment with full path should be hidden"

	# Conda env should be hidden when virtualenv style is off.
	zstyle ':prompt:pure:environment:virtualenv' show no
	prompt_pure_precmd
	assert_empty "$psvar[20]" "conda env should be hidden when virtualenv show is no"

	# Virtualenv should be hidden when virtualenv style is off.
	unset CONDA_DEFAULT_ENV
	VIRTUAL_ENV=/path/to/venvs/myvenv
	VIRTUAL_ENV_DISABLE_PROMPT=20
	prompt_pure_precmd
	assert_empty "$psvar[20]" "virtualenv should be hidden when virtualenv show is no"

	# VIRTUAL_ENV_DISABLE_PROMPT should not be set by precmd when virtualenv show is off.
	unset VIRTUAL_ENV_DISABLE_PROMPT
	prompt_pure_precmd
	assert_empty "${VIRTUAL_ENV_DISABLE_PROMPT-}" "VIRTUAL_ENV_DISABLE_PROMPT should not be set when virtualenv show is no"

	# Re-enable and verify virtualenv is shown.
	zstyle -d ':prompt:pure:environment:virtualenv' show
	prompt_pure_precmd
	assert_equal "myvenv" "$psvar[20]" "virtualenv should be shown when style is re-enabled"

	# Virtualenv with VIRTUAL_ENV_DISABLE_PROMPT unset (user handed control back).
	unset VIRTUAL_ENV_DISABLE_PROMPT
	prompt_pure_precmd
	assert_equal "myvenv" "$psvar[20]" "virtualenv should be shown when VIRTUAL_ENV_DISABLE_PROMPT is unset"

	# Conda env should be overridden by virtualenv when both are active.
	CONDA_DEFAULT_ENV=condaenv
	prompt_pure_precmd
	assert_equal "myvenv" "$psvar[20]" "virtualenv should take precedence over conda"

	# VIRTUAL_ENV_PROMPT should be preferred over VIRTUAL_ENV basename.
	VIRTUAL_ENV_PROMPT="custom-prompt"
	prompt_pure_precmd
	assert_equal "custom-prompt" "$psvar[20]" "VIRTUAL_ENV_PROMPT should be preferred"

	# Third-party VIRTUAL_ENV_DISABLE_PROMPT should be respected (Pure should not override).
	unset CONDA_DEFAULT_ENV VIRTUAL_ENV_PROMPT
	VIRTUAL_ENV_DISABLE_PROMPT=1
	prompt_pure_precmd
	assert_empty "$psvar[20]" "third-party VIRTUAL_ENV_DISABLE_PROMPT should be respected"

	# Nix-shell should still work when virtualenv style is off.
	unset VIRTUAL_ENV VIRTUAL_ENV_DISABLE_PROMPT
	zstyle ':prompt:pure:environment:virtualenv' show no
	IN_NIX_SHELL=pure
	name=my-nix-shell
	prompt_pure_precmd
	assert_equal "my-nix-shell" "$psvar[20]" "nix-shell should be independent of virtualenv style"
	unset IN_NIX_SHELL name
	zstyle -d ':prompt:pure:environment:virtualenv' show

	print -- "virtualenv tests passed"
}

main "$@"
