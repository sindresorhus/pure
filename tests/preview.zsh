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

	# A `%` in a symbol must render literally, like in the real prompt.
	zstyle ':prompt:pure:environment:node_version' symbol 'N%b'
	output=$(PURE_PROMPT_SYMBOL='%b' PURE_SUSPENDED_JOBS_SYMBOL='a%b' PURE_GIT_DOWN_ARROW='100%' PURE_GIT_STASH_SYMBOL='%F{red}' prompt_pure_preview 2>&1)

	for symbol in '%b' 'a%b' '100%' '%F{red}' 'N%b22'; do
		if [[ $output != *"$symbol"* ]]; then
			print -u2 -- "Preview did not render the symbol literally: $symbol"
			return 1
		fi
	done

	# A color set to the empty string must not corrupt the palette: iterating the colors must not drop empty values and shift the key/value pairs.
	typeset -gA prompt_pure_colors=("${(@kv)prompt_pure_colors_default}")
	zstyle ':prompt:pure:host' color ''
	local -a default_keys palette_keys
	default_keys=("${(@k)prompt_pure_colors_default}")
	local bogus
	# On the unfixed code the palette grows with every call, so call it a few times, and the corruption trips `nounset`: relax it so the run reaches the assertions below and fails with a readable message.
	set +eu
	local attempt
	for attempt in 1 2 3; do
		prompt_pure_set_colors 2>/dev/null || :
	done
	set -eu
	typeset -A known_colors
	known_colors=("${(@kv)prompt_pure_colors_default}")
	palette_keys=("${(@k)prompt_pure_colors}")
	bogus=()
	local key
	for key in "${palette_keys[@]}"; do
		[[ -n ${known_colors[$key]-} ]] || bogus+=($key)
	done
	assert_equal "${#default_keys[@]}" "${#palette_keys[@]}" "an empty color should not add keys to the palette"
	assert_empty "${(j:, :)bogus}" "an empty color should not add color-value keys to the palette"
	# The key/value pairing itself must survive: the empty `host` and the zstyle-set `path` color stay attached to their own keys.
	assert_empty "${prompt_pure_colors[host]}" "an empty color should keep its value on its own key"
	assert_equal "red" "${prompt_pure_colors[path]}" "a zstyle color should stay on its own key"

	print "preview tests passed."
}

main "$@"
