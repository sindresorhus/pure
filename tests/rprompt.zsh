#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"

main() {
	# Simulate a framework that sets RPROMPT before Pure loads.
	# Pure should clear it during setup since it does not use a right prompt.
	local rprompt_after
	rprompt_after=$(command zsh -fc 'RPROMPT="%~"; source ./pure.zsh >/dev/null 2>&1; print -r -- "$RPROMPT"')
	assert_empty "$rprompt_after" "RPROMPT should be cleared by pure setup"

	print -- "rprompt tests passed"
}

main "$@"
