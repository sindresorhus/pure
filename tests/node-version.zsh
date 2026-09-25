#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

main() {
	zmodload -F zsh/files b:zf_rm

	local base_directory=$PWD/.ai-temporary/pure-node-version-$$
	local bin_directory=$base_directory/bin
	local second_bin_directory=$base_directory/bin-second
	local project_directory=$base_directory/project
	local nested_directory=$project_directory/deep/nested
	local outside_directory=/
	local counter_path=$base_directory/node-count

	trap "zf_rm -rf -- ${(q)base_directory}" EXIT

	mkdir -p -- "$bin_directory" "$second_bin_directory" "$nested_directory"
	: > "$project_directory/package.json"
	: > "$counter_path"

	local node_path=$bin_directory/node
	cat > "$node_path" <<EOF
#!/bin/sh
count=\$(cat "$counter_path")
count=\$((count + 1))
printf '%s' "\$count" > "$counter_path"
printf '%s\n' 'v25.8.0'
EOF
	chmod +x "$node_path"

	local second_node_path=$second_bin_directory/node
	cat > "$second_node_path" <<EOF
#!/bin/sh
count=\$(cat "$counter_path")
count=\$((count + 1))
printf '%s' "\$count" > "$counter_path"
printf '%s\n' 'v26.1.0'
EOF
	chmod +x "$second_node_path"

	prompt_pure_async_init() {
		:
	}

	async_worker_eval() {
		:
	}

	async_flush_jobs() {
		:
	}

	async_job() {
		:
	}

	typeset -gA prompt_pure_vcs_info=(pwd '' top '')
	zstyle ':prompt:pure:environment:node_version' show yes
	local prompt_layout=$(command zsh -fc 'source ./pure.zsh >/dev/null 2>&1; print -r -- $PROMPT')
	local before_stash=${prompt_layout%%"%(18V."*}
	local before_node_version=${prompt_layout%%"%(21V."*}
	local before_execution_time=${prompt_layout%%"%(19V."*}
	local before_newline=${prompt_layout%%'${prompt_newline}'*}
	local before_virtualenv=${prompt_layout%%"%(20V."*}
	if (( ${#before_stash} >= ${#before_node_version} || ${#before_node_version} >= ${#before_execution_time} || ${#before_execution_time} >= ${#before_newline} || ${#before_newline} >= ${#before_virtualenv} )); then
		print -u2 -- "Assertion failed: node version should render after git stash and before execution time on the preprompt line"
		return 1
	fi

	PATH="$bin_directory:/usr/bin:/bin"
	builtin cd -q "$nested_directory"
	prompt_pure_async_tasks || :
	assert_equal "25" "${prompt_pure_node_version-}" "node version should be set synchronously inside a package.json tree"
	assert_equal "1" "$(cat "$counter_path")" "node should be resolved on the first prompt in a package.json tree"

	prompt_pure_async_tasks || :
	assert_equal "25" "${prompt_pure_node_version-}" "node version should be reused when directory and PATH do not change"
	assert_equal "1" "$(cat "$counter_path")" "node should not be resolved again when directory and PATH are unchanged"

	PATH="$second_bin_directory:/usr/bin:/bin"
	prompt_pure_async_tasks || :
	assert_equal "26" "${prompt_pure_node_version-}" "node version should be refreshed when PATH changes"
	assert_equal "2" "$(cat "$counter_path")" "node should be resolved again when PATH changes"

	prompt_pure_vcs_info[pwd]=$outside_directory
	prompt_pure_async_tasks || :
	assert_equal "26" "${prompt_pure_node_version-}" "node version should survive git working tree state reset"
	assert_equal "2" "$(cat "$counter_path")" "node should not be resolved again when git working tree state resets"

	zstyle ':prompt:pure:git' show no
	unset prompt_pure_node_version
	unset prompt_pure_node_cache_key
	prompt_pure_async_tasks || :
	assert_equal "26" "${prompt_pure_node_version-}" "node version should still be set when git integration is disabled"
	assert_equal "3" "$(cat "$counter_path")" "node should be resolved when git integration is disabled"
	zstyle -d ':prompt:pure:git' show

	builtin cd -q "$outside_directory"
	prompt_pure_async_tasks || :
	assert_empty "${prompt_pure_node_version-}" "node version should be cleared outside a package.json tree"

	# Creating or removing package.json in the current directory updates the version without changing directory.
	# The directory is outside the repository, which has its own package.json.
	local new_project_directory=$(mktemp -d "${TMPDIR:-/tmp}/pure-node-version-project.XXXXXX")
	trap "zf_rm -rf -- ${(q)base_directory} ${(q)new_project_directory}" EXIT
	builtin cd -q "$new_project_directory"
	prompt_pure_async_tasks || :
	assert_empty "${prompt_pure_node_version-}" "node version should be empty before package.json exists"
	: > package.json
	prompt_pure_async_tasks || :
	assert_equal "26" "${prompt_pure_node_version-}" "node version should be shown after package.json is created"
	zf_rm package.json
	prompt_pure_async_tasks || :
	assert_empty "${prompt_pure_node_version-}" "node version should be cleared after package.json is removed"

	# Moving within the same package does not resolve node again.
	builtin cd -q "$nested_directory"
	prompt_pure_async_tasks || :
	local node_count=$(<"$counter_path")
	builtin cd -q "$project_directory"
	prompt_pure_async_tasks || :
	assert_equal "26" "${prompt_pure_node_version-}" "node version should be kept within the same package"
	assert_equal "$node_count" "$(<"$counter_path")" "node should not be resolved again within the same package"

	# Without `node`, nothing is shown.
	local no_node_directory=$base_directory/no-node
	mkdir -p -- "$no_node_directory"
	local saved_path=$PATH
	PATH=$no_node_directory
	prompt_pure_async_tasks || :
	PATH=$saved_path
	assert_empty "${prompt_pure_node_version-}" "node version should be empty when node is not installed"

	zstyle ':prompt:pure:environment:node_version' show no
	builtin cd -q "$nested_directory"
	typeset -g prompt_pure_node_version=stale
	prompt_pure_async_tasks || :
	assert_empty "${prompt_pure_node_version-}" "node version should stay disabled when the style is off"

	# The version is parsed even when `node` prefixes it with whitespace or a newline (some version-manager shims do).
	local whitespace_bin_directory=$base_directory/bin-whitespace
	mkdir -p -- "$whitespace_bin_directory"
	cat > "$whitespace_bin_directory/node" <<'EOF'
#!/bin/sh
printf '\n \tv25.8.0\r\n'
EOF
	chmod +x "$whitespace_bin_directory/node"
	assert_equal "25" "$(PATH="$whitespace_bin_directory:/usr/bin:/bin" prompt_pure_check_node_version)" "leading whitespace and a trailing carriage return should be stripped from the node version"

	print -- "node-version tests passed"
}

main "$@"
