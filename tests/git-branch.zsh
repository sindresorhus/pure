#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

# Renders the preprompt for the Git repository in $1 through the real async pipeline: `prompt_pure_async_vcs_info` output is fed to the callback, and PROMPT is then expanded. The optional $2 is evaluated first, to simulate the user's `.zshrc`. Sets `preprompt` and `git_top`.
render_preprompt() {
	local output
	output=$(command zsh -fc '
		setopt extendedglob
		source ./pure.zsh >/dev/null 2>&1
		eval "$2"
		async_job() {
			:
		}
		builtin cd -q "$1"
		typeset -g prompt_pure_async_inited=1
		typeset -g PROMPT_PURE_WORKER_GENERATION=1
		typeset -gA prompt_pure_worker_env=(pwd "$PWD" generation 1)
		prompt_pure_async_callback prompt_pure_async_vcs_info 0 "$(prompt_pure_async_vcs_info)" 0 "" 0
		prompt_pure_preprompt_render
		local preprompt=${${(S%%)PROMPT}%%$'\''\n'\''*}
		# The top-level comes first, as the command substitution drops a trailing empty line.
		print -r -- $prompt_pure_vcs_info[top]
		# Strip color escape sequences.
		print -r -- ${preprompt//$'\''\e'\''\[[0-9;]#m}
	' zsh "$1" "${2-}")
	typeset -g git_top=${output%%$'\n'*} preprompt=${output#*$'\n'}
}

main() {
	zmodload -F zsh/files b:zf_rm b:zf_mkdir

	local repository=$PWD/.ai-temporary/pure-git-branch-$$
	trap "zf_rm -rf -- ${(q)repository}" EXIT
	zf_mkdir -p -- "$repository"
	command git -C "$repository" init -q --template=
	local expected_path=${repository/#$HOME/\~}

	local branch
	for branch in 'feat%2' '100%' 'a%%b' '%F{red}x%f' 'x$HOME' "it's" 'main'; do
		command git -C "$repository" symbolic-ref HEAD "refs/heads/$branch"
		render_preprompt "$repository"
		assert_equal "$expected_path $branch" "$preprompt" "branch '$branch' should be rendered literally"
	done

	# The user's own `vcs_info` styles and hooks should not affect Pure.
	local user_setup
	for user_setup in \
		'zstyle ":vcs_info:git:*" formats "%F{green}%b%f"; zstyle ":vcs_info:git:*" actionformats "%b|%a"' \
		'zstyle ":vcs_info:*" max-exports 1' \
		'zstyle ":vcs_info:*" enable hg' \
		'zstyle ":vcs_info:git*:*" use-simple false' \
		'zstyle ":vcs_info:git*+set-message:*" hooks add-suffix; +vi-add-suffix() { hook_com[branch]+=-suffix }' \
		'autoload -Uz vcs_info_hookadd; vcs_info_hookadd set-message add-suffix; +vi-add-suffix() { hook_com[branch]+=-suffix }' \
		'zstyle ":vcs_info:*" debug true'
	do
		render_preprompt "$repository" "$user_setup"
		assert_equal "$expected_path main" "$preprompt" "user vcs_info config should not change the branch: $user_setup"
		assert_equal "$repository" "$git_top" "user vcs_info config should not change the Git top-level: $user_setup"
	done

	# Outside a repository, the user's `nvcsformats` messages should not be shown as a branch or taken as a Git top-level.
	render_preprompt / 'zstyle ":vcs_info:*" nvcsformats "no repository" /tmp'
	assert_equal "/" "$preprompt" "user nvcsformats should not be shown outside a repository"
	assert_empty "$git_top" "user nvcsformats should not set a Git top-level outside a repository"

	# The user's `vcs_info` styles should not make Pure run extra Git commands, as Pure checks dirtiness itself, with caching for slow repositories.
	local base_directory=$repository.bin
	trap "zf_rm -rf -- ${(q)repository} ${(q)base_directory}" EXIT
	zf_mkdir -p -- "$base_directory"
	create_logging_git "$base_directory" "$base_directory/git.log"
	local git_calls
	git_calls=$(builtin cd -q "$repository" && PATH="$base_directory:$PATH" command zsh -fc '
		source "$1/pure.zsh" >/dev/null 2>&1
		zstyle ":vcs_info:*" check-for-changes true
		zstyle ":vcs_info:*" check-for-staged-changes true
		zstyle ":vcs_info:*" get-revision true
		prompt_pure_async_vcs_info >/dev/null
		command cat "$2/git.log"
	' zsh "$OLDPWD" "$base_directory")
	# The exact list of Git commands is what is asserted, so merging or reordering the calls that `vcs_info` runs is a deliberate change to this test.
	assert_equal "rev-parse --git-dir|rev-parse --show-toplevel|symbolic-ref HEAD" "${(j:|:)${(f)git_calls}}" "user vcs_info styles should not add Git commands"

	# An action in progress is rendered after the branch.
	command git -C "$repository" -c user.name=Test -c user.email=test@test.com commit -q --allow-empty -m initial
	command git -C "$repository" rev-parse HEAD >| "$repository/.git/MERGE_HEAD"
	: >| "$repository/.git/MERGE_MSG"
	render_preprompt "$repository"
	assert_equal "$expected_path main merge" "$preprompt" "a merge in progress should be rendered"
	render_preprompt "$repository" 'zstyle ":vcs_info:git:*" actionformats "%F{red}%b|%a%f"'
	assert_equal "$expected_path main merge" "$preprompt" "user actionformats should not change the action"

	# A subdirectory reports the repository top-level.
	zf_mkdir -p -- "$repository/sub"
	render_preprompt "$repository/sub"
	assert_equal "$expected_path/sub main merge" "$preprompt" "a subdirectory should render the branch and action"
	assert_equal "$repository" "$git_top" "a subdirectory should report the repository top-level"

	print -- "git-branch tests passed"
}

main "$@"
