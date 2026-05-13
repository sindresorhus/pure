#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

main() {
	# Set up colors like prompt_pure_setup would.
	typeset -gA prompt_pure_colors=(
		custom:prefix        242
		custom:suffix        242
		execution_time       yellow
		git:arrow            cyan
		git:stash            cyan
		git:branch           242
		git:branch:cached    red
		git:action           yellow
		git:dirty            218
		host                 242
		node_version         green
		path                 blue
		prompt:error         red
		prompt:success       magenta
		prompt:continuation  242
		suspended_jobs       red
		user                 242
		user:root            default
		virtualenv           242
	)
	typeset -gA prompt_pure_colors_default
	prompt_pure_colors_default=("${(@kv)prompt_pure_colors}")

	local output
	output=$(prompt_pure_preview 2>&1)

	for component in prefix suffix zaphod heartofgold "~/dev/pure" "main" "rebase-i" "42s" "venv" "prompt after error" "continuation prompt" "root" "branch color when data is cached"; do
		if [[ $output != *"$component"* ]]; then
			print -u2 "Missing component in preview output: $component"
			return 1
		fi
	done

	zstyle ':prompt:pure:path' color red
	output=$(prompt_pure_preview 2>&1)

	if [[ $output != *$'\e[31m~/dev/pure'* ]]; then
		print -u2 "Preview did not apply zstyle path color."
		return 1
	fi

	zstyle ':prompt:pure:environment:node_version' symbol '⬡'
	output=$(prompt_pure_preview 2>&1)

	if [[ $output != *'⬡22'* ]]; then
		print -u2 "Preview did not apply zstyle Node.js symbol."
		return 1
	fi

	zstyle ':prompt:pure:path:separator' dim yes
	output=$(prompt_pure_preview 2>&1)

	if [[ $output != *$'\e[2m/\e[22m'* ]]; then
		print -u2 "Preview did not apply dimmed path separators."
		return 1
	fi

	zstyle ':prompt:pure:host' show no
	output=$(prompt_pure_preview 2>&1)

	if [[ $output == *'heartofgold'* ]]; then
		print -u2 "Preview should not show hostname when host display is disabled."
		return 1
	fi

	if [[ $output != *'zaphod'* ]]; then
		print -u2 "Preview should still show username when host display is disabled."
		return 1
	fi

	print "preview tests passed."
}

main "$@"
