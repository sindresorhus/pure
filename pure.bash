# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
prompt_pure_human_time() {
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
	command git rev-parse --is-inside-work-tree &>/dev/null || return
	# check if it's dirty
	[[ "$PURE_GIT_UNTRACKED_DIRTY" == 0 ]] && local umode="-uno" || local umode="-unormal"
	command test -n "$(git status --porcelain --ignore-submodules ${umode})"

	(($? == 0)) && echo '*'
}

# displays the exec time of the last command if set threshold was exceeded
prompt_pure_cmd_exec_time() {
	local stop=$SECONDS
	local start=${cmd_timestamp:-$stop}
	local elapsed=$(($stop-$start))
	(($elapsed > ${PURE_CMD_MAX_EXEC_TIME:=5})) && prompt_pure_human_time $elapsed
}

prompt_pure_preexec() {
	# don't cause a preexec for $PROMPT_COMMAND
	[ "$BASH_COMMAND" = "$PROMPT_COMMAND" ] && return

	cmd_timestamp=${cmd_timestamp:-$SECONDS}

	local cwd=$(pwd | sed "s|^${HOME}|~|")
	local this_command=$(HISTTIMEFORMAT= history 1 | sed -e "s/^[ ]*[0-9]*[ ]*//");

	# shows the current dir and executed command in the title when a process is active
	echo -en "\e]0;"
	echo -nE "${cwd}: ${this_command}"
	echo -en "\a"
}

# string length ignoring ansi escapes
prompt_pure_string_length() {
	local str=$(echo -E "${1}" | sed 's/\\\e\[\([0-9]\+;\)\?[0-9]\+m\|\\n//g')
	echo ${#str}
}

prompt_pure_precmd() {
	local cwd=$(pwd | sed "s|^${HOME}|~|")

	# shows the full path in the title
	echo -en "\e]0;${cwd}\a"

	local prompt_pure_preprompt="\n\e[0;34m${cwd} \e[0;37m$(__git_ps1 "%s")$(prompt_pure_git_dirty) $prompt_pure_username\e[0m \e[0;33m$(prompt_pure_cmd_exec_time)\e[0m"
	echo -e $prompt_pure_preprompt

	# check async if there is anything to pull
	(( ${PURE_GIT_PULL:-1} )) && ({
		# check if we're in a git repo
		command git rev-parse --is-inside-work-tree &>/dev/null &&
		# check check if there is anything to pull
		command git fetch &>/dev/null &&
		# check if there is an upstream configured for this branch
		command git rev-parse --abbrev-ref @'{u}' &>/dev/null && {
			local arrows=''
			(( $(command git rev-list --right-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows='⇣'
			(( $(command git rev-list --left-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows+='⇡'
			echo -en "\e7\e[A\e[1G\e[$(prompt_pure_string_length "$prompt_pure_preprompt")C\e[0;36m${arrows}\e[0m\e8"
		}
	} &)

	# reset value since `preexec` isn't always triggered
	unset cmd_timestamp
}

prompt_pure_exit_color() {
	[[ "$?" = '0' ]] && echo -e "\e[0;37m" || echo -e "\e[0;31m"
}

prompt_pure_setup() {
	# prevent percentage showing up
	# if output doesn't end with a newline
	export PS2=''

	export PROMPT_COMMAND='prompt_pure_precmd'
	trap 'prompt_pure_preexec' DEBUG

	# show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && prompt_pure_username="${USER}@${HOSTNAME} "

	# prompt turns red if the previous command didn't exit with 0
	PS1='\[$(prompt_pure_exit_color)\]❯\[\e[0m\] '
}

prompt_pure_setup "$@"
