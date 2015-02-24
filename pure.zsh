# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)


# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
prompt_pure_human_time() {
	echo -n " "
	local tmp=$1
	local days=$(( tmp / 60 / 60 / 24 ))
	local hours=$(( tmp / 60 / 60 % 24 ))
	local minutes=$(( tmp / 60 % 60 ))
	local seconds=$(( tmp % 60 ))
	(( $days > 0 )) && echo -n "${days}d "
	(( $hours > 0 )) && echo -n "${hours}h "
	(( $minutes > 0 )) && echo -n "${minutes}m "
	echo "${seconds}s"
}

# fastest possible way to check if repo is dirty
prompt_pure_git_dirty() {
	# check if we're in a git repo
	[[ "$(command git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] || return
	# check if it's dirty
	[[ "$PURE_GIT_UNTRACKED_DIRTY" == 0 ]] && local umode="-uno" || local umode="-unormal"
	command test -n "$(git status --porcelain --ignore-submodules ${umode})"

	(($? == 0)) && echo '*'
}

# displays the exec time of the last command if set threshold was exceeded
prompt_pure_cmd_exec_time() {
	local stop=$EPOCHSECONDS
	local start=${cmd_timestamp:-$stop}
	integer elapsed=$stop-$start
	(($elapsed > ${PURE_CMD_MAX_EXEC_TIME:=5})) && prompt_pure_human_time $elapsed
}

prompt_pure_preexec() {
	cmd_timestamp=$EPOCHSECONDS

	# shows the current dir and executed command in the title when a process is active
	print -Pn "\e]0;"
	echo -nE "$PWD:t: $2"
	print -Pn "\a"
}

# string length ignoring ansi escapes
prompt_pure_string_length() {
	# Subtract one since newline is counted as two characters
	echo $(( ${#${(S%%)1//(\%([KF1]|)\{*\}|\%[Bbkf])}} - 1 ))
}

prompt_pure_git_render_arrows() {
	# check that no command is currently running, would likely cause the arrows to render in incorrect position
	[[ ! -n ${cmd_timestamp+x} ]] &&
	# check if we're in a git repo
	prompt_pure_is_git_repository &&
	# check if there is an upstream configured for this branch
	command git rev-parse --abbrev-ref @'{u}' &>/dev/null && {
		local arrows=''
		(( $(command git rev-list --right-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows='⇣'
		(( $(command git rev-list --left-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows+='⇡'
		print -Pn "\e7\e[A\e[1G\e[${prompt_pure_preprompt_length}C%F{cyan}${arrows}%f\e8"
	}
}

prompt_pure_is_git_repository() {
	[[ "$(command git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] || return 1
}

prompt_pure_git_fetch() {
	prompt_pure_git_fetch_complete=0
	local pid=$$
	# check async if there is anything to pull
	(( ${PURE_GIT_PULL:-1} )) && {
		# check if we're in a git repo
		prompt_pure_is_git_repository &&
		# make sure working tree is not $HOME
		[[ "$(command git rev-parse --show-toplevel)" != "$HOME" ]] &&
		# check check if there is anything to pull
		command git fetch &>/dev/null
		# always send completion signal to parent process
		command kill -INFO $pid
	} &!
}

prompt_pure_git_fetch_compelte_trap() {
	# mark git fetch as completed and draw arrows
	prompt_pure_git_fetch_complete=1
	prompt_pure_git_render_arrows
}

prompt_pure_chpwd() {
	# prefix working_tree with x as to not match current path, affects variable resolution
	local working_tree="x$(command git rev-parse --show-toplevel 2>/dev/null)"

	# check if the working tree has changed and run git fetch immediately
	if [ "${prompt_pure_working_tree}" != "${working_tree}" ]; then
		prompt_pure_working_tree=$working_tree
		prompt_pure_git_fetch
	fi
}

prompt_pure_precmd() {
	# set up a trap to catch git fetch updates
	trap prompt_pure_git_fetch_compelte_trap INFO

	# shows the full path in the title
	print -Pn '\e]0;%~\a'

	# git info
	vcs_info

	local prompt_pure_preprompt="\n%F{blue}%~%F{242}$vcs_info_msg_0_`prompt_pure_git_dirty`$prompt_pure_username%f%F{yellow}`prompt_pure_cmd_exec_time`%f"
	print -P $prompt_pure_preprompt

	prompt_pure_preprompt_length=$(prompt_pure_string_length $prompt_pure_preprompt)

	# reset value since `preexec` isn't always triggered
	unset cmd_timestamp

	# draw arrows based on current git status
	prompt_pure_git_render_arrows

	# try to do a new fetch if a previous fetch is not running
	(( $prompt_pure_git_fetch_complete )) && prompt_pure_git_fetch
}

prompt_pure_setup() {
	# prevent percentage showing up
	# if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	# disable auth prompting on git 2.3+
	export GIT_TERMINAL_PROMPT=0

	prompt_opts=(cr subst percent)

	zmodload zsh/datetime
	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec
	add-zsh-hook chpwd prompt_pure_chpwd

	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:git*' formats ' %b'
	zstyle ':vcs_info:git*' actionformats ' %b|%a'

	# show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && prompt_pure_username=' %n@%m '

	# show username@host if root, with username in white
	[[ $UID -eq 0 ]] && prompt_pure_username=' %F{white}%n%F{242}@%m '

	# prompt turns red if the previous command didn't exit with 0
	PROMPT="%(?.%F{magenta}.%F{red})${PURE_PROMPT_SYMBOL:-❯}%f "
}

prompt_pure_setup "$@"
